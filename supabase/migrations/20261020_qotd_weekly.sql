create table if not exists public.qotd_freq(hotel_id text references public.hotels(id) on delete cascade, role text not null,
  freq text not null check (freq in ('daily','weekly')), updated_by uuid, updated_at timestamptz default now(), primary key(hotel_id,role));
alter table public.qotd_freq enable row level security;
drop policy if exists qotd_freq_read on public.qotd_freq;
create policy qotd_freq_read on public.qotd_freq for select using (hotel_id=private.my_hotel() or private.is_above());
create or replace function private.qotd_freq(h text, r text) returns text language sql stable security definer set search_path=public as $$
  select coalesce((select freq from qotd_freq where hotel_id=h and role=r),
    case when r in ('front_desk','night_audit','gm') then 'daily' else 'weekly' end) $$;
create or replace function private.qotd_period(h text, r text, d date) returns date language sql stable as $$
  select case when private.qotd_freq(h,r)='weekly' then date_trunc('week',d)::date else d end $$;
create or replace function public.qotd_set_freq(p_hotel text, p_role text, p_freq text) returns void language plpgsql security definer set search_path=public,private as $$
begin
  if not (private.is_above() or (private.is_mgr_of(p_hotel) and private.my_role() in ('gm','agm'))) then raise exception 'not allowed'; end if;
  insert into qotd_freq(hotel_id,role,freq,updated_by) values (p_hotel,p_role,p_freq,auth.uid())
    on conflict (hotel_id,role) do update set freq=excluded.freq, updated_by=auth.uid(), updated_at=now();
end $$;
create or replace function public.qotd_get_freq(p_hotel text) returns table(role text, freq text) language sql stable security definer set search_path=public,private as $$
  select r, private.qotd_freq(p_hotel,r) from unnest(array['front_desk','night_audit','room_attendant','laundry','houseman','hk_supervisor','maintenance','breakfast','driver','bartender','gm']) r $$;
insert into public.points_rules(hotel_id,reason,label_en,label_es,points,daily_cap,params)
select h.id, r.* from public.hotels h cross join (values
 ('qotd_answer_week','Question of the Week answered','Pregunta de la semana respondida',5,1,'{}'::jsonb),
 ('qotd_correct_week','Question of the Week correct','Pregunta de la semana correcta',25,1,'{}'::jsonb)) r(a,b,c,d,e,f)
on conflict (hotel_id,reason) do nothing;
drop function if exists public.qotd_pool_health(text);
create or replace function public.qotd_pool_health(p_hotel text) returns table(role text, freq text, users int, min_unseen int, periods_left int, warn boolean)
language sql security definer set search_path=public,private as $$
  with u as (select p.user_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) r from profiles p where p.hotel_id=p_hotel),
  br as (select brand from hotels where id=p_hotel),
  c as (select u.r, u.user_id, (select count(*) from qotd_questions x where x.active and x.es_reviewed and u.r=any(x.roles)
          and x.brand in ('all',(select brand from br)) and (x.hotel_id is null or x.hotel_id=p_hotel)
          and (x.review_by is null or x.review_by>=current_date)
          and not exists (select 1 from qotd_daily y where y.user_id=u.user_id and y.question_id=x.id))::int n from u)
  -- warn when remaining unseen pool covers < 90 days (daily = 90 questions, weekly = 13 questions)
  select r, private.qotd_freq(p_hotel,r), count(*)::int, min(n), min(n),
    min(n) < case when private.qotd_freq(p_hotel,r)='weekly' then 13 else 90 end
  from c where private.is_mgr_of(p_hotel) or private.is_above() group by r order by 6 desc, 4 $$;
-- ~80% own-role, ~20% relevant shared; light brand question at most once per 7 days; spaced-repetition reviews first
create or replace function public.get_qotd() returns jsonb language plpgsql security definer set search_path=public,private as $$
declare u uuid := auth.uid(); h text; qr text; br text; pd date; fr text; d date := (now() at time zone 'America/Chicago')::date;
  row_ qotd_daily; qid bigint; rev boolean := false; qq qotd_questions; st user_stats; want text; light_ok boolean;
begin
  if u is null then raise exception 'sign in'; end if;
  select p.hotel_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) into h, qr from profiles p where p.user_id=u;
  select brand into br from hotels where id=h; fr := private.qotd_freq(h,qr); pd := private.qotd_period(h,qr,d);
  select * into row_ from qotd_daily where user_id=u and day=pd;
  if not found then
    select r.question_id into qid from qotd_review r join qotd_questions x on x.id=r.question_id and x.active and qr=any(x.roles) and (x.hotel_id is null or x.hotel_id=h)
      where r.user_id=u and r.due_date<=d order by r.due_date, random() limit 1;
    rev := qid is not null;
    if qid is null then
      light_ok := not exists (select 1 from qotd_daily y join qotd_questions x on x.id=y.question_id where y.user_id=u and y.day>pd-(case when fr='weekly' then 42 else 7 end) and x.kind='brand_light');
      want := case when random()<0.8 then 'role' else 'shared' end;
      select x.id into qid from qotd_questions x where x.active and x.es_reviewed and x.brand in ('all',br) and qr=any(x.roles) and private.qotd_live(x.hotel_id,x.season_start,x.season_end,x.review_by,h,d)
        and (x.kind<>'brand_light' or light_ok)
        and not exists (select 1 from qotd_daily y where y.user_id=u and y.question_id=x.id)
        order by (x.season_start is not null) desc, case when x.kind=want or (want='shared' and x.kind='brand_light') then 0 else 1 end, random() limit 1;
    end if;
    if qid is null then
      select x.id into qid from qotd_questions x where x.active and x.es_reviewed and x.brand in ('all',br) and qr=any(x.roles) and private.qotd_live(x.hotel_id,x.season_start,x.season_end,x.review_by,h,d) and x.kind<>'brand_light'
        order by (select max(day) from qotd_daily y where y.user_id=u and y.question_id=x.id) nulls first, random() limit 1;
    end if;
    if qid is null then return null; end if;
    insert into qotd_daily(user_id,day,hotel_id,question_id,role_group,is_review) values (u,pd,h,qid,qr,rev) on conflict do nothing;
    select * into row_ from qotd_daily where user_id=u and day=pd;
  end if;
  select * into qq from qotd_questions where id=row_.question_id;
  select * into st from user_stats where user_id=u;
  return jsonb_build_object('day',pd,'freq',fr,'period_end',case when fr='weekly' then pd+6 else pd end,'question_id',qq.id,'topic',qq.topic,'is_review',row_.is_review,'role',qr,
    'question_en',qq.question_en,'question_es',qq.question_es,'options_en',qq.options_en,'options_es',qq.options_es,
    'answered',row_.answered_at is not null,'answered_idx',row_.answered_idx,'correct',row_.correct,
    'correct_idx',case when row_.answered_at is not null then qq.correct_idx end,
    'explain_en',case when row_.answered_at is not null then qq.explain_en end,
    'explain_es',case when row_.answered_at is not null then qq.explain_es end,
    'source_url',case when row_.answered_at is not null then qq.source_url end,
    'streak',coalesce(st.qotd_streak,0));
end $$;
create or replace function public.answer_qotd(p_idx int) returns jsonb language plpgsql security definer set search_path=public,private as $$
declare u uuid := auth.uid(); d date := (now() at time zone 'America/Chicago')::date; row_ qotd_daily; qq qotd_questions;
  ok boolean; pts int := 0; h text; qr text; fr text; pd date; step int; st user_stats; badge_before int; badge_after int;
begin
  select p.hotel_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) into h, qr from profiles p where p.user_id=u;
  fr := private.qotd_freq(h,qr); pd := private.qotd_period(h,qr,d); step := case when fr='weekly' then 7 else 1 end;
  select * into row_ from qotd_daily where user_id=u and day=pd for update;
  if not found then raise exception 'no question today'; end if;
  if row_.answered_at is not null then raise exception 'already answered'; end if;
  select * into qq from qotd_questions where id=row_.question_id;
  if p_idx is null or p_idx<0 or p_idx>=jsonb_array_length(qq.options_en) then raise exception 'bad option'; end if;
  ok := p_idx=qq.correct_idx;
  update qotd_daily set answered_idx=p_idx, correct=ok, answered_at=now() where user_id=u and day=pd;
  -- streak (consecutive days answered, right or wrong)
  insert into user_stats(user_id,hotel_id) values (u,row_.hotel_id) on conflict do nothing;
  update user_stats set qotd_streak=case when qotd_last=pd-step then qotd_streak+1 when qotd_last=pd then qotd_streak else 1 end,
    qotd_last=pd where user_id=u returning * into st;
  update user_stats set qotd_best=greatest(qotd_best,qotd_streak) where user_id=u;
  -- spaced repetition: miss -> due in 3 days, then 7, 14; correct on review -> doubled interval, removed after 14+
  if not ok then
    insert into qotd_review(user_id,question_id,due_date,interval_days) values (u,qq.id,d+3*step,3*step)
      on conflict (user_id,question_id) do update set due_date=d+3*step, interval_days=3*step, misses=qotd_review.misses+1;
  elsif row_.is_review then
    update qotd_review set interval_days=interval_days*2, due_date=d+interval_days*2 where user_id=u and question_id=qq.id;
    delete from qotd_review where user_id=u and question_id=qq.id and interval_days>14*step;
  end if;
  select count(*) into badge_before from user_badges where user_id=u and code='brainiac';
  pts := private.award(u,row_.hotel_id,case when fr='weekly' then 'qotd_answer_week' else 'qotd_answer' end,'qotd',u::text||':'||pd);
  if ok then pts := pts + private.award(u,row_.hotel_id,case when fr='weekly' then 'qotd_correct_week' else 'qotd_correct' end,'qotd',u::text||':'||pd); end if;
  perform private.refresh_stats(u,row_.hotel_id);
  select count(*) into badge_after from user_badges where user_id=u and code='brainiac';
  return jsonb_build_object('correct',ok,'correct_idx',qq.correct_idx,'points',pts,'streak',st.qotd_streak,
    'explain_en',qq.explain_en,'explain_es',qq.explain_es,'source_url',qq.source_url,'new_badge',badge_after>badge_before,'freq',fr);
end $$;
