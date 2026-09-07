-- Vá lỗi: sau M1, bcs_student_groups.class_id NOT NULL nhưng bcs_admin_set_student_group
-- chưa từng gán class_id khi insert -> gán Tổ cho học sinh MỚI (chưa từng được gán trước đó)
-- báo lỗi "Lỗi khi lưu, thử lại." (insert vi phạm NOT NULL). Học sinh đã có sẵn dòng cũ (update
-- qua on conflict) thì không lỗi, nên bug chỉ lộ ra khi gán Tổ cho học sinh chưa gán bao giờ.
-- Đồng thời lọc theo class_id cho bcs_admin_get_student_groups (còn thiếu theo checklist M7).

create or replace function bcs_admin_set_student_group(p_admin_password text, p_student_name text, p_group_no smallint)
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
  if p_group_no is null then
    delete from bcs_student_groups where student_name = trim(p_student_name) and class_id = v_class_id;
  else
    insert into bcs_student_groups(student_name, group_no, updated_at, class_id)
    values (trim(p_student_name), p_group_no, now(), v_class_id)
    on conflict (student_name) do update set group_no = excluded.group_no, updated_at = now(), class_id = excluded.class_id;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_student_group(text, text, smallint) to anon, authenticated;

create or replace function bcs_admin_get_student_groups(p_admin_password text)
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
  return jsonb_build_object('ok', true, 'groups', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_student_groups t where t.class_id = v_class_id
  ));
end;
$$;
grant execute on function bcs_admin_get_student_groups(text) to anon, authenticated;
