-- Cho phép GV (admin) xem/sửa sơ đồ lớp bằng mật khẩu quản trị (không phải mật khẩu ban cán sự)
create or replace function bcs_admin_get_seating(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'seats', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_seating t
  ));
end;
$$;
grant execute on function bcs_admin_get_seating(text) to anon, authenticated;

create or replace function bcs_admin_set_seat(p_admin_password text, p_seat_index int, p_student_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  insert into bcs_seating(seat_index, student_name, updated_at)
  values (p_seat_index, nullif(trim(p_student_name),''), now())
  on conflict (seat_index) do update set student_name = excluded.student_name, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_seat(text, int, text) to anon, authenticated;
