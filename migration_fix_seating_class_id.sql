-- Cùng lỗi như bcs_admin_set_student_group (xem migration_fix_student_groups_class_id.sql):
-- bcs_seating.class_id NOT NULL (từ M1) nhưng bcs_admin_set_seat chưa gán class_id khi insert.
-- Ghế đã có sẵn dòng trong CSDL thì update vẫn chạy được (không đụng class_id), nhưng ghế
-- CHƯA từng có ai ngồi (chưa từng insert) sẽ báo lỗi khi xếp vào lần đầu — ví dụ khi dùng
-- tính năng "Tự động xếp theo Tổ" ghi vào những chỗ trống chưa từng dùng.

create or replace function bcs_admin_get_seating(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_class_id uuid;
begin
  v_class_id := bcs_admin_class(p_admin_password);
  if v_class_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'seats', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_seating t where t.class_id = v_class_id
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
declare v_class_id uuid;
begin
  v_class_id := bcs_admin_class(p_admin_password);
  if v_class_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  insert into bcs_seating(seat_index, student_name, updated_at, class_id)
  values (p_seat_index, nullif(trim(p_student_name),''), now(), v_class_id)
  on conflict (seat_index) do update set student_name = excluded.student_name, updated_at = now(), class_id = excluded.class_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_seat(text, int, text) to anon, authenticated;
