-- DESIGN ONLY. NOT APPLIED. Labor plan edits (JR Corporate only) + training hour requests.
-- Assumes public.staff_profiles(user_id uuid, role text, hotel_id text) maps auth.uid() to role/hotel.
-- HotelHQ currently stores this in localStorage (jrportal_lplan_v1, jrportal_trreq_v1).

create or replace function public.hq_is_corporate() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from staff_profiles where user_id=auth.uid() and role='Above Property') $$;
create or replace function public.hq_my_hotel() returns text language sql stable security definer set search_path=public as $$
  select hotel_id from staff_profiles where user_id=auth.uid() limit 1 $$;
create or replace function public.hq_is_gm_agm() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from staff_profiles where user_id=auth.uid() and role in ('GM','AGM')) $$;

create table if not exists public.labor_plan_edits (
  id bigint generated always as identity primary key,
  hotel_id text not null check (hotel_id in ('MSPWE','MSPAM','MSPMS','SHUTTLE')),
  week_start date not null,                -- Monday
  kind text not null check (kind in ('position','associate','rooms')),
  line text not null,                      -- position name, associate id, or 'rooms'
  day_values numeric(5,1)[] not null check (array_length(day_values,1)=7),  -- Mon..Sun
  change_note text not null,
  edited_by uuid not null default auth.uid() references auth.users(id),
  edited_at timestamptz not null default now(),
  unique (hotel_id, week_start, kind, line)
);
create table if not exists public.labor_plan_edit_log (
  id bigint generated always as identity primary key,
  edit_id bigint references public.labor_plan_edits(id) on delete set null,
  hotel_id text not null, week_start date not null, kind text not null, line text not null,
  old_values numeric(5,1)[], new_values numeric(5,1)[], change_note text,
  edited_by uuid default auth.uid(), edited_at timestamptz default now()
);
alter table public.labor_plan_edits enable row level security;
alter table public.labor_plan_edit_log enable row level security;
create policy lpe_read on public.labor_plan_edits for select to authenticated using (hq_is_corporate() or hotel_id=hq_my_hotel());
create policy lpe_write on public.labor_plan_edits for all to authenticated using (hq_is_corporate()) with check (hq_is_corporate());
create policy lpl_read on public.labor_plan_edit_log for select to authenticated using (hq_is_corporate() or hotel_id=hq_my_hotel());
create policy lpl_write on public.labor_plan_edit_log for insert to authenticated with check (hq_is_corporate());

create table if not exists public.training_hour_requests (
  id bigint generated always as identity primary key,
  hotel_id text not null check (hotel_id in ('MSPWE','MSPAM','MSPMS')),
  associate text not null,                 -- associate id or 'New hire (TBD)'
  position text not null,
  trainer text,
  week_start date not null,
  days boolean[] not null check (array_length(days,1)=7),
  hours_per_day numeric(4,1) not null check (hours_per_day between 0 and 16),
  reason text not null check (reason in ('new','cross','brand','other')),
  notes text,
  status text not null default 'Pending' check (status in ('Pending','Approved','Denied')),
  corp_comment text,
  requested_by uuid not null default auth.uid(), requested_at timestamptz not null default now(),
  decided_by uuid, decided_at timestamptz
);
alter table public.training_hour_requests enable row level security;
-- GM/AGM (own hotel) and corporate can read; nobody else sees training requests.
create policy thr_read on public.training_hour_requests for select to authenticated
  using (hq_is_corporate() or (hq_is_gm_agm() and hotel_id=hq_my_hotel()));
-- GM/AGM submit for their own hotel, always Pending.
create policy thr_insert on public.training_hour_requests for insert to authenticated
  with check (hq_is_gm_agm() and hotel_id=hq_my_hotel() and status='Pending' and decided_by is null);
-- Only corporate approves / denies / adjusts hours.
create policy thr_decide on public.training_hour_requests for update to authenticated
  using (hq_is_corporate()) with check (hq_is_corporate());
-- Approved rows show as a separate 'Training' line in the plan (view, not merged into labor_plans).
create or replace view public.training_plan_lines with (security_invoker=true) as
  select hotel_id, week_start, position, associate, days, hours_per_day from public.training_hour_requests where status='Approved';
