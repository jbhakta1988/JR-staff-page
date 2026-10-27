alter table public.qotd_questions add column if not exists difficulty text not null default 'med' check (difficulty in ('easy','med','hard'));
alter table public.qotd_questions add column if not exists topics text[] not null default '{}';
alter table public.qotd_questions add column if not exists hotel_id text;          -- local/hotel-specific: only that hotel's staff
alter table public.qotd_questions add column if not exists season_start text;      -- 'MM-DD' window, wraps year end
alter table public.qotd_questions add column if not exists season_end text;
alter table public.qotd_questions add column if not exists review_by date;         -- changeable local facts re-verify date
alter table public.qotd_questions add column if not exists norm_key text;          -- QA dedupe key
update public.qotd_questions set topics=array[topic] where topics='{}';
create index if not exists qotd_q_norm on public.qotd_questions(norm_key);
-- GM low-pool warning: unseen eligible questions per role at a hotel vs 90 days
create or replace function public.qotd_pool_health(p_hotel text) returns table(role text, users int, min_unseen int, warn boolean)
language sql security definer set search_path=public,private as $$
  with u as (select p.user_id, coalesce(p.qotd_role, private.qotd_role(p.role::text)) r from profiles p where p.hotel_id=p_hotel),
  br as (select brand from hotels where id=p_hotel),
  c as (select u.r, u.user_id, (select count(*) from qotd_questions x where x.active and x.es_reviewed and u.r=any(x.roles)
          and x.brand in ('all',(select brand from br)) and (x.hotel_id is null or x.hotel_id=p_hotel)
          and (x.review_by is null or x.review_by>=current_date)
          and not exists (select 1 from qotd_daily y where y.user_id=u.user_id and y.question_id=x.id))::int n from u)
  select r, count(*)::int, min(n), min(n)<90 from c
  where private.is_mgr_of(p_hotel) or private.is_above() group by r order by 3 $$;
