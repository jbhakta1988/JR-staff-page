-- QOTD: "needs GM confirm" questions. Stored inactive; GM/AGM of that hotel (or above-property) fills in/approves, which activates them.
alter table public.qotd_questions add column if not exists needs_confirm boolean not null default false;
alter table public.qotd_questions add column if not exists confirm_note text;
alter table public.qotd_questions add column if not exists confirmed_by uuid;
alter table public.qotd_questions add column if not exists confirmed_at timestamptz;
create or replace function public.qotd_pending(p_hotel text) returns setof public.qotd_questions
language sql stable security definer set search_path=public,private as $$
  select * from qotd_questions where needs_confirm and hotel_id=p_hotel and (private.is_above() or private.is_mgr_of(p_hotel)) order by topic, id $$;
create or replace function public.qotd_confirm(p_id bigint, p jsonb) returns void
language plpgsql security definer set search_path=public,private as $$
declare q qotd_questions; oe jsonb; os jsonb; c int;
begin
  select * into q from qotd_questions where id=p_id and needs_confirm;
  if not found then raise exception 'not pending'; end if;
  if not (private.is_above() or private.is_mgr_of(q.hotel_id)) then raise exception 'not allowed'; end if;
  oe:=coalesce(p->'options_en',q.options_en); os:=coalesce(p->'options_es',q.options_es); c:=coalesce((p->>'correct_idx')::int,q.correct_idx);
  if jsonb_array_length(oe) not between 3 and 4 or jsonb_array_length(os)<>jsonb_array_length(oe) or c<0 or c>=jsonb_array_length(oe) then raise exception '3-4 options, EN and ES must match'; end if;
  if (oe::text||os::text) ~ '\[GM' then raise exception 'fill in every [GM ...] blank first'; end if;
  update qotd_questions set options_en=oe, options_es=os, correct_idx=c,
    explain_en=coalesce(nullif(p->>'explain_en',''),explain_en), explain_es=coalesce(nullif(p->>'explain_es',''),explain_es),
    needs_confirm=false, active=true, confirmed_by=auth.uid(), confirmed_at=now(), updated_by=auth.uid(), updated_at=now(),
    review_by=coalesce(review_by,(current_date+182)) where id=p_id;
end $$;
revoke execute on function public.qotd_pending(text), public.qotd_confirm(bigint,jsonb) from anon;
grant execute on function public.qotd_pending(text), public.qotd_confirm(bigint,jsonb) to authenticated;
