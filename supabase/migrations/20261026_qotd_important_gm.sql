-- QOTD: important flag (GM-editable per hotel), 90-day refresh of important questions, GMs/AGMs no longer get QOTD,
-- and a GM "What my team is missing" view + weekly push summary (EN/ES).

-- 1) important flag + per-hotel GM override
alter table public.qotd_questions add column if not exists important boolean not null default false;
create table if not exists public.qotd_important_override (
  hotel_id text not null, question_id bigint not null references public.qotd_questions(id) on delete cascade,
  important boolean not null, set_by uuid, set_at timestamptz not null default now(), primary key (hotel_id, question_id));
alter table public.qotd_important_override enable row level security;
drop policy if exists qio_read on public.qotd_important_override;
create policy qio_read on public.qotd_important_override for select to authenticated using (private.is_above() or private.is_mgr_of(hotel_id));

create or replace function private.qotd_is_important(p_q bigint, p_hotel text) returns boolean
language sql stable security definer set search_path=public as $$
  select coalesce((select o.important from qotd_important_override o where o.hotel_id=p_hotel and o.question_id=p_q),
                  (select q.important from qotd_questions q where q.id=p_q), false) $$;

-- pre-set: critical safety / fire / emergency / cash / PCI / alcohol / ADA / trafficking
update public.qotd_questions set important=true where
  topic in ('fire','fire_panel','emergency','emergency_lights','exits','exit_signs','tornado','cpr','aed','choking','stroke','co','loto','lockout','gas',
            'cash','count','payments','pci','scam','liquor','dui','age','id','intox','ada','accessibility','trafficking','weapons','bloodborne','sharps','allergens','safety','security')
  or topics && array['fire','emergency','cash','pci','payments','alcohol','liquor','ada','trafficking','allergens']::text[]
  or question_en ~* '(fire alarm|evacuat|\mAED\M|\mCPR\M|traffick|service animal|intoxicat|fake ID|proof of age|card number|counterfeit|carbon monoxide|lockout|tagout)';

create or replace function public.qotd_set_important(p_hotel text, p_id bigint, p_important boolean) returns void
language plpgsql security definer set search_path=public,private as $$
begin
  if not (private.is_above() or private.is_mgr_of(p_hotel)) then raise exception 'not allowed'; end if;
  insert into qotd_important_override(hotel_id,question_id,important,set_by) values (p_hotel,p_id,p_important,auth.uid())
    on conflict (hotel_id,question_id) do update set important=excluded.important, set_by=auth.uid(), set_at=now();
end $$;
create or replace function public.qotd_important_list(p_hotel text) returns table(question_id bigint, important boolean)
language sql stable security definer set search_path=public,private as $$
  select q.id, private.qotd_is_important(q.id,p_hotel) from qotd_questions q
  where (private.is_above() or private.is_mgr_of(p_hotel)) and (q.important or exists (select 1 from qotd_important_override o where o.hotel_id=p_hotel and o.question_id=q.id)) $$;

-- 2) GMs/AGMs/above-property don't get QOTD: remove 'gm' from audiences; GM-only questions retire
update public.qotd_questions set roles=array_remove(roles,'gm') where 'gm'=any(roles);
update public.qotd_questions set active=false, retired_at=coalesce(retired_at,now()) where cardinality(roles)=0 and active;

-- 3) get_qotd: no question for managers; missed reviews first; then (max 1 in 3 days / 1 in 2 weeks) an important question last seen 90+ days ago
create or replace function public.get_qotd() returns jsonb
language plpgsql security definer set search_path=public,private as $function$
declare u uuid := auth.uid(); h text; qr text; br text; pd date; fr text; d date := (now() at time zone 'America/Chicago')::date;
  row_ qotd_daily; qid bigint; rev boolean := false; qq qotd_questions; st user_stats; want text; light_ok boolean; win int;
begin
  if u is null then raise exception 'sign in'; end if;
  select p.hotel_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) into h, qr from profiles p where p.user_id=u;
  if qr is null or qr='gm' then return null; end if;
  select brand into br from hotels where id=h; fr := private.qotd_freq(h,qr); pd := private.qotd_period(h,qr,d);
  select * into row_ from qotd_daily where user_id=u and day=pd;
  if not found then
    select r.question_id into qid from qotd_review r join qotd_questions x on x.id=r.question_id and x.active and qr=any(x.roles) and (x.hotel_id is null or x.hotel_id=h)
      where r.user_id=u and r.due_date<=d order by r.due_date, random() limit 1;
    if qid is null then
      win := case when fr='weekly' then 14 else 3 end;
      if not exists (select 1 from qotd_daily y where y.user_id=u and y.day>pd-win and y.is_review) then
        select x.id into qid from qotd_questions x
          join lateral (select max(y.day) last_day from qotd_daily y where y.user_id=u and y.question_id=x.id and y.answered_at is not null) l on true
          where x.active and x.es_reviewed and x.brand in ('all',br) and qr=any(x.roles) and private.qotd_live(x.hotel_id,x.season_start,x.season_end,x.review_by,h,d)
            and l.last_day is not null and l.last_day<=d-90 and private.qotd_is_important(x.id,h)
            and not exists (select 1 from qotd_review r where r.user_id=u and r.question_id=x.id)
          order by l.last_day, random() limit 1;
      end if;
    end if;
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
    'important',private.qotd_is_important(qq.id,h),
    'question_en',qq.question_en,'question_es',qq.question_es,'options_en',qq.options_en,'options_es',qq.options_es,
    'answered',row_.answered_at is not null,'answered_idx',row_.answered_idx,'correct',row_.correct,
    'correct_idx',case when row_.answered_at is not null then qq.correct_idx end,
    'explain_en',case when row_.answered_at is not null then qq.explain_en end,
    'explain_es',case when row_.answered_at is not null then qq.explain_es end,
    'source_url',case when row_.answered_at is not null then qq.source_url end,
    'streak',coalesce(st.qotd_streak,0));
end $function$;

-- pool health: managers aren't an audience
create or replace function public.qotd_pool_health(p_hotel text)
 returns table(role text, freq text, users integer, min_unseen integer, periods_left integer, warn boolean)
 language sql security definer set search_path to 'public','private' as $function$
  with u as (select p.user_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) r from profiles p where p.hotel_id=p_hotel),
  br as (select brand from hotels where id=p_hotel),
  c as (select u.r, u.user_id, (select count(*) from qotd_questions x where x.active and x.es_reviewed and u.r=any(x.roles)
          and x.brand in ('all',(select brand from br)) and (x.hotel_id is null or x.hotel_id=p_hotel)
          and (x.review_by is null or x.review_by>=current_date)
          and not exists (select 1 from qotd_daily y where y.user_id=u.user_id and y.question_id=x.id))::int n from u where u.r<>'gm')
  select r, private.qotd_freq(p_hotel,r), count(*)::int, min(n), min(n),
    min(n) < case when private.qotd_freq(p_hotel,r)='weekly' then 13 else 90 end
  from c where private.is_mgr_of(p_hotel) or private.is_above() group by r order by 6 desc, 4 $function$;

-- 4) "What my team is missing"
create table if not exists public.qotd_covered (
  hotel_id text not null, question_id bigint not null references public.qotd_questions(id) on delete cascade,
  covered_by uuid, covered_at timestamptz not null default now(), primary key (hotel_id, question_id));
alter table public.qotd_covered enable row level security;
drop policy if exists qc_read on public.qotd_covered;
create policy qc_read on public.qotd_covered for select to authenticated using (private.is_above() or private.is_mgr_of(hotel_id));

create or replace function private.qotd_team_data(p_hotel text, p_days int) returns jsonb
language sql stable security definer set search_path=public as $$
  with a as (select d.*, q.topic, q.question_en, q.question_es, q.options_en, q.options_es, q.correct_idx, q.roles
             from qotd_daily d join qotd_questions q on q.id=d.question_id
             where d.hotel_id=p_hotel and d.answered_at is not null and d.day>=current_date-p_days),
  qs as (select question_id, max(question_en) qe, max(question_es) qsp, max(topic) topic, string_agg(distinct role_group, ',') roles,
           count(*) n, count(*) filter (where not correct) miss, private.qotd_is_important(question_id,p_hotel) imp,
           (select c.covered_at from qotd_covered c where c.hotel_id=p_hotel and c.question_id=a.question_id) covered_at,
           (select jsonb_build_object('en',x.options_en->>x.correct_idx,'es',x.options_es->>x.correct_idx) from qotd_questions x where x.id=a.question_id) answer
         from a group by question_id having count(*) filter (where not correct)>0)
  select jsonb_build_object(
    'days',p_days,
    'answered',(select count(*) from a),
    'pct',(select round(100.0*count(*) filter (where correct)/nullif(count(*),0)) from a),
    'questions',coalesce((select jsonb_agg(jsonb_build_object('id',question_id,'qe',qe,'qs',qsp,'topic',topic,'roles',roles,'n',n,'miss',miss,'pct',round(100.0*(n-miss)/n),
        'important',imp,'answer',answer,'covered_at',covered_at) order by (covered_at is null) desc, imp desc, miss desc, n desc) from (select * from qs order by imp desc, miss desc limit 40) z),'[]'),
    'topics',coalesce((select jsonb_agg(jsonb_build_object('topic',topic,'role',role_group,'n',n,'pct',pct) order by pct, n desc) from
        (select topic, role_group, count(*) n, round(100.0*count(*) filter (where correct)/count(*)) pct from a group by 1,2 having count(*)>=2 order by 4, 3 desc limit 15) t),'[]'),
    'roles',coalesce((select jsonb_agg(jsonb_build_object('role',role_group,'n',n,'pct',pct) order by pct) from
        (select role_group, count(*) n, round(100.0*count(*) filter (where correct)/count(*)) pct from a group by 1) t),'[]'),
    'people',coalesce((select jsonb_agg(jsonb_build_object('user_id',user_id,'name',name,'role',role_group,'n',n,'pct',pct,'reviews',rv) order by pct, n desc) from
        (select a.user_id, coalesce(p.name,'?') name, max(a.role_group) role_group, count(*) n, round(100.0*count(*) filter (where correct)/count(*)) pct,
           (select count(*) from qotd_review r where r.user_id=a.user_id) rv
         from a left join profiles p on p.user_id=a.user_id group by a.user_id, p.name) t),'[]'),
    'repeat',coalesce((select jsonb_agg(jsonb_build_object('name',coalesce(p.name,'?'),'qe',q.question_en,'qs',q.question_es,'misses',r.misses,'important',private.qotd_is_important(q.id,p_hotel)) order by r.misses desc)
        from qotd_review r join profiles p on p.user_id=r.user_id and p.hotel_id=p_hotel join qotd_questions q on q.id=r.question_id where r.misses>=2),'[]'),
    'important_missed',coalesce((select jsonb_agg(jsonb_build_object('id',question_id,'qe',qe,'qs',qsp,'miss',miss,'n',n,'covered_at',covered_at)) from qs where imp),'[]')) $$;

create or replace function public.qotd_team_missing(p_hotel text, p_days int default 30) returns jsonb
language plpgsql stable security definer set search_path=public,private as $$
begin
  if not (private.is_above() or private.is_mgr_of(p_hotel)) then raise exception 'not allowed'; end if;
  return private.qotd_team_data(p_hotel, greatest(1,least(p_days,365)));
end $$;

create or replace function public.qotd_mark_covered(p_hotel text, p_id bigint, p_covered boolean default true) returns void
language plpgsql security definer set search_path=public,private as $$
begin
  if not (private.is_above() or private.is_mgr_of(p_hotel)) then raise exception 'not allowed'; end if;
  if p_covered then insert into qotd_covered(hotel_id,question_id,covered_by) values (p_hotel,p_id,auth.uid())
    on conflict (hotel_id,question_id) do update set covered_by=auth.uid(), covered_at=now();
  else delete from qotd_covered where hotel_id=p_hotel and question_id=p_id; end if;
end $$;

-- 5) weekly summary push to GM/AGM (Mondays 8 a.m. Central-ish = 13:00 UTC)
create table if not exists public.qotd_team_summaries (
  id bigserial primary key, hotel_id text not null, week date not null, data jsonb not null, created_at timestamptz not null default now(), unique (hotel_id, week));
alter table public.qotd_team_summaries enable row level security;
drop policy if exists qts_read on public.qotd_team_summaries;
create policy qts_read on public.qotd_team_summaries for select to authenticated using (private.is_above() or private.is_mgr_of(hotel_id));

create or replace function private.qotd_weekly_summary() returns void
language plpgsql security definer set search_path=public as $$
declare h record; d jsonb; sid bigint; wk date := date_trunc('week',(now() at time zone 'America/Chicago'))::date;
begin
  for h in select id from hotels loop
    d := private.qotd_team_data(h.id, 7);
    if coalesce((d->>'answered')::int,0)=0 then continue; end if;
    insert into qotd_team_summaries(hotel_id,week,data) values (h.id,wk,d) on conflict (hotel_id,week) do nothing returning id into sid;
    if sid is not null then perform private.queue_notification('qotd_team_summary', h.id, sid); end if;
  end loop;
end $$;
revoke all on function private.qotd_weekly_summary() from public;
select cron.unschedule('qotd-team-weekly') where exists (select 1 from cron.job where jobname='qotd-team-weekly');
select cron.schedule('qotd-team-weekly','0 13 * * 1','select private.qotd_weekly_summary()');

revoke execute on function public.qotd_set_important(text,bigint,boolean), public.qotd_important_list(text), public.qotd_team_missing(text,int), public.qotd_mark_covered(text,bigint,boolean) from anon;
grant execute on function public.qotd_set_important(text,bigint,boolean), public.qotd_important_list(text), public.qotd_team_missing(text,int), public.qotd_mark_covered(text,bigint,boolean) to authenticated;
