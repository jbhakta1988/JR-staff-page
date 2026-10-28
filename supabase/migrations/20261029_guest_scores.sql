-- Guest scores (ITR and the rest of the brand survey). Additive only.
-- Does not change the older guest_survey_scores aggregate table.
-- No guest names, emails, phone numbers, or survey vendor keys are stored.
-- Demo mode does not call this database.
--
-- Who can see what is guest_score_access (role -> metric). Keep it identical to
-- GS_ACCESS in guest-scores.js. Leaders are not listed: GM, AGM, and corporate
-- read every metric, comments, and rooms. A metric ending in * is a prefix,
-- so a new IHG or Hilton breakfast question is picked up without a code change.
-- Housekeeping roles (hk_lead is the executive housekeeper and the HK lead),
-- housekeepers, laundry, and housepersons read only ITR and cleanliness.
-- Breakfast reads ITR and the breakfast metrics. Front desk and maintenance
-- are in the same map so those departments can be turned on without a new policy.

create schema if not exists private;

grant usage on schema private to authenticated;

create table if not exists public.guest_surveys (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  survey_date date not null,
  room text,
  source text not null check (char_length(btrim(source)) between 1 and 40),
  itr smallint check (itr is null or itr between 0 and 10),
  comment text check (comment is null or char_length(comment) <= 400),
  created_at timestamptz not null default pg_catalog.now()
);

comment on table public.guest_surveys is
  'One survey or public review. Do not store guest names, emails, or phone numbers.';
comment on column public.guest_surveys.room is
  'Room number or area only. Never a guest name.';
comment on column public.guest_surveys.comment is
  'Optional note about the room or the issue. Never a guest name.';
comment on column public.guest_surveys.itr is
  'Intent to Recommend, 0-10. Null for Google and TripAdvisor rows, which use guest_survey_metrics.';

create table if not exists public.guest_survey_metrics (
  survey_id bigint not null references public.guest_surveys (id) on delete cascade,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  survey_date date not null,
  metric text not null check (metric ~ '^[a-z][a-z0-9_]{0,40}$'),
  score numeric not null check (score >= 0 and score <= 10),
  primary key (survey_id, metric)
);

comment on table public.guest_survey_metrics is
  'Flexible scores so IHG, Hilton, and Marriott can send different questions. Hotel and date are copied from the survey.';

create index if not exists guest_surveys_hotel_date_idx
  on public.guest_surveys (hotel, survey_date desc);
create index if not exists guest_surveys_low_itr_idx
  on public.guest_surveys (hotel, survey_date desc)
  where itr <= 6;
create index if not exists guest_survey_metrics_lookup_idx
  on public.guest_survey_metrics (hotel, metric, survey_date desc);

create table if not exists public.itr_goals (
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  month date not null,
  metric text not null default 'itr' check (metric ~ '^[a-z][a-z0-9_]{0,40}$'),
  goal_pct numeric not null check (goal_pct >= 0 and goal_pct <= 100),
  updated_by uuid default auth.uid(),
  updated_at timestamptz not null default pg_catalog.now(),
  primary key (hotel, month, metric),
  check (month = pg_catalog.date_trunc('month', month)::date)
);

comment on table public.itr_goals is
  'Monthly goal for one metric at one hotel. Corporate writes. GM and AGM read. Department roles read only the metrics in guest_score_access.';
comment on column public.itr_goals.goal_pct is
  'Top-box percent (0-100), or a 1-5 star target for google_stars and tripadvisor_stars.';

create table if not exists public.guest_score_access (
  role text not null check (role ~ '^[a-z_]+$'),
  metric text not null check (metric ~ '^[a-z][a-z0-9_]*\*?$'),
  primary key (role, metric)
);

comment on table public.guest_score_access is
  'The role to metric list. Leaders are omitted and can read every metric. A trailing * matches a prefix. Same rows as GS_ACCESS in guest-scores.js.';

alter table public.guest_surveys enable row level security;
alter table public.guest_survey_metrics enable row level security;
alter table public.itr_goals enable row level security;
alter table public.guest_score_access enable row level security;

-- True for GM, AGM, and corporate (any metric), and for a department role
-- when guest_score_access lists that metric or a matching prefix.
create or replace function private.guest_score_metric_allowed(p_metric text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.is_above()
    or private.my_role() in ('gm', 'agm')
    or exists (
      select 1
      from public.guest_score_access a
      where a.role = private.my_role()::text
        and (
          a.metric = p_metric
          or (
            pg_catalog.right(a.metric, 1) = '*'
            and pg_catalog.char_length(a.metric) > 1
            and pg_catalog.starts_with(
              p_metric,
              pg_catalog.left(a.metric, pg_catalog.char_length(a.metric) - 1)
            )
          )
        )
    ),
    false
  );
$$;

create or replace function private.set_itr_goal(
  p_hotel text,
  p_month date,
  p_metric text,
  p_goal numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  m date;
begin
  if not private.is_above() then
    raise exception 'not allowed';
  end if;
  if p_hotel not in ('MSPWE', 'MSPAM', 'MSPMS') then
    raise exception 'unknown hotel';
  end if;
  if p_metric is null or p_metric !~ '^[a-z][a-z0-9_]{0,40}$' then
    raise exception 'unknown metric';
  end if;
  if p_goal is null then
    raise exception 'goal required';
  end if;
  if p_metric like '%\_stars' escape '\' then
    if p_goal < 1 or p_goal > 5 then
      raise exception 'star goal out of range';
    end if;
  elsif p_goal < 0 or p_goal > 100 then
    raise exception 'goal out of range';
  end if;
  m := pg_catalog.date_trunc('month', p_month)::date;
  insert into public.itr_goals (hotel, month, metric, goal_pct, updated_by, updated_at)
  values (p_hotel, m, p_metric, p_goal, (select auth.uid()), pg_catalog.now())
  on conflict (hotel, month, metric) do update
    set goal_pct = excluded.goal_pct,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;

create or replace function public.set_itr_goal(
  p_hotel text,
  p_month date,
  p_metric text,
  p_goal numeric
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_itr_goal(p_hotel, p_month, p_metric, p_goal);
$$;

-- Copy ITR onto the flexible metric table. Other questions are inserted as
-- their own metric rows. Hotel and date always follow the parent survey.
create or replace function private.guest_survey_align_metric()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  h text;
  d date;
begin
  select s.hotel, s.survey_date into h, d
  from public.guest_surveys s
  where s.id = new.survey_id;
  if h is null then
    raise exception 'unknown survey';
  end if;
  new.hotel := h;
  new.survey_date := d;
  return new;
end;
$$;

create or replace function private.guest_survey_sync_itr()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.itr is null then
    delete from public.guest_survey_metrics m
    where m.survey_id = new.id and m.metric = 'itr';
  else
    insert into public.guest_survey_metrics (survey_id, hotel, survey_date, metric, score)
    values (new.id, new.hotel, new.survey_date, 'itr', new.itr)
    on conflict (survey_id, metric) do update
      set hotel = excluded.hotel,
          survey_date = excluded.survey_date,
          score = excluded.score;
  end if;
  return new;
end;
$$;

drop trigger if exists guest_survey_align_metric on public.guest_survey_metrics;
create trigger guest_survey_align_metric
  before insert or update on public.guest_survey_metrics
  for each row execute function private.guest_survey_align_metric();

drop trigger if exists guest_survey_sync_itr on public.guest_surveys;
create trigger guest_survey_sync_itr
  after insert or update of itr, hotel, survey_date on public.guest_surveys
  for each row execute function private.guest_survey_sync_itr();

drop policy if exists guest_surveys_select on public.guest_surveys;
create policy guest_surveys_select on public.guest_surveys
  for select to authenticated
  using ((select private.is_mgr_of(hotel)));

drop policy if exists guest_survey_metrics_select on public.guest_survey_metrics;
create policy guest_survey_metrics_select on public.guest_survey_metrics
  for select to authenticated
  using (
    (select private.is_mgr_of(hotel))
    or (
      hotel = any (select private.my_hotels())
      and (select private.guest_score_metric_allowed(metric))
    )
  );

drop policy if exists itr_goals_select on public.itr_goals;
create policy itr_goals_select on public.itr_goals
  for select to authenticated
  using (
    (select private.is_mgr_of(hotel))
    or (
      hotel = any (select private.my_hotels())
      and (select private.guest_score_metric_allowed(metric))
    )
  );

drop policy if exists itr_goals_insert on public.itr_goals;
create policy itr_goals_insert on public.itr_goals
  for insert to authenticated
  with check ((select private.is_above()));

drop policy if exists itr_goals_update on public.itr_goals;
create policy itr_goals_update on public.itr_goals
  for update to authenticated
  using ((select private.is_above()))
  with check ((select private.is_above()));

drop policy if exists guest_score_access_select on public.guest_score_access;
create policy guest_score_access_select on public.guest_score_access
  for select to authenticated
  using ((select auth.uid()) is not null);

-- Department reads go through this view: hotel, date, metric, and score only.
create or replace view public.guest_score_facts
with (security_invoker = true) as
select m.survey_id, m.hotel, m.survey_date, m.metric, m.score
from public.guest_survey_metrics m;

comment on view public.guest_score_facts is
  'Scores the signed-in role may see. No room, no comment, and no guest name.';

revoke all on function private.guest_score_metric_allowed(text) from public, anon;
revoke all on function private.set_itr_goal(text, date, text, numeric) from public, anon;
revoke all on function private.guest_survey_align_metric() from public, anon;
revoke all on function private.guest_survey_sync_itr() from public, anon;
revoke all on function public.set_itr_goal(text, date, text, numeric) from public, anon;

grant execute on function private.guest_score_metric_allowed(text) to authenticated;
grant execute on function private.set_itr_goal(text, date, text, numeric) to authenticated;
grant execute on function private.guest_survey_align_metric() to authenticated;
grant execute on function private.guest_survey_sync_itr() to authenticated;
grant execute on function public.set_itr_goal(text, date, text, numeric) to authenticated;

revoke all on table public.guest_surveys from public, anon, authenticated;
revoke all on table public.guest_survey_metrics from public, anon, authenticated;
revoke all on table public.itr_goals from public, anon, authenticated;
revoke all on table public.guest_score_access from public, anon, authenticated;
revoke all on table public.guest_score_facts from public, anon, authenticated;

grant select on table public.guest_surveys to authenticated;
grant select on table public.guest_survey_metrics to authenticated;
grant select, insert, update on table public.itr_goals to authenticated;
grant select on table public.guest_score_access to authenticated;
grant select on table public.guest_score_facts to authenticated;

revoke all on sequence public.guest_surveys_id_seq from public, anon, authenticated;

-- GS_ACCESS_SEED_START
insert into public.guest_score_access (role, metric) values
  ('hk_lead', 'itr'),
  ('hk_lead', 'cleanliness'),
  ('housekeeper', 'itr'),
  ('housekeeper', 'cleanliness'),
  ('laundry', 'itr'),
  ('laundry', 'cleanliness'),
  ('house_person', 'itr'),
  ('house_person', 'cleanliness'),
  ('breakfast', 'itr'),
  ('breakfast', 'fb_overall'),
  ('breakfast', 'breakfast_service'),
  ('breakfast', 'food_quality'),
  ('breakfast', 'breakfast_*'),
  ('front_desk', 'itr'),
  ('front_desk', 'staff_service'),
  ('front_desk', 'check_in'),
  ('front_desk', 'check_in_*'),
  ('maintenance', 'itr'),
  ('maintenance', 'maintenance'),
  ('maintenance', 'maintenance_*')
on conflict (role, metric) do nothing;
-- GS_ACCESS_SEED_END
