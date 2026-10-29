-- Outbound shuttle sign-up for the shared Hampton (MSPAM) and SpringHill (MSPMS) van.
-- Rides from the hotel to MSP Terminal 1, Terminal 2, or Mall of America are booked here.
-- Return pickups stay in TrackMyShuttle. This migration does not build pickup dispatch.
-- The guest tracking code and the TrackMyShuttle URL live in shuttle_settings.
-- Seeded codes: Hampton 2860, SpringHill 2871. A GM or corporate can change them later.
-- Golden Valley (MSPWE) is hidden with hotel_features feature 'shuttle' = false.
-- Additive only: no drops and no deletes.
--
-- Read access for a hotel uses
--   hotel = any ((select private.my_hotels())::text[])
-- so the list is read once and the check is text = any(text[]).
-- The shuttle queue is the exception. Front desk, GM, AGM, and shuttle drivers
-- whose hotels overlap the airport pool see both MSPAM and MSPMS sign-ups.
-- That branch still requires the row's hotel to be in the shuttle pool.
-- Golden Valley is not in the pool, so MSPWE never sees this queue.
-- No other HotelHQ table is widened. These rows store only the sign-up fields:
-- hotel, destination, time, last name or room, party, bags, notes, flight time,
-- and status. No phone, billing, rate, or plate.
-- Seat totals come from shuttle_day_counts, which returns a number per departure.

create schema if not exists private;

grant usage on schema private to authenticated;

-- hotel_features already exists. Add shuttle to the allowed module list.
alter table public.hotel_features drop constraint if exists hotel_features_feature_check;

alter table public.hotel_features add constraint hotel_features_feature_check
  check (feature in ('parking', 'sales_leads', 'greetings', 'guest_scores', 'shuttle'));

create table if not exists public.shuttle_settings (
  hotel text primary key check (hotel in ('MSPAM', 'MSPMS')),
  tracking_code text check (tracking_code is null or tracking_code ~ '^[0-9A-Za-z]{1,12}$'),
  slot_minutes integer not null default 30 check (slot_minutes in (15, 20, 30, 60)),
  seat_capacity integer not null default 14 check (seat_capacity between 1 and 30),
  open_minute integer not null default 300 check (open_minute between 0 and 1439),
  close_minute integer not null default 1380 check (close_minute between 1 and 1440),
  track_url text not null default 'https://www.trackmyshuttle.com/' check (track_url ~ '^https://'),
  pickup_order text[] not null default array['MSPAM', 'MSPMS']::text[],
  updated_by uuid,
  updated_at timestamptz not null default pg_catalog.now(),
  check (close_minute > open_minute),
  check (
    cardinality(pickup_order) = 2
    and pickup_order <@ array['MSPAM', 'MSPMS']::text[]
    and array['MSPAM', 'MSPMS']::text[] <@ pickup_order
  )
);

comment on table public.shuttle_settings is
  'Per-hotel TrackMyShuttle guest code. Slot length, seats, hours, URL, and pickup order are the shared van and are kept identical on both rows.';

comment on column public.shuttle_settings.tracking_code is
  'Code the guest types into TrackMyShuttle. Hampton seed 2860. SpringHill seed 2871. Not a phone number.';

create table if not exists public.shuttle_signups (
  id bigint generated always as identity primary key,
  hotel text not null check (hotel in ('MSPAM', 'MSPMS')),
  destination text not null check (destination in ('t1', 't2', 'moa', 'other')),
  destination_note text check (destination_note is null or char_length(btrim(destination_note)) between 1 and 80),
  depart_at timestamptz not null,
  guest_label text not null check (char_length(btrim(guest_label)) between 1 and 40),
  label_kind text not null check (label_kind in ('name', 'room')),
  party_size integer not null check (party_size between 1 and 14),
  bags integer not null default 0 check (bags between 0 and 20),
  notes text check (notes is null or char_length(notes) <= 200),
  flight_time text check (flight_time is null or flight_time ~ '^[0-2][0-9]:[0-5][0-9]$'),
  status text not null default 'booked' check (status in ('booked', 'boarded', 'no_show', 'done')),
  status_at timestamptz,
  boarded_at timestamptz,
  noshow_at timestamptz,
  done_at timestamptz,
  parking_visit_id bigint references public.parking_visits (id) on delete set null,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default pg_catalog.now(),
  check (destination <> 'other' or destination_note is not null),
  check (guest_label !~ '[0-9]{7,}')
);

comment on table public.shuttle_signups is
  'Outbound ride leaving the hotel. guest_label is a last name or a room number. No phone number.';

create index if not exists shuttle_signups_depart_idx on public.shuttle_signups (depart_at);
create index if not exists shuttle_signups_hotel_depart_idx on public.shuttle_signups (hotel, depart_at);
create index if not exists shuttle_signups_parking_idx on public.shuttle_signups (parking_visit_id) where parking_visit_id is not null;

alter table public.shuttle_settings enable row level security;
alter table public.shuttle_signups enable row level security;

insert into public.hotel_features (hotel, feature, enabled) values
  ('MSPWE', 'shuttle', false),
  ('MSPAM', 'shuttle', true),
  ('MSPMS', 'shuttle', true)
on conflict (hotel, feature) do nothing;

insert into public.shuttle_settings (hotel, tracking_code) values
  ('MSPAM', '2860'),
  ('MSPMS', '2871')
on conflict (hotel) do update
  set tracking_code = coalesce(public.shuttle_settings.tracking_code, excluded.tracking_code);

create or replace function private.shuttle_pool()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(f.hotel order by f.hotel), '{}'::text[])
  from public.hotel_features f
  where f.feature = 'shuttle' and f.enabled;
$$;

create or replace function private.shuttle_feature_on(p_hotel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.hotel_features f
    where f.hotel = p_hotel and f.feature = 'shuttle' and f.enabled
  );
$$;

create or replace function private.shuttle_driver_in_pool()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.my_role() = 'shuttle_driver'
    and exists (
      select 1
      from unnest((select private.my_hotels())::text[]) h
      where h = any (private.shuttle_pool())
    ),
    false
  );
$$;

-- Front desk, GM, AGM, and drivers at a pool hotel. MSPWE staff do not match.
create or replace function private.shuttle_staff_in_pool()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.my_role() in ('front_desk', 'gm', 'agm', 'shuttle_driver')
    and exists (
      select 1
      from unnest((select private.my_hotels())::text[]) h
      where h = any (private.shuttle_pool())
    ),
    false
  );
$$;

create or replace function private.shuttle_can_book()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.is_above() or private.my_role() in ('front_desk', 'gm', 'agm'),
    false
  );
$$;

create or replace function private.shuttle_can_configure()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(private.is_above() or private.my_role() in ('gm', 'agm'), false);
$$;

create or replace function private.shuttle_hotel_ok(p_hotel text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    p_hotel in ('MSPAM', 'MSPMS')
    and private.shuttle_feature_on(p_hotel)
    and (
      private.is_above()
      or p_hotel = any ((select private.my_hotels())::text[])
    ),
    false
  );
$$;

create or replace function private.shuttle_settings_row()
returns public.shuttle_settings
language sql
stable
security definer
set search_path = ''
as $$
  select s.hotel, s.tracking_code, s.slot_minutes, s.seat_capacity, s.open_minute,
    s.close_minute, s.track_url, s.pickup_order, s.updated_by, s.updated_at
  from public.shuttle_settings s
  order by s.hotel
  limit 1;
$$;

create or replace function public.shuttle_day_counts(p_day date)
returns table (depart_at timestamptz, seats integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(
    private.is_above()
    or private.my_role() in ('front_desk', 'gm', 'agm', 'shuttle_driver'),
    false
  ) then
    return;
  end if;
  if not (
    (select private.is_above())
    or (select private.shuttle_driver_in_pool())
    or exists (
      select 1
      from unnest((select private.my_hotels())::text[]) h
      where h = any (private.shuttle_pool())
    )
  ) then
    return;
  end if;
  return query
  select s.depart_at, coalesce(sum(s.party_size), 0)::integer
  from public.shuttle_signups s
  where (s.depart_at at time zone 'America/Chicago')::date = p_day
    and s.status <> 'no_show'
    and s.hotel = any (private.shuttle_pool())
  group by s.depart_at;
end;
$$;

create or replace function public.shuttle_ridership(p_day date)
returns table (hotel text, destination text, signed_up integer, rode integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(private.is_above() or private.my_role() in ('gm', 'agm'), false) then
    return;
  end if;
  if not (
    (select private.is_above())
    or exists (
      select 1
      from unnest((select private.my_hotels())::text[]) h
      where h = any (private.shuttle_pool())
    )
  ) then
    return;
  end if;
  return query
  select s.hotel,
    s.destination,
    coalesce(sum(s.party_size) filter (where s.status <> 'no_show'), 0)::integer,
    coalesce(sum(s.party_size) filter (where s.status in ('boarded', 'done')), 0)::integer
  from public.shuttle_signups s
  where (s.depart_at at time zone 'America/Chicago')::date = p_day
    and s.hotel = any (private.shuttle_pool())
  group by s.hotel, s.destination
  order by s.hotel, s.destination;
end;
$$;

create or replace function private.shuttle_book(
  p_hotel text,
  p_destination text,
  p_destination_note text,
  p_depart timestamptz,
  p_guest_label text,
  p_label_kind text,
  p_party integer,
  p_bags integer,
  p_notes text,
  p_flight text,
  p_parking_visit bigint
) returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_cfg public.shuttle_settings;
  v_local timestamp;
  v_min integer;
  v_used integer;
  v_note text;
  v_label text;
  v_flight text;
  v_notes text;
  v_id bigint;
begin
  if not private.shuttle_can_book() then
    raise exception 'role';
  end if;
  if not private.shuttle_hotel_ok(p_hotel) then
    raise exception 'hotel';
  end if;
  if p_destination not in ('t1', 't2', 'moa', 'other') then
    raise exception 'destination';
  end if;
  v_note := nullif(btrim(coalesce(p_destination_note, '')), '');
  if p_destination = 'other' then
    if v_note is null or char_length(v_note) > 80 then
      raise exception 'destination';
    end if;
  else
    v_note := null;
  end if;
  if p_label_kind not in ('name', 'room') then
    raise exception 'label';
  end if;
  v_label := btrim(coalesce(p_guest_label, ''));
  if p_label_kind = 'room' then
    if v_label !~ '^[0-9]{2,4}$' then
      raise exception 'label';
    end if;
  else
    if v_label !~ '^[A-Za-z][A-Za-z .''-]{0,39}$' then
      raise exception 'label';
    end if;
  end if;
  if v_label ~ '[0-9]{7,}' then
    raise exception 'phone';
  end if;
  if p_party is null or p_party < 1 or p_party > 14 then
    raise exception 'party';
  end if;
  if p_bags is null or p_bags < 0 or p_bags > 20 then
    raise exception 'bags';
  end if;
  v_flight := nullif(btrim(coalesce(p_flight, '')), '');
  if v_flight is not null and v_flight !~ '^[0-2][0-9]:[0-5][0-9]$' then
    raise exception 'flight';
  end if;
  v_notes := nullif(btrim(coalesce(p_notes, '')), '');
  if v_notes is not null and char_length(v_notes) > 200 then
    raise exception 'notes';
  end if;
  if p_depart is null then
    raise exception 'slot';
  end if;
  v_cfg := private.shuttle_settings_row();
  if v_cfg is null or v_cfg.hotel is null then
    raise exception 'slot';
  end if;
  v_local := p_depart at time zone 'America/Chicago';
  if date_trunc('minute', v_local) <> v_local then
    raise exception 'slot';
  end if;
  v_min := (extract(hour from v_local))::integer * 60 + (extract(minute from v_local))::integer;
  if v_min < v_cfg.open_minute or v_min > v_cfg.close_minute or ((v_min - v_cfg.open_minute) % v_cfg.slot_minutes) <> 0 then
    raise exception 'slot';
  end if;
  if p_parking_visit is not null then
    if not exists (
      select 1 from public.parking_visits v
      where v.id = p_parking_visit
        and v.hotel = p_hotel
        and v.vehicle_type = 'park_fly'
        and v.checked_out_at is null
    ) then
      raise exception 'parking';
    end if;
    if exists (
      select 1 from public.shuttle_signups s
      where s.parking_visit_id = p_parking_visit
        and s.status in ('booked', 'boarded')
    ) then
      raise exception 'already';
    end if;
  end if;
  select coalesce(sum(s.party_size), 0) into v_used
  from public.shuttle_signups s
  where s.depart_at = p_depart
    and s.status <> 'no_show'
    and s.hotel = any (private.shuttle_pool());
  if v_used + p_party > v_cfg.seat_capacity then
    raise exception 'full';
  end if;
  insert into public.shuttle_signups (
    hotel, destination, destination_note, depart_at, guest_label, label_kind,
    party_size, bags, notes, flight_time, status, parking_visit_id, created_by
  ) values (
    p_hotel, p_destination, v_note, p_depart, v_label, p_label_kind,
    p_party, p_bags, v_notes, v_flight, 'booked', p_parking_visit, auth.uid()
  ) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.shuttle_book(
  p_hotel text,
  p_destination text,
  p_destination_note text,
  p_depart timestamptz,
  p_guest_label text,
  p_label_kind text,
  p_party integer,
  p_bags integer,
  p_notes text,
  p_flight text,
  p_parking_visit bigint
) returns bigint
language sql
security invoker
set search_path = ''
as $$
  select private.shuttle_book(
    p_hotel, p_destination, p_destination_note, p_depart, p_guest_label, p_label_kind,
    p_party, p_bags, p_notes, p_flight, p_parking_visit
  );
$$;

create or replace function private.shuttle_set_status(p_id bigint, p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_hotel text;
  v_now timestamptz := pg_catalog.now();
begin
  if p_status not in ('boarded', 'no_show', 'done') then
    raise exception 'status';
  end if;
  select s.hotel into v_hotel from public.shuttle_signups s where s.id = p_id;
  if v_hotel is null then
    raise exception 'missing';
  end if;
  if not (
    (select private.is_above())
    or (
      (select private.shuttle_staff_in_pool())
      and v_hotel = any (private.shuttle_pool())
    )
  ) then
    raise exception 'role';
  end if;
  update public.shuttle_signups s
  set status = p_status,
      status_at = v_now,
      boarded_at = case when p_status = 'boarded' then v_now else s.boarded_at end,
      noshow_at = case when p_status = 'no_show' then v_now else s.noshow_at end,
      done_at = case when p_status = 'done' then v_now else s.done_at end
  where s.id = p_id;
end;
$$;

create or replace function public.shuttle_set_status(p_id bigint, p_status text)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.shuttle_set_status(p_id, p_status);
$$;

create or replace function private.shuttle_save_settings(
  p_hotel text,
  p_tracking_code text,
  p_slot_minutes integer,
  p_seat_capacity integer,
  p_open_minute integer,
  p_close_minute integer,
  p_track_url text,
  p_pickup_order text[]
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_code text;
begin
  if not private.shuttle_can_configure() then
    raise exception 'role';
  end if;
  if not private.shuttle_hotel_ok(p_hotel) then
    raise exception 'hotel';
  end if;
  if p_slot_minutes not in (15, 20, 30, 60) then
    raise exception 'slot';
  end if;
  if p_seat_capacity is null or p_seat_capacity < 1 or p_seat_capacity > 30 then
    raise exception 'capacity';
  end if;
  if p_open_minute is null or p_close_minute is null
     or p_open_minute < 0 or p_close_minute > 1440
     or p_close_minute <= p_open_minute then
    raise exception 'hours';
  end if;
  if p_pickup_order is null
     or cardinality(p_pickup_order) <> 2
     or not (
       p_pickup_order <@ array['MSPAM', 'MSPMS']::text[]
       and array['MSPAM', 'MSPMS']::text[] <@ p_pickup_order
     ) then
    raise exception 'order';
  end if;
  v_code := nullif(btrim(coalesce(p_tracking_code, '')), '');
  if v_code is not null and v_code !~ '^[0-9A-Za-z]{1,12}$' then
    raise exception 'code';
  end if;
  select s.track_url into v_url from public.shuttle_settings s where s.hotel = p_hotel;
  if private.is_above() and nullif(btrim(coalesce(p_track_url, '')), '') is not null then
    if btrim(p_track_url) !~ '^https://' then
      raise exception 'url';
    end if;
    v_url := btrim(p_track_url);
  end if;
  if v_url is null or v_url !~ '^https://' then
    v_url := 'https://www.trackmyshuttle.com/';
  end if;
  update public.shuttle_settings s
  set slot_minutes = p_slot_minutes,
      seat_capacity = p_seat_capacity,
      open_minute = p_open_minute,
      close_minute = p_close_minute,
      track_url = v_url,
      pickup_order = p_pickup_order,
      updated_at = pg_catalog.now()
  where s.hotel in ('MSPAM', 'MSPMS');
  update public.shuttle_settings s
  set tracking_code = v_code,
      updated_by = auth.uid(),
      updated_at = pg_catalog.now()
  where s.hotel = p_hotel;
end;
$$;

create or replace function public.shuttle_save_settings(
  p_hotel text,
  p_tracking_code text,
  p_slot_minutes integer,
  p_seat_capacity integer,
  p_open_minute integer,
  p_close_minute integer,
  p_track_url text,
  p_pickup_order text[]
) returns void
language sql
security invoker
set search_path = ''
as $$
  select private.shuttle_save_settings(
    p_hotel, p_tracking_code, p_slot_minutes, p_seat_capacity, p_open_minute,
    p_close_minute, p_track_url, p_pickup_order
  );
$$;

-- hotel_features keeps its own-hotel read policy. Shuttle rows add one pool
-- branch so Hampton and SpringHill front desks and drivers see both hotels.
-- MSPWE is not in that pool. No other HotelHQ table is widened.

create or replace function private.set_hotel_feature(
  p_hotel text,
  p_feature text,
  p_enabled boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not private.hotel_feature_is_corporate() then
    raise exception 'not allowed';
  end if;
  if p_hotel not in ('MSPWE', 'MSPAM', 'MSPMS') then
    raise exception 'unknown hotel';
  end if;
  if p_feature not in ('parking', 'sales_leads', 'greetings', 'guest_scores', 'shuttle') then
    raise exception 'unknown feature';
  end if;
  insert into public.hotel_features (hotel, feature, enabled, updated_by, updated_at)
  values (p_hotel, p_feature, coalesce(p_enabled, true), (select auth.uid()), pg_catalog.now())
  on conflict (hotel, feature) do update
    set enabled = excluded.enabled,
        updated_by = excluded.updated_by,
        updated_at = excluded.updated_at;
end;
$$;

create or replace function public.set_hotel_feature(
  p_hotel text,
  p_feature text,
  p_enabled boolean
)
returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_hotel_feature(p_hotel, p_feature, p_enabled);
$$;

drop policy if exists shuttle_settings_select on public.shuttle_settings;
create policy shuttle_settings_select on public.shuttle_settings
  for select to authenticated
  using (
    (select private.is_above())
    or hotel = any ((select private.my_hotels())::text[])
    or (
      (select private.shuttle_staff_in_pool())
      and hotel = any (private.shuttle_pool())
    )
  );

drop policy if exists shuttle_signups_select on public.shuttle_signups;
create policy shuttle_signups_select on public.shuttle_signups
  for select to authenticated
  using (
    (select private.is_above())
    or hotel = any ((select private.my_hotels())::text[])
    or (
      (select private.shuttle_staff_in_pool())
      and hotel = any (private.shuttle_pool())
    )
  );

revoke all on function private.shuttle_pool() from public, anon;
revoke all on function private.shuttle_feature_on(text) from public, anon;
revoke all on function private.shuttle_driver_in_pool() from public, anon;
revoke all on function private.shuttle_staff_in_pool() from public, anon;
revoke all on function private.shuttle_can_book() from public, anon;
revoke all on function private.shuttle_can_configure() from public, anon;
revoke all on function private.shuttle_hotel_ok(text) from public, anon;
revoke all on function private.shuttle_settings_row() from public, anon;
revoke all on function private.shuttle_book(text, text, text, timestamptz, text, text, integer, integer, text, text, bigint) from public, anon;
revoke all on function private.shuttle_set_status(bigint, text) from public, anon;
revoke all on function private.shuttle_save_settings(text, text, integer, integer, integer, integer, text, text[]) from public, anon;
revoke all on function public.shuttle_day_counts(date) from public, anon;
revoke all on function public.shuttle_ridership(date) from public, anon;
revoke all on function public.shuttle_book(text, text, text, timestamptz, text, text, integer, integer, text, text, bigint) from public, anon;
revoke all on function public.shuttle_set_status(bigint, text) from public, anon;
revoke all on function public.shuttle_save_settings(text, text, integer, integer, integer, integer, text, text[]) from public, anon;

grant execute on function private.shuttle_pool() to authenticated;
grant execute on function private.shuttle_feature_on(text) to authenticated;
grant execute on function private.shuttle_driver_in_pool() to authenticated;
grant execute on function private.shuttle_staff_in_pool() to authenticated;
grant execute on function private.shuttle_can_book() to authenticated;
grant execute on function private.shuttle_can_configure() to authenticated;
grant execute on function private.shuttle_hotel_ok(text) to authenticated;
grant execute on function private.shuttle_settings_row() to authenticated;
grant execute on function private.shuttle_book(text, text, text, timestamptz, text, text, integer, integer, text, text, bigint) to authenticated;
grant execute on function private.shuttle_set_status(bigint, text) to authenticated;
grant execute on function private.shuttle_save_settings(text, text, integer, integer, integer, integer, text, text[]) to authenticated;
grant execute on function public.shuttle_day_counts(date) to authenticated;
grant execute on function public.shuttle_ridership(date) to authenticated;
grant execute on function public.shuttle_book(text, text, text, timestamptz, text, text, integer, integer, text, text, bigint) to authenticated;
grant execute on function public.shuttle_set_status(bigint, text) to authenticated;
grant execute on function public.shuttle_save_settings(text, text, integer, integer, integer, integer, text, text[]) to authenticated;

revoke all on table public.hotel_features from public, anon, authenticated;
revoke all on table public.shuttle_settings from public, anon, authenticated;
revoke all on table public.shuttle_signups from public, anon, authenticated;

grant select on table public.hotel_features to authenticated;
grant select on table public.shuttle_settings to authenticated;
grant select on table public.shuttle_signups to authenticated;

revoke all on sequence public.shuttle_signups_id_seq from public, anon, authenticated;
