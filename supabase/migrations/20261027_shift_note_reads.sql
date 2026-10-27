-- Read receipts for Shift Notes & Handoff (DESIGN / not applied by the app yet: notes are still device-local in the demo).
-- Rules: any signed-in associate may record THEIR OWN read of a note at their hotel; only AGM, GM and Above Property (corporate)
-- may SELECT receipts. Everyone else gets no rows, so no counts either. Reads are append-only (no update/delete).
-- Assumes public.profiles(user_id uuid, name text, hotel_id text, role enum/text with 'above_property','gm','agm') as used by the QOTD migrations.

create schema if not exists private;

-- Notes table (create only if the backend does not have one yet; skip this block if it already exists).
create table if not exists public.shift_notes (
  id          uuid primary key default gen_random_uuid(),
  hotel_id    text not null,
  shift       text not null check (shift in ('AM','PM','Night Audit')),
  author_id   uuid not null references auth.users(id),
  body        text not null,
  lang        text,
  created_at  timestamptz not null default now()
);
alter table public.shift_notes enable row level security;

create or replace function private.my_hotel() returns text language sql stable security definer set search_path=public as $$
  select hotel_id from public.profiles where user_id = auth.uid() $$;

create or replace function private.can_see_receipts(p_hotel text) returns boolean language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.profiles p
    where p.user_id = auth.uid()
      and ( p.role::text = 'above_property'
         or (p.role::text in ('gm','agm') and p.hotel_id = p_hotel) ) ) $$;

drop policy if exists shift_notes_read on public.shift_notes;
create policy shift_notes_read on public.shift_notes for select
  using (hotel_id = private.my_hotel() or private.can_see_receipts(hotel_id));
drop policy if exists shift_notes_insert on public.shift_notes;
create policy shift_notes_insert on public.shift_notes for insert
  with check (author_id = auth.uid() and hotel_id = private.my_hotel());

-- Receipts
create table if not exists public.shift_note_reads (
  note_id  uuid not null references public.shift_notes(id) on delete cascade,
  user_id  uuid not null references auth.users(id) on delete cascade,
  hotel_id text not null,
  read_at  timestamptz not null default now(),
  primary key (note_id, user_id)
);
create index if not exists shift_note_reads_hotel_idx on public.shift_note_reads (hotel_id, read_at desc);
alter table public.shift_note_reads enable row level security;

-- SELECT: AGM / GM of that hotel and corporate only.
drop policy if exists shift_note_reads_select on public.shift_note_reads;
create policy shift_note_reads_select on public.shift_note_reads for select
  using (private.can_see_receipts(hotel_id));

-- INSERT: only your own read, only for a note at your own hotel.
drop policy if exists shift_note_reads_insert on public.shift_note_reads;
create policy shift_note_reads_insert on public.shift_note_reads for insert
  with check (
    user_id = auth.uid()
    and hotel_id = private.my_hotel()
    and exists (select 1 from public.shift_notes n where n.id = note_id and n.hotel_id = hotel_id));
-- No update or delete policies: receipts are append-only.

-- Client call is `insert ... on conflict do nothing` (or this helper), so re-opening a note never errors.
create or replace function public.mark_note_read(p_note uuid) returns void language sql security invoker as $$
  insert into public.shift_note_reads(note_id, user_id, hotel_id)
  select n.id, auth.uid(), n.hotel_id from public.shift_notes n where n.id = p_note
  on conflict (note_id, user_id) do nothing $$;

-- Unread list for the GM view: staff at the hotel who have not read the note (security definer so the GM does not need profile access;
-- the function itself refuses anyone who is not AGM/GM/corporate).
create or replace function public.shift_note_unread(p_note uuid) returns table(out_user_id uuid, out_name text)
language plpgsql stable security definer set search_path=public,private as $$
declare h text;
begin
  select hotel_id into h from public.shift_notes where id = p_note;
  if h is null or not private.can_see_receipts(h) then return; end if;
  return query
    select p.user_id, p.name from public.profiles p
    where p.hotel_id = h and p.role::text <> 'above_property'
      and not exists (select 1 from public.shift_note_reads r where r.note_id = p_note and r.user_id = p.user_id);
end $$;
revoke all on function public.shift_note_unread(uuid) from public, anon;
grant execute on function public.shift_note_unread(uuid) to authenticated;
