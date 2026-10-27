-- DESIGN ONLY (not applied). "On the clock" compliance.
-- Punched-in snapshots from the HE Single-Day Report, ingested every ~30 min by a server job using the service role.
-- No real names in this file. Assumes helper functions app_role() and app_hotel() (see 20261027_labor_standards.sql).

create table if not exists public.punch_snapshots (
  id           bigserial primary key,
  hotel        text        not null,            -- MSPWE / MSPAM / MSPMS
  taken_at     timestamptz not null,            -- when the snapshot was pulled
  work_date    date        not null,
  source       text        not null default 'he_single_day',
  rows         jsonb       not null,            -- [{name, employee_id, he_position, punch_in, punch_out|null}]
  created_at   timestamptz not null default now()
);
create index if not exists punch_snapshots_hotel_date on public.punch_snapshots (hotel, work_date, taken_at desc);

-- HE name / employee id -> HotelHQ user, editable by GM/AGM (and corporate)
create table if not exists public.punch_user_map (
  hotel       text not null,
  he_key      text not null,                    -- 'id:<employee id>' or 'n:<normalized name>'
  user_id     uuid,                             -- null = not a HotelHQ user (ignore)
  updated_by  uuid default auth.uid(),
  updated_at  timestamptz not null default now(),
  primary key (hotel, he_key)
);

-- First HotelHQ login per user per day, and per-hotel rule settings
create table if not exists public.daily_logins (
  user_id uuid not null, hotel text not null, work_date date not null, first_login timestamptz not null,
  primary key (user_id, work_date)
);
create table if not exists public.on_clock_settings (
  hotel text primary key, window_min int not null default 30 check (window_min between 5 and 240),
  bonus_enabled boolean not null default true, bonus_points int not null default 5,
  updated_by uuid default auth.uid(), updated_at timestamptz not null default now()
);

alter table public.punch_snapshots  enable row level security;
alter table public.punch_user_map   enable row level security;
alter table public.daily_logins     enable row level security;
alter table public.on_clock_settings enable row level security;

-- punch_snapshots: read = corporate (all) or GM/AGM (own hotel). No insert/update/delete policies:
-- writes happen only via the service role (which bypasses RLS) from the import job.
create policy punch_snapshots_read on public.punch_snapshots for select
  using (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()));

create policy punch_user_map_read on public.punch_user_map for select
  using (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()));
create policy punch_user_map_write on public.punch_user_map for all
  using (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()))
  with check (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()));

create policy daily_logins_read on public.daily_logins for select
  using (user_id = auth.uid() or app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()));
create policy daily_logins_insert_self on public.daily_logins for insert
  with check (user_id = auth.uid() and hotel = app_hotel());

create policy on_clock_settings_read on public.on_clock_settings for select
  using (app_role() = 'above_property' or hotel = app_hotel());
create policy on_clock_settings_write on public.on_clock_settings for all
  using (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()))
  with check (app_role() = 'above_property' or (app_role() in ('gm','agm') and hotel = app_hotel()));
