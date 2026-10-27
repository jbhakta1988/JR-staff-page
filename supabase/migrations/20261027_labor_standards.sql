-- DESIGN ONLY - NOT APPLIED. Occupancy-driven labor standards + out-time standards + occupancy overrides.
-- Corporate (above_property) writes; hotel staff with GM/AGM read their own hotel.
create table if not exists public.labor_standards (
  hotel_id text not null,
  position text not null,              -- 'Front Desk','Housekeeper',... or '_hotel' for hotel-level row
  fixed_hours numeric default 0,       -- hrs/day regardless of occupancy
  hours_per_occ_room numeric default 0,-- variable hrs per occupied room
  mpr_minutes numeric,                 -- housekeeper minutes per room
  min_hours numeric, max_hours numeric,
  total_rooms int, auto_recalc boolean default false,
  out_time jsonb default '{}'::jsonb,  -- {co,so,oth,brk,side,lbsCO,lbsSO,lbsLoad,minLoad,sup,t_pub,...}
  updated_by uuid, updated_at timestamptz default now(),
  primary key (hotel_id, position)
);
create table if not exists public.occupancy_overrides (
  hotel_id text not null, stay_date date not null, occupied_rooms int not null,
  calc_snapshot int, updated_by uuid, updated_at timestamptz default now(),
  primary key (hotel_id, stay_date)
);
alter table public.labor_standards enable row level security;
alter table public.occupancy_overrides enable row level security;
-- assumes helper functions public.app_role() and public.app_hotel() from staff profile
create policy ls_read on public.labor_standards for select using (public.app_role()='above_property' or (public.app_role() in ('gm','agm') and hotel_id=public.app_hotel()));
create policy ls_write on public.labor_standards for all using (public.app_role()='above_property') with check (public.app_role()='above_property');
create policy oo_read on public.occupancy_overrides for select using (public.app_role()='above_property' or (public.app_role() in ('gm','agm') and hotel_id=public.app_hotel()));
create policy oo_write on public.occupancy_overrides for all using (public.app_role()='above_property') with check (public.app_role()='above_property');
