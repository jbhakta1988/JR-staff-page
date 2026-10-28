-- Yearly winter preparedness checklist. Additive only: new tables and functions.
-- A fresh season is created for every hotel when that year's assign date arrives
-- (default October 15, due about three weeks later on November 5).
-- 2026 keeps the hotel due dates already set: Hampton (MSPAM) 2026-11-04,
-- SpringHill (MSPMS) 2026-11-05, Golden Valley (MSPWE) optional 2026-11-06.
-- Past years stay in the tables; triggers refuse edits once a later year exists.
-- Demo mode does not call this database. No staff names, prices, or keys are stored here.
-- Read access follows hq_can_see (corporate, or the caller's hotel). GM / AGM use
-- hq_is_gm_agm. Maintenance and front desk use the same staff_profiles / profiles
-- membership row, with both "GM" and "gm" style role labels accepted.

create schema if not exists private;

-- Authenticated staff call the helpers from row-level policies. anon does not.
grant usage on schema private to authenticated;

create table if not exists public.winter_settings (
  id int primary key check (id = 1),
  assign_month int not null default 10 check (assign_month between 1 and 12),
  assign_day int not null default 15 check (assign_day between 1 and 28),
  due_month int not null default 11 check (due_month between 1 and 12),
  due_day int not null default 5 check (due_day between 1 and 28),
  updated_at timestamptz not null default now()
);

create table if not exists public.winter_seasons (
  id bigint generated always as identity primary key,
  hotel_id text not null check (hotel_id in ('MSPWE', 'MSPAM', 'MSPMS')),
  year int not null check (year between 2026 and 2100),
  assign_on date not null,
  due_on date not null,
  optional boolean not null default false,
  snow_phone text check (snow_phone is null or char_length(snow_phone) <= 40),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (hotel_id, year),
  check (due_on >= assign_on)
);

create table if not exists public.winter_items (
  season_id bigint not null references public.winter_seasons (id) on delete cascade,
  item_no int not null check (item_no between 1 and 28),
  status text not null default 'open' check (status in ('open', 'done', 'na')),
  na_reason text,
  note text,
  photo text,
  completed_by uuid,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (season_id, item_no),
  check (
    (status = 'na' and nullif(btrim(na_reason), '') is not null)
    or (status = 'done')
    or (status = 'open' and na_reason is null and completed_at is null and completed_by is null)
  )
);

create table if not exists public.winter_logs (
  id bigint generated always as identity primary key,
  season_id bigint not null references public.winter_seasons (id) on delete cascade,
  kind text not null check (kind in ('cold', 'ooo', 'storm', 'snow')),
  logged_at timestamptz not null default now(),
  logged_by uuid,
  note text,
  photo text,
  temp_f numeric,
  area text,
  room text,
  action text
);

create index if not exists winter_seasons_year_idx on public.winter_seasons (year);
create index if not exists winter_logs_season_idx on public.winter_logs (season_id, logged_at desc);

alter table public.winter_settings enable row level security;
alter table public.winter_seasons enable row level security;
alter table public.winter_items enable row level security;
alter table public.winter_logs enable row level security;

insert into public.winter_settings (id, assign_month, assign_day, due_month, due_day)
values (1, 10, 15, 11, 5)
on conflict (id) do nothing;

-- Membership. staff_profiles is what hq_my_hotel reads. profiles is the other
-- directory used by older migrations. Dynamic SQL keeps this file runnable when
-- only one of those tables exists. search_path is empty; names are qualified.
create or replace function private.winter_membership()
returns table (role text, hotel_id text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  rec record;
  found_row boolean := false;
begin
  if (select auth.uid()) is null then
    return;
  end if;
  begin
    execute $q$
      select p.role::text as role, p.hotel_id::text as hotel_id
      from public.staff_profiles p
      where p.user_id = (select auth.uid())
      limit 1
    $q$ into rec;
    found_row := found;
  exception when others then
    found_row := false;
  end;
  if not found_row then
    begin
      execute $q$
        select p.role::text as role, p.hotel_id::text as hotel_id
        from public.profiles p
        where p.user_id = (select auth.uid())
        limit 1
      $q$ into rec;
      found_row := found;
    exception when others then
      found_row := false;
    end;
  end if;
  if not found_row then
    return;
  end if;
  role := lower(replace(coalesce(rec.role, ''), ' ', '_'));
  hotel_id := rec.hotel_id;
  return next;
end;
$$;

create or replace function private.winter_can_see(p_hotel text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r text;
  h text;
begin
  if (select auth.uid()) is null or p_hotel is null then
    return false;
  end if;
  begin
    if public.hq_can_see(p_hotel) then
      return true;
    end if;
  exception when others then
    null;
  end;
  select m.role, m.hotel_id into r, h from private.winter_membership() m;
  if r = 'above_property' then
    return true;
  end if;
  return h = p_hotel and coalesce(r, '') <> '';
end;
$$;

create or replace function private.winter_is_corporate()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null then
    return false;
  end if;
  begin
    if public.hq_is_corporate() then
      return true;
    end if;
  exception when others then
    null;
  end;
  return exists (
    select 1 from private.winter_membership() m where m.role = 'above_property'
  );
end;
$$;

create or replace function private.winter_can_check(p_hotel text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r text;
  h text;
begin
  if (select auth.uid()) is null or p_hotel is null then
    return false;
  end if;
  begin
    if public.hq_is_gm_agm() and public.hq_my_hotel() = p_hotel then
      return true;
    end if;
  exception when others then
    null;
  end;
  select m.role, m.hotel_id into r, h from private.winter_membership() m;
  return r in ('gm', 'agm', 'maintenance') and h = p_hotel;
end;
$$;

create or replace function private.winter_can_snow(p_hotel text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  r text;
  h text;
begin
  if private.winter_can_check(p_hotel) then
    return true;
  end if;
  select m.role, m.hotel_id into r, h from private.winter_membership() m;
  return r = 'front_desk' and h = p_hotel;
end;
$$;

create or replace function private.winter_is_history(p_season bigint)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.winter_seasons cur
    join public.winter_seasons newer
      on newer.hotel_id = cur.hotel_id
     and newer.year > cur.year
    where cur.id = p_season
  );
$$;

create or replace function private.winter_seed_items()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.winter_items (season_id, item_no)
  select new.id, g.n
  from generate_series(1, 28) as g(n)
  on conflict (season_id, item_no) do nothing;
  return new;
end;
$$;

create or replace function private.winter_touch_item()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.winter_is_history(new.season_id) then
    raise exception 'past year is history';
  end if;
  if new.status is distinct from old.status then
    if new.status in ('done', 'na') then
      new.completed_by := (select auth.uid());
      new.completed_at := now();
    else
      new.completed_by := null;
      new.completed_at := null;
    end if;
  end if;
  if new.status = 'na' and nullif(btrim(coalesce(new.na_reason, '')), '') is null then
    raise exception 'N/A needs a reason';
  end if;
  if new.status <> 'na' then
    new.na_reason := null;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

create or replace function private.winter_touch_log()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.winter_is_history(new.season_id) then
    raise exception 'past year is history';
  end if;
  if new.logged_at is null then
    new.logged_at := now();
  end if;
  new.logged_by := (select auth.uid());
  if new.kind = 'cold' and new.temp_f is null then
    raise exception 'temperature required';
  end if;
  if new.kind = 'snow' and nullif(btrim(coalesce(new.action, '')), '') is null then
    raise exception 'snow log needs an action';
  end if;
  return new;
end;
$$;

create or replace function private.winter_guard_season()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.winter_is_history(old.id) then
    raise exception 'past year is history';
  end if;
  if private.winter_is_corporate() then
    new.updated_at := now();
    return new;
  end if;
  if not private.winter_can_check(old.hotel_id) then
    raise exception 'not allowed';
  end if;
  if new.hotel_id is distinct from old.hotel_id
     or new.year is distinct from old.year
     or new.assign_on is distinct from old.assign_on
     or new.due_on is distinct from old.due_on
     or new.optional is distinct from old.optional then
    raise exception 'only corporate can change dates';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- Creates the active season for every hotel once the assign date has arrived.
-- Does nothing before that date, and does not overwrite a year that already exists.
create or replace function private.winter_ensure_year(p_year integer)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  today date := (current_timestamp at time zone 'America/Chicago')::date;
  cal integer := extract(year from today)::integer;
  active integer;
  assign_month integer;
  assign_day integer;
  due_month integer;
  due_day integer;
  assign_on date;
  due_on date;
  hotel text;
begin
  if (select auth.uid()) is null then
    raise exception 'sign in';
  end if;
  select s.assign_month, s.assign_day, s.due_month, s.due_day
    into assign_month, assign_day, due_month, due_day
  from public.winter_settings s
  where s.id = 1;
  if assign_month is null then
    raise exception 'winter settings missing';
  end if;
  if today >= make_date(cal, assign_month, assign_day) then
    active := cal;
  else
    active := cal - 1;
  end if;
  if active < 2026 or p_year is distinct from active then
    return;
  end if;
  assign_on := make_date(active, assign_month, assign_day);
  foreach hotel in array array['MSPAM', 'MSPMS', 'MSPWE'] loop
    if active = 2026 and hotel = 'MSPAM' then
      due_on := date '2026-11-04';
    elsif active = 2026 and hotel = 'MSPMS' then
      due_on := date '2026-11-05';
    elsif active = 2026 and hotel = 'MSPWE' then
      due_on := date '2026-11-06';
    else
      due_on := make_date(active, due_month, due_day);
    end if;
    insert into public.winter_seasons (hotel_id, year, assign_on, due_on, optional)
    values (hotel, active, assign_on, due_on, active = 2026 and hotel = 'MSPWE')
    on conflict (hotel_id, year) do nothing;
  end loop;
end;
$$;

create or replace function public.winter_ensure_year(p_year integer)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.winter_ensure_year(p_year);
$$;

drop trigger if exists winter_seed_items on public.winter_seasons;
create trigger winter_seed_items
  after insert on public.winter_seasons
  for each row execute function private.winter_seed_items();

drop trigger if exists winter_touch_item on public.winter_items;
create trigger winter_touch_item
  before update on public.winter_items
  for each row execute function private.winter_touch_item();

drop trigger if exists winter_touch_log on public.winter_logs;
create trigger winter_touch_log
  before insert on public.winter_logs
  for each row execute function private.winter_touch_log();

drop trigger if exists winter_guard_season on public.winter_seasons;
create trigger winter_guard_season
  before update on public.winter_seasons
  for each row execute function private.winter_guard_season();

drop policy if exists winter_settings_read on public.winter_settings;
create policy winter_settings_read on public.winter_settings
  for select to authenticated
  using ((select auth.uid()) is not null);

drop policy if exists winter_settings_update on public.winter_settings;
create policy winter_settings_update on public.winter_settings
  for update to authenticated
  using ((select private.winter_is_corporate()))
  with check ((select private.winter_is_corporate()));

drop policy if exists winter_seasons_read on public.winter_seasons;
create policy winter_seasons_read on public.winter_seasons
  for select to authenticated
  using ((select private.winter_can_see(hotel_id)));

drop policy if exists winter_seasons_update on public.winter_seasons;
create policy winter_seasons_update on public.winter_seasons
  for update to authenticated
  using (
    (select private.winter_is_corporate())
    or (select private.winter_can_check(hotel_id))
  )
  with check (
    (select private.winter_is_corporate())
    or (select private.winter_can_check(hotel_id))
  );

drop policy if exists winter_items_read on public.winter_items;
create policy winter_items_read on public.winter_items
  for select to authenticated
  using (
    exists (
      select 1 from public.winter_seasons s
      where s.id = season_id
        and (select private.winter_can_see(s.hotel_id))
    )
  );

drop policy if exists winter_items_update on public.winter_items;
create policy winter_items_update on public.winter_items
  for update to authenticated
  using (
    exists (
      select 1 from public.winter_seasons s
      where s.id = season_id
        and (select private.winter_can_check(s.hotel_id))
    )
  )
  with check (
    exists (
      select 1 from public.winter_seasons s
      where s.id = season_id
        and (select private.winter_can_check(s.hotel_id))
    )
  );

drop policy if exists winter_logs_read on public.winter_logs;
create policy winter_logs_read on public.winter_logs
  for select to authenticated
  using (
    exists (
      select 1 from public.winter_seasons s
      where s.id = season_id
        and (select private.winter_can_see(s.hotel_id))
    )
  );

drop policy if exists winter_logs_insert on public.winter_logs;
create policy winter_logs_insert on public.winter_logs
  for insert to authenticated
  with check (
    exists (
      select 1 from public.winter_seasons s
      where s.id = season_id
        and (
          (kind = 'snow' and (select private.winter_can_snow(s.hotel_id)))
          or (kind <> 'snow' and (select private.winter_can_check(s.hotel_id)))
        )
    )
  );

revoke all on function private.winter_membership() from public, anon;
revoke all on function private.winter_can_see(text) from public, anon;
revoke all on function private.winter_is_corporate() from public, anon;
revoke all on function private.winter_can_check(text) from public, anon;
revoke all on function private.winter_can_snow(text) from public, anon;
revoke all on function private.winter_is_history(bigint) from public, anon;
revoke all on function private.winter_seed_items() from public, anon;
revoke all on function private.winter_touch_item() from public, anon;
revoke all on function private.winter_touch_log() from public, anon;
revoke all on function private.winter_guard_season() from public, anon;
revoke all on function private.winter_ensure_year(integer) from public, anon;
revoke all on function public.winter_ensure_year(integer) from public, anon;

grant execute on function private.winter_membership() to authenticated;
grant execute on function private.winter_can_see(text) to authenticated;
grant execute on function private.winter_is_corporate() to authenticated;
grant execute on function private.winter_can_check(text) to authenticated;
grant execute on function private.winter_can_snow(text) to authenticated;
grant execute on function private.winter_is_history(bigint) to authenticated;
grant execute on function private.winter_seed_items() to authenticated;
grant execute on function private.winter_touch_item() to authenticated;
grant execute on function private.winter_touch_log() to authenticated;
grant execute on function private.winter_guard_season() to authenticated;
grant execute on function private.winter_ensure_year(integer) to authenticated;
grant execute on function public.winter_ensure_year(integer) to authenticated;

revoke all on table public.winter_settings from public, anon, authenticated;
revoke all on table public.winter_seasons from public, anon, authenticated;
revoke all on table public.winter_items from public, anon, authenticated;
revoke all on table public.winter_logs from public, anon, authenticated;

grant select, update on table public.winter_settings to authenticated;
grant select, update on table public.winter_seasons to authenticated;
grant select, update on table public.winter_items to authenticated;
grant select, insert on table public.winter_logs to authenticated;

revoke all on sequence public.winter_seasons_id_seq from public, anon;
revoke all on sequence public.winter_logs_id_seq from public, anon;
grant usage, select on sequence public.winter_seasons_id_seq to authenticated;
grant usage, select on sequence public.winter_logs_id_seq to authenticated;
