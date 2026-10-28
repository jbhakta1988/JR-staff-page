-- Parking stalls, visits, and Park & Fly. Additive only.
-- Does not drop or delete existing data.
-- Demo mode does not call this database and does not load sample plates.
-- Do not store guest names. A plate is a vehicle id, not a person.
--
-- Who can log: front desk, shuttle drivers, GM, AGM, and corporate.
-- Who can lay out stalls, lots, proximity, and Park & Fly: GM, AGM, and corporate.
-- Read access is the same as log access, limited to the caller's hotels.
-- private.my_hotels() returns text[]. Compare with
--   hotel = any ((select private.my_hotels())::text[])
-- so the list is read once and the check is text = any(text[]).
-- Corporate (private.is_above()) can see every hotel.
--
-- Overstay is not stored. The app flags a guest vehicle that is still parked
-- past expected checkout, or past the hotel's hour limit when it has no room.
-- A Park & Fly vehicle is not flagged at hotel checkout. It is flagged only
-- after expected pickup plus the hotel's grace hours.
-- Duration is checked_out_at - checked_in_at, or now() - checked_in_at
-- while the vehicle is still on the lot (see parking_visit_times).
-- Keep stall suggestion in private.parking_suggest_stall aligned with
-- suggestStall in parking.js.

create schema if not exists private;

grant usage on schema private to authenticated;

create table if not exists public.parking_settings (
  hotel text primary key check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  max_hours_without_room integer not null default 72 check (max_hours_without_room between 1 and 720),
  long_term_nights integer not null default 7 check (long_term_nights between 1 and 365),
  park_fly_enabled boolean not null,
  park_fly_grace_hours integer not null default 2 check (park_fly_grace_hours between 0 and 72),
  updated_by uuid,
  updated_at timestamptz not null default pg_catalog.now()
);

comment on table public.parking_settings is
  'Per-hotel parking rules. Park & Fly defaults on for the airport hotels and off for Golden Valley.';

create table if not exists public.parking_zones (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  purpose text not null check (purpose in ('standard', 'long_term', 'park_fly')),
  active boolean not null default true,
  sort_order integer not null default 0,
  unique (hotel, name)
);

comment on table public.parking_zones is
  'A lot or zone. standard is nearest-to-room. long_term and park_fly are designated areas.';

create table if not exists public.parking_stalls (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  zone_id bigint not null references public.parking_zones (id),
  stall_no text not null check (stall_no ~ '^[A-Z0-9-]{1,12}$'),
  notes text check (notes is null or char_length(notes) <= 80),
  active boolean not null default true,
  sort_order integer not null default 0,
  unique (hotel, stall_no)
);

comment on table public.parking_stalls is
  'Numbered stall. notes is a short tag such as ADA, EV, or oversized. No guest name.';

create table if not exists public.parking_stall_ranges (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  stall_id bigint not null references public.parking_stalls (id),
  room_lo integer check (room_lo is null or room_lo between 1 and 9999),
  room_hi integer check (room_hi is null or room_hi between 1 and 9999),
  floor text check (floor is null or floor ~ '^[0-9]{1,2}$'),
  wing text check (wing is null or char_length(btrim(wing)) between 1 and 20),
  rank integer not null check (rank between 1 and 99),
  active boolean not null default true,
  check (room_hi is null or room_lo is null or room_hi >= room_lo),
  check (room_lo is not null or floor is not null or wing is not null)
);

comment on table public.parking_stall_ranges is
  'Proximity of one stall to a room range, floor, or wing. Rank 1 is the closest.';

create table if not exists public.parking_visits (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPWE', 'MSPAM', 'MSPMS')),
  plate text not null check (plate ~ '^[A-Z0-9]{2,8}$'),
  plate_state text not null check (plate_state ~ '^[A-Z]{2}$'),
  make text check (make is null or char_length(make) <= 30),
  model text check (model is null or char_length(model) <= 30),
  color text check (color is null or char_length(color) <= 30),
  stall_id bigint references public.parking_stalls (id),
  room text check (room is null or room ~ '^[0-9]{2,4}$'),
  checked_in_at timestamptz not null default pg_catalog.now(),
  expected_out_at timestamptz,
  checked_out_at timestamptz,
  permit text check (permit is null or char_length(permit) <= 20),
  paid boolean not null default false,
  rate_note text check (rate_note is null or char_length(rate_note) <= 120),
  long_term boolean not null default false,
  unknown boolean not null default false,
  vehicle_type text not null default 'guest' check (vehicle_type in ('guest', 'park_fly')),
  pf_confirm text check (pf_confirm is null or pf_confirm ~ '^[A-Z0-9-]{2,24}$'),
  pf_days integer check (pf_days is null or pf_days between 1 and 60),
  pf_dropoff date,
  pf_pickup_at timestamptz,
  pf_flight text check (pf_flight is null or char_length(pf_flight) <= 40),
  pf_extra_note text check (pf_extra_note is null or char_length(pf_extra_note) <= 120),
  note text check (note is null or char_length(note) <= 200),
  created_by uuid default auth.uid(),
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),
  check (checked_out_at is null or checked_out_at >= checked_in_at),
  check (
    vehicle_type <> 'park_fly'
    or (
      pf_confirm is not null
      and pf_days is not null
      and pf_dropoff is not null
      and pf_pickup_at is not null
    )
  )
);

comment on table public.parking_visits is
  'One vehicle on the lot. Do not store a guest name. unknown marks a car found on a lot walk.';

create index if not exists parking_zones_hotel_idx on public.parking_zones (hotel);
create index if not exists parking_stalls_hotel_idx on public.parking_stalls (hotel, zone_id);
create index if not exists parking_stall_ranges_stall_idx on public.parking_stall_ranges (stall_id) where active;
create index if not exists parking_visits_hotel_in_idx on public.parking_visits (hotel, checked_in_at desc);
create index if not exists parking_visits_plate_idx on public.parking_visits (hotel, plate);
create unique index if not exists parking_visits_open_stall_idx
  on public.parking_visits (stall_id)
  where checked_out_at is null and stall_id is not null;
create unique index if not exists parking_visits_open_plate_idx
  on public.parking_visits (hotel, plate)
  where checked_out_at is null;

alter table public.parking_settings enable row level security;
alter table public.parking_zones enable row level security;
alter table public.parking_stalls enable row level security;
alter table public.parking_stall_ranges enable row level security;
alter table public.parking_visits enable row level security;

insert into public.parking_settings (hotel, max_hours_without_room, long_term_nights, park_fly_enabled, park_fly_grace_hours)
values
  ('MSPWE', 72, 7, false, 2),
  ('MSPAM', 72, 7, true, 2),
  ('MSPMS', 72, 7, true, 2)
on conflict (hotel) do nothing;

create or replace function private.parking_can_log()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.my_role() in ('front_desk', 'shuttle_driver', 'gm', 'agm', 'above_property'),
    false
  );
$$;

create or replace function private.parking_can_configure()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.is_above() or private.my_role() in ('gm', 'agm'), false);
$$;

create or replace function private.parking_hotel_ok(p_hotel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_hotel in ('MSPWE', 'MSPAM', 'MSPMS')
    and (
      private.is_above()
      or p_hotel = any ((select private.my_hotels())::text[])
    ),
    false
  );
$$;

create or replace function private.parking_suggest_stall(
  p_hotel text,
  p_room text,
  p_checked_in timestamptz,
  p_expected_out timestamptz,
  p_long_term boolean,
  p_vehicle_type text
)
returns bigint
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_hours integer;
  v_nights_limit integer;
  v_enabled boolean;
  v_room integer;
  v_floor text;
  v_nights integer := 0;
  v_long boolean;
  v_purpose text;
  v_id bigint;
begin
  if not private.parking_hotel_ok(p_hotel) then
    return null;
  end if;
  if not private.parking_can_log() then
    return null;
  end if;
  select s.max_hours_without_room, s.long_term_nights, s.park_fly_enabled
    into v_hours, v_nights_limit, v_enabled
  from public.parking_settings s
  where s.hotel = p_hotel;
  if v_nights_limit is null then
    return null;
  end if;
  if p_vehicle_type = 'park_fly' then
    if not v_enabled then
      return null;
    end if;
    v_purpose := 'park_fly';
  else
    if p_checked_in is not null and p_expected_out is not null then
      v_nights := (pg_catalog.timezone('America/Chicago', p_expected_out))::date
        - (pg_catalog.timezone('America/Chicago', p_checked_in))::date;
    end if;
    v_long := coalesce(p_long_term, false) or v_nights > v_nights_limit;
    v_purpose := case when v_long then 'long_term' else 'standard' end;
  end if;

  if v_purpose = 'standard' then
    if p_room is null or p_room !~ '^[0-9]{2,4}$' then
      return null;
    end if;
    v_room := p_room::integer;
    if v_room >= 100 then
      v_floor := (v_room / 100)::text;
    else
      v_floor := '';
    end if;
    select st.id into v_id
    from public.parking_stalls st
    join public.parking_zones z on z.id = st.zone_id
    join public.parking_stall_ranges r on r.stall_id = st.id and r.active
    where st.hotel = p_hotel
      and st.active
      and z.active
      and z.purpose = 'standard'
      and (r.floor is null or r.floor = v_floor)
      and (
        (r.room_lo is not null and r.room_hi is not null and v_room between r.room_lo and r.room_hi)
        or (r.room_lo is null and r.floor is not null)
      )
      and not exists (
        select 1 from public.parking_visits v
        where v.stall_id = st.id and v.checked_out_at is null
      )
    order by r.rank, st.sort_order, st.stall_no
    limit 1;
    return v_id;
  end if;

  select st.id into v_id
  from public.parking_stalls st
  join public.parking_zones z on z.id = st.zone_id
  where st.hotel = p_hotel
    and st.active
    and z.active
    and z.purpose = v_purpose
    and not exists (
      select 1 from public.parking_visits v
      where v.stall_id = st.id and v.checked_out_at is null
    )
  order by z.sort_order, st.sort_order, st.stall_no
  limit 1;
  return v_id;
end;
$$;

create or replace function private.parking_log_visit(
  p_hotel text,
  p_plate text,
  p_state text,
  p_make text,
  p_model text,
  p_color text,
  p_stall_id bigint,
  p_room text,
  p_checked_in timestamptz,
  p_expected_out timestamptz,
  p_permit text,
  p_paid boolean,
  p_rate_note text,
  p_long_term boolean,
  p_unknown boolean,
  p_vehicle_type text,
  p_pf_confirm text,
  p_pf_days integer,
  p_pf_dropoff date,
  p_pf_pickup timestamptz,
  p_pf_flight text,
  p_pf_extra_note text,
  p_note text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_plate text;
  v_state text;
  v_type text;
  v_enabled boolean;
  v_nights_limit integer;
  v_nights integer := 0;
  v_long boolean;
  v_stall bigint;
  v_id bigint;
  v_in timestamptz;
begin
  if (select auth.uid()) is null or not private.parking_can_log() then
    raise exception 'not allowed';
  end if;
  if not private.parking_hotel_ok(p_hotel) then
    raise exception 'unknown hotel';
  end if;
  v_plate := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_plate, ''), '[^A-Za-z0-9]', '', 'g'));
  if v_plate !~ '^[A-Z0-9]{2,8}$' then
    raise exception 'plate required';
  end if;
  v_state := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_state, ''), '[^A-Za-z]', '', 'g'));
  if v_state !~ '^[A-Z]{2}$' then
    raise exception 'state required';
  end if;
  v_type := case when p_vehicle_type = 'park_fly' then 'park_fly' else 'guest' end;
  if coalesce(p_unknown, false) and v_type = 'park_fly' then
    raise exception 'not allowed';
  end if;
  select s.park_fly_enabled, s.long_term_nights into v_enabled, v_nights_limit
  from public.parking_settings s where s.hotel = p_hotel;
  if v_type = 'park_fly' and not coalesce(v_enabled, false) then
    raise exception 'park and fly is off';
  end if;
  v_in := coalesce(p_checked_in, pg_catalog.now());
  if p_expected_out is not null then
    v_nights := (pg_catalog.timezone('America/Chicago', p_expected_out))::date
      - (pg_catalog.timezone('America/Chicago', v_in))::date;
  end if;
  v_long := v_type <> 'park_fly' and (coalesce(p_long_term, false) or v_nights > coalesce(v_nights_limit, 7));
  v_stall := p_stall_id;
  if v_stall is null and not coalesce(p_unknown, false) then
    v_stall := private.parking_suggest_stall(p_hotel, p_room, v_in, p_expected_out, v_long, v_type);
  end if;
  if coalesce(p_unknown, false) and v_stall is null then
    raise exception 'stall required';
  end if;
  if v_type = 'park_fly' then
    if p_pf_confirm is null or p_pf_days is null or p_pf_dropoff is null or p_pf_pickup is null then
      raise exception 'park and fly fields required';
    end if;
  end if;
  if exists (
    select 1 from public.parking_visits v
    where v.hotel = p_hotel and v.plate = v_plate and v.checked_out_at is null
  ) then
    raise exception 'already parked';
  end if;
  if v_stall is not null and exists (
    select 1 from public.parking_visits v
    where v.stall_id = v_stall and v.checked_out_at is null
  ) then
    raise exception 'stall occupied';
  end if;

  insert into public.parking_visits (
    hotel, plate, plate_state, make, model, color, stall_id, room,
    checked_in_at, expected_out_at, permit, paid, rate_note, long_term, unknown,
    vehicle_type, pf_confirm, pf_days, pf_dropoff, pf_pickup_at, pf_flight, pf_extra_note, note,
    created_by
  ) values (
    p_hotel, v_plate, v_state,
    nullif(btrim(p_make), ''), nullif(btrim(p_model), ''), nullif(btrim(p_color), ''),
    v_stall, nullif(btrim(p_room), ''),
    v_in, p_expected_out, nullif(btrim(p_permit), ''), coalesce(p_paid, false), nullif(btrim(p_rate_note), ''),
    v_long, coalesce(p_unknown, false) and v_type = 'guest',
    v_type,
    case when v_type = 'park_fly' then pg_catalog.upper(pg_catalog.regexp_replace(p_pf_confirm, '[^A-Za-z0-9-]', '', 'g')) else null end,
    case when v_type = 'park_fly' then p_pf_days else null end,
    case when v_type = 'park_fly' then p_pf_dropoff else null end,
    case when v_type = 'park_fly' then p_pf_pickup else null end,
    case when v_type = 'park_fly' then nullif(btrim(p_pf_flight), '') else null end,
    case when v_type = 'park_fly' then nullif(btrim(p_pf_extra_note), '') else null end,
    nullif(btrim(p_note), ''),
    (select auth.uid())
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function private.parking_mark_out(p_id bigint, p_out timestamptz)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hotel text;
  v_in timestamptz;
  v_out timestamptz;
begin
  if (select auth.uid()) is null or not private.parking_can_log() then
    raise exception 'not allowed';
  end if;
  select v.hotel, v.checked_in_at, v.checked_out_at into v_hotel, v_in, v_out
  from public.parking_visits v where v.id = p_id;
  if v_hotel is null then
    raise exception 'unknown visit';
  end if;
  if not private.parking_hotel_ok(v_hotel) then
    raise exception 'not allowed';
  end if;
  if v_out is not null then
    raise exception 'already out';
  end if;
  if p_out is null or p_out < v_in then
    raise exception 'time out before time in';
  end if;
  update public.parking_visits
    set checked_out_at = p_out, updated_at = pg_catalog.now()
  where id = p_id;
end;
$$;

create or replace function private.parking_save_settings(
  p_hotel text,
  p_max_hours integer,
  p_long_term_nights integer,
  p_park_fly boolean,
  p_grace_hours integer
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not private.parking_can_configure() then
    raise exception 'not allowed';
  end if;
  if not private.parking_hotel_ok(p_hotel) then
    raise exception 'unknown hotel';
  end if;
  if p_max_hours is null or p_max_hours < 1 or p_max_hours > 720 then
    raise exception 'hours out of range';
  end if;
  if p_long_term_nights is null or p_long_term_nights < 1 or p_long_term_nights > 365 then
    raise exception 'nights out of range';
  end if;
  if p_grace_hours is null or p_grace_hours < 0 or p_grace_hours > 72 then
    raise exception 'grace out of range';
  end if;
  insert into public.parking_settings (hotel, max_hours_without_room, long_term_nights, park_fly_enabled, park_fly_grace_hours, updated_by, updated_at)
  values (p_hotel, p_max_hours, p_long_term_nights, coalesce(p_park_fly, false), p_grace_hours, (select auth.uid()), pg_catalog.now())
  on conflict (hotel) do update
    set max_hours_without_room = excluded.max_hours_without_room,
        long_term_nights = excluded.long_term_nights,
        park_fly_enabled = excluded.park_fly_enabled,
        park_fly_grace_hours = excluded.park_fly_grace_hours,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;

create or replace function private.parking_save_zone(
  p_id bigint,
  p_hotel text,
  p_name text,
  p_purpose text,
  p_active boolean,
  p_sort integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_name text;
begin
  if (select auth.uid()) is null or not private.parking_can_configure() then
    raise exception 'not allowed';
  end if;
  if not private.parking_hotel_ok(p_hotel) then
    raise exception 'unknown hotel';
  end if;
  v_name := btrim(coalesce(p_name, ''));
  if char_length(v_name) < 1 or char_length(v_name) > 40 then
    raise exception 'name required';
  end if;
  if p_purpose not in ('standard', 'long_term', 'park_fly') then
    raise exception 'unknown purpose';
  end if;
  if p_id is null then
    insert into public.parking_zones (hotel, name, purpose, active, sort_order)
    values (p_hotel, v_name, p_purpose, coalesce(p_active, true), coalesce(p_sort, 0))
    returning id into v_id;
    return v_id;
  end if;
  update public.parking_zones
    set name = v_name, purpose = p_purpose, active = coalesce(p_active, true), sort_order = coalesce(p_sort, sort_order)
  where id = p_id and hotel = p_hotel
  returning id into v_id;
  if v_id is null then
    raise exception 'unknown zone';
  end if;
  return v_id;
end;
$$;

create or replace function private.parking_save_stall(
  p_id bigint,
  p_hotel text,
  p_zone_id bigint,
  p_stall_no text,
  p_notes text,
  p_active boolean,
  p_sort integer
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id bigint;
  v_no text;
begin
  if (select auth.uid()) is null or not private.parking_can_configure() then
    raise exception 'not allowed';
  end if;
  if not private.parking_hotel_ok(p_hotel) then
    raise exception 'unknown hotel';
  end if;
  if not exists (select 1 from public.parking_zones z where z.id = p_zone_id and z.hotel = p_hotel) then
    raise exception 'unknown zone';
  end if;
  v_no := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_stall_no, ''), '[^A-Za-z0-9-]', '', 'g'));
  if v_no !~ '^[A-Z0-9-]{1,12}$' then
    raise exception 'stall number required';
  end if;
  if p_id is null then
    insert into public.parking_stalls (hotel, zone_id, stall_no, notes, active, sort_order)
    values (p_hotel, p_zone_id, v_no, nullif(btrim(p_notes), ''), coalesce(p_active, true), coalesce(p_sort, 0))
    returning id into v_id;
    return v_id;
  end if;
  update public.parking_stalls
    set zone_id = p_zone_id, stall_no = v_no, notes = nullif(btrim(p_notes), ''),
        active = coalesce(p_active, true), sort_order = coalesce(p_sort, sort_order)
  where id = p_id and hotel = p_hotel
  returning id into v_id;
  if v_id is null then
    raise exception 'unknown stall';
  end if;
  return v_id;
end;
$$;

create or replace function private.parking_save_range(
  p_id bigint,
  p_stall_id bigint,
  p_room_lo integer,
  p_room_hi integer,
  p_floor text,
  p_wing text,
  p_rank integer,
  p_active boolean
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hotel text;
  v_id bigint;
  v_floor text;
  v_wing text;
begin
  if (select auth.uid()) is null or not private.parking_can_configure() then
    raise exception 'not allowed';
  end if;
  select s.hotel into v_hotel from public.parking_stalls s where s.id = p_stall_id;
  if v_hotel is null or not private.parking_hotel_ok(v_hotel) then
    raise exception 'unknown stall';
  end if;
  v_floor := nullif(btrim(coalesce(p_floor, '')), '');
  v_wing := nullif(btrim(coalesce(p_wing, '')), '');
  if p_room_lo is null and p_room_hi is null and v_floor is null and v_wing is null then
    raise exception 'range required';
  end if;
  if p_rank is null or p_rank < 1 or p_rank > 99 then
    raise exception 'rank out of range';
  end if;
  if p_id is null then
    insert into public.parking_stall_ranges (hotel, stall_id, room_lo, room_hi, floor, wing, rank, active)
    values (v_hotel, p_stall_id, p_room_lo, p_room_hi, v_floor, v_wing, p_rank, coalesce(p_active, true))
    returning id into v_id;
    return v_id;
  end if;
  update public.parking_stall_ranges
    set stall_id = p_stall_id, hotel = v_hotel, room_lo = p_room_lo, room_hi = p_room_hi,
        floor = v_floor, wing = v_wing, rank = p_rank, active = coalesce(p_active, true)
  where id = p_id and hotel = v_hotel
  returning id into v_id;
  if v_id is null then
    raise exception 'unknown range';
  end if;
  return v_id;
end;
$$;

create or replace function private.parking_stall_align()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  z_hotel text;
begin
  select z.hotel into z_hotel from public.parking_zones z where z.id = new.zone_id;
  if z_hotel is null or z_hotel is distinct from new.hotel then
    raise exception 'stall hotel must match zone';
  end if;
  return new;
end;
$$;

create or replace function private.parking_range_align()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  s_hotel text;
begin
  select s.hotel into s_hotel from public.parking_stalls s where s.id = new.stall_id;
  if s_hotel is null then
    raise exception 'unknown stall';
  end if;
  new.hotel := s_hotel;
  return new;
end;
$$;

create or replace function private.parking_visit_stall()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.stall_id is not null and not exists (
    select 1 from public.parking_stalls s where s.id = new.stall_id and s.hotel = new.hotel
  ) then
    raise exception 'stall hotel';
  end if;
  return new;
end;
$$;

drop trigger if exists parking_stall_align on public.parking_stalls;
create trigger parking_stall_align
  before insert or update on public.parking_stalls
  for each row execute function private.parking_stall_align();

drop trigger if exists parking_range_align on public.parking_stall_ranges;
create trigger parking_range_align
  before insert or update on public.parking_stall_ranges
  for each row execute function private.parking_range_align();

drop trigger if exists parking_visit_stall on public.parking_visits;
create trigger parking_visit_stall
  before insert or update on public.parking_visits
  for each row execute function private.parking_visit_stall();

create or replace function public.parking_suggest_stall(
  p_hotel text, p_room text, p_checked_in timestamptz, p_expected_out timestamptz, p_long_term boolean, p_vehicle_type text
) returns bigint
language sql security invoker set search_path = ''
as $$ select private.parking_suggest_stall(p_hotel, p_room, p_checked_in, p_expected_out, p_long_term, p_vehicle_type); $$;

create or replace function public.parking_log_visit(
  p_hotel text, p_plate text, p_state text, p_make text, p_model text, p_color text, p_stall_id bigint, p_room text,
  p_checked_in timestamptz, p_expected_out timestamptz, p_permit text, p_paid boolean, p_rate_note text, p_long_term boolean,
  p_unknown boolean, p_vehicle_type text, p_pf_confirm text, p_pf_days integer, p_pf_dropoff date, p_pf_pickup timestamptz,
  p_pf_flight text, p_pf_extra_note text, p_note text
) returns bigint
language sql security invoker set search_path = ''
as $$
  select private.parking_log_visit(
    p_hotel, p_plate, p_state, p_make, p_model, p_color, p_stall_id, p_room, p_checked_in, p_expected_out, p_permit,
    p_paid, p_rate_note, p_long_term, p_unknown, p_vehicle_type, p_pf_confirm, p_pf_days, p_pf_dropoff, p_pf_pickup,
    p_pf_flight, p_pf_extra_note, p_note
  );
$$;

create or replace function public.parking_mark_out(p_id bigint, p_out timestamptz)
returns void language sql security invoker set search_path = ''
as $$ select private.parking_mark_out(p_id, p_out); $$;

create or replace function public.parking_save_settings(
  p_hotel text, p_max_hours integer, p_long_term_nights integer, p_park_fly boolean, p_grace_hours integer
) returns void language sql security invoker set search_path = ''
as $$ select private.parking_save_settings(p_hotel, p_max_hours, p_long_term_nights, p_park_fly, p_grace_hours); $$;

create or replace function public.parking_save_zone(
  p_id bigint, p_hotel text, p_name text, p_purpose text, p_active boolean, p_sort integer
) returns bigint language sql security invoker set search_path = ''
as $$ select private.parking_save_zone(p_id, p_hotel, p_name, p_purpose, p_active, p_sort); $$;

create or replace function public.parking_save_stall(
  p_id bigint, p_hotel text, p_zone_id bigint, p_stall_no text, p_notes text, p_active boolean, p_sort integer
) returns bigint language sql security invoker set search_path = ''
as $$ select private.parking_save_stall(p_id, p_hotel, p_zone_id, p_stall_no, p_notes, p_active, p_sort); $$;

create or replace function public.parking_save_range(
  p_id bigint, p_stall_id bigint, p_room_lo integer, p_room_hi integer, p_floor text, p_wing text, p_rank integer, p_active boolean
) returns bigint language sql security invoker set search_path = ''
as $$ select private.parking_save_range(p_id, p_stall_id, p_room_lo, p_room_hi, p_floor, p_wing, p_rank, p_active); $$;

create or replace view public.parking_visit_times
with (security_invoker = true) as
select v.id, v.hotel, v.checked_in_at, v.checked_out_at,
  coalesce(v.checked_out_at, pg_catalog.now()) - v.checked_in_at as parked_for
from public.parking_visits v;

comment on view public.parking_visit_times is
  'Parked duration. Still on the lot uses now(). Checked out uses the time out.';

drop policy if exists parking_settings_select on public.parking_settings;
create policy parking_settings_select on public.parking_settings
  for select to authenticated
  using (
    (select private.parking_can_log())
    and (
      (select private.is_above())
      or hotel = any ((select private.my_hotels())::text[])
    )
  );

drop policy if exists parking_zones_select on public.parking_zones;
create policy parking_zones_select on public.parking_zones
  for select to authenticated
  using (
    (select private.parking_can_log())
    and (
      (select private.is_above())
      or hotel = any ((select private.my_hotels())::text[])
    )
  );

drop policy if exists parking_stalls_select on public.parking_stalls;
create policy parking_stalls_select on public.parking_stalls
  for select to authenticated
  using (
    (select private.parking_can_log())
    and (
      (select private.is_above())
      or hotel = any ((select private.my_hotels())::text[])
    )
  );

drop policy if exists parking_stall_ranges_select on public.parking_stall_ranges;
create policy parking_stall_ranges_select on public.parking_stall_ranges
  for select to authenticated
  using (
    (select private.parking_can_log())
    and (
      (select private.is_above())
      or hotel = any ((select private.my_hotels())::text[])
    )
  );

drop policy if exists parking_visits_select on public.parking_visits;
create policy parking_visits_select on public.parking_visits
  for select to authenticated
  using (
    (select private.parking_can_log())
    and (
      (select private.is_above())
      or hotel = any ((select private.my_hotels())::text[])
    )
  );

revoke all on function private.parking_can_log() from public, anon;
revoke all on function private.parking_can_configure() from public, anon;
revoke all on function private.parking_hotel_ok(text) from public, anon;
revoke all on function private.parking_suggest_stall(text, text, timestamptz, timestamptz, boolean, text) from public, anon;
revoke all on function private.parking_log_visit(text, text, text, text, text, text, bigint, text, timestamptz, timestamptz, text, boolean, text, boolean, boolean, text, text, integer, date, timestamptz, text, text, text) from public, anon;
revoke all on function private.parking_mark_out(bigint, timestamptz) from public, anon;
revoke all on function private.parking_save_settings(text, integer, integer, boolean, integer) from public, anon;
revoke all on function private.parking_save_zone(bigint, text, text, text, boolean, integer) from public, anon;
revoke all on function private.parking_save_stall(bigint, text, bigint, text, text, boolean, integer) from public, anon;
revoke all on function private.parking_save_range(bigint, bigint, integer, integer, text, text, integer, boolean) from public, anon;
revoke all on function private.parking_stall_align() from public, anon;
revoke all on function private.parking_range_align() from public, anon;
revoke all on function private.parking_visit_stall() from public, anon;
revoke all on function public.parking_suggest_stall(text, text, timestamptz, timestamptz, boolean, text) from public, anon;
revoke all on function public.parking_log_visit(text, text, text, text, text, text, bigint, text, timestamptz, timestamptz, text, boolean, text, boolean, boolean, text, text, integer, date, timestamptz, text, text, text) from public, anon;
revoke all on function public.parking_mark_out(bigint, timestamptz) from public, anon;
revoke all on function public.parking_save_settings(text, integer, integer, boolean, integer) from public, anon;
revoke all on function public.parking_save_zone(bigint, text, text, text, boolean, integer) from public, anon;
revoke all on function public.parking_save_stall(bigint, text, bigint, text, text, boolean, integer) from public, anon;
revoke all on function public.parking_save_range(bigint, bigint, integer, integer, text, text, integer, boolean) from public, anon;

grant execute on function private.parking_can_log() to authenticated;
grant execute on function private.parking_can_configure() to authenticated;
grant execute on function private.parking_hotel_ok(text) to authenticated;
grant execute on function private.parking_suggest_stall(text, text, timestamptz, timestamptz, boolean, text) to authenticated;
grant execute on function private.parking_log_visit(text, text, text, text, text, text, bigint, text, timestamptz, timestamptz, text, boolean, text, boolean, boolean, text, text, integer, date, timestamptz, text, text, text) to authenticated;
grant execute on function private.parking_mark_out(bigint, timestamptz) to authenticated;
grant execute on function private.parking_save_settings(text, integer, integer, boolean, integer) to authenticated;
grant execute on function private.parking_save_zone(bigint, text, text, text, boolean, integer) to authenticated;
grant execute on function private.parking_save_stall(bigint, text, bigint, text, text, boolean, integer) to authenticated;
grant execute on function private.parking_save_range(bigint, bigint, integer, integer, text, text, integer, boolean) to authenticated;
grant execute on function private.parking_stall_align() to authenticated;
grant execute on function private.parking_range_align() to authenticated;
grant execute on function private.parking_visit_stall() to authenticated;
grant execute on function public.parking_suggest_stall(text, text, timestamptz, timestamptz, boolean, text) to authenticated;
grant execute on function public.parking_log_visit(text, text, text, text, text, text, bigint, text, timestamptz, timestamptz, text, boolean, text, boolean, boolean, text, text, integer, date, timestamptz, text, text, text) to authenticated;
grant execute on function public.parking_mark_out(bigint, timestamptz) to authenticated;
grant execute on function public.parking_save_settings(text, integer, integer, boolean, integer) to authenticated;
grant execute on function public.parking_save_zone(bigint, text, text, text, boolean, integer) to authenticated;
grant execute on function public.parking_save_stall(bigint, text, bigint, text, text, boolean, integer) to authenticated;
grant execute on function public.parking_save_range(bigint, bigint, integer, integer, text, text, integer, boolean) to authenticated;

revoke all on table public.parking_settings from public, anon, authenticated;
revoke all on table public.parking_zones from public, anon, authenticated;
revoke all on table public.parking_stalls from public, anon, authenticated;
revoke all on table public.parking_stall_ranges from public, anon, authenticated;
revoke all on table public.parking_visits from public, anon, authenticated;
revoke all on table public.parking_visit_times from public, anon, authenticated;

grant select on table public.parking_settings to authenticated;
grant select on table public.parking_zones to authenticated;
grant select on table public.parking_stalls to authenticated;
grant select on table public.parking_stall_ranges to authenticated;
grant select on table public.parking_visits to authenticated;
grant select on table public.parking_visit_times to authenticated;

revoke all on sequence public.parking_zones_id_seq from public, anon, authenticated;
revoke all on sequence public.parking_stalls_id_seq from public, anon, authenticated;
revoke all on sequence public.parking_stall_ranges_id_seq from public, anon, authenticated;
revoke all on sequence public.parking_visits_id_seq from public, anon, authenticated;
