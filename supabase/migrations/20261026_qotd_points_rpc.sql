-- QOTD: GM-editable point values (daily/weekly answer + correct) stored in points_rules
create or replace function public.qotd_get_points(p_hotel text) returns table(reason text, points int)
language sql stable security definer set search_path=public,private as $$
  select r.reason, r.points from points_rules r where r.hotel_id=p_hotel
    and r.reason in ('qotd_answer','qotd_correct','qotd_answer_week','qotd_correct_week') $$;
create or replace function public.qotd_set_points(p_hotel text, p_reason text, p_points int) returns void
language plpgsql security definer set search_path=public,private as $$
begin
  if not (private.is_above() or private.is_mgr_of(p_hotel)) then raise exception 'not allowed'; end if;
  if p_reason not in ('qotd_answer','qotd_correct','qotd_answer_week','qotd_correct_week') then raise exception 'bad reason'; end if;
  if p_points is null or p_points<0 or p_points>500 then raise exception 'points must be 0-500'; end if;
  update points_rules set points=p_points, updated_by=auth.uid(), updated_at=now() where hotel_id=p_hotel and reason=p_reason;
  if not found then raise exception 'rule missing'; end if;
end $$;
revoke execute on function public.qotd_get_points(text), public.qotd_set_points(text,text,int) from anon;
grant execute on function public.qotd_get_points(text), public.qotd_set_points(text,text,int) to authenticated;
