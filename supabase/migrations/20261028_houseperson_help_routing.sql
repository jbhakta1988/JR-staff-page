-- Houseperson help (formerly Line Staff) alerts both the house person and the shuttle driver
-- at the hotel. Older saved ids stay valid and resolve to the same route.
-- The demo app keeps the same map in the client (canonReq / hpHelpRoles) and fans
-- in-app alerts plus one notifications row per role when Supabase is on.
-- Do not edit earlier migrations; this file only adds the route table.

create table if not exists public.staff_request_routes (
  kind text primary key,
  canonical text not null,
  notify_roles text[] not null,
  label_en text not null,
  label_es text not null
);

alter table public.staff_request_routes enable row level security;

drop policy if exists staff_request_routes_read on public.staff_request_routes;
create policy staff_request_routes_read on public.staff_request_routes
  for select to authenticated using ((select auth.uid()) is not null);

insert into public.staff_request_routes (kind, canonical, notify_roles, label_en, label_es) values
  ('houseperson_help', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('House Person', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('Line Staff', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('Line staff', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('line staff', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('lineStaff', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('line_staff', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('personal de línea', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('personal de linea', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson'),
  ('Pedir personal de línea', 'houseperson_help', array['house_person','shuttle_driver'], 'Houseperson help', 'Ayuda de houseperson')
on conflict (kind) do update set
  canonical = excluded.canonical,
  notify_roles = excluded.notify_roles,
  label_en = excluded.label_en,
  label_es = excluded.label_es;

create or replace function public.staff_request_notify_roles(p_kind text)
returns text[]
language sql
stable
security invoker
set search_path = ''
as $$
  select r.notify_roles
  from public.staff_request_routes r
  where r.kind = p_kind
  limit 1
$$;

revoke all on function public.staff_request_notify_roles(text) from public, anon;
grant execute on function public.staff_request_notify_roles(text) to authenticated;
