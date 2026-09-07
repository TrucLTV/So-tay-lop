-- GVBM (Giáo viên bộ môn): tên GV + số điện thoại liên hệ theo từng môn, cho GV chủ nhiệm quản trị.
-- Có class_id ngay từ đầu (NOT NULL) để tránh lặp lại lỗi thiếu class_id đã gặp ở bcs_student_groups/bcs_seating.

create table if not exists bcs_gvbm (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references bcs_classes(id),
  subject text not null,
  teacher_name text,
  phone text,
  updated_at timestamptz not null default now(),
  unique (class_id, subject)
);

create or replace function bcs_admin_get_gvbm(p_admin_password text)
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
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_gvbm t where t.class_id = v_class_id
  ));
end;
$$;
grant execute on function bcs_admin_get_gvbm(text) to anon, authenticated;

create or replace function bcs_admin_set_gvbm(p_admin_password text, p_subject text, p_teacher_name text, p_phone text)
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
  insert into bcs_gvbm(class_id, subject, teacher_name, phone, updated_at)
  values (v_class_id, trim(p_subject), nullif(trim(coalesce(p_teacher_name,'')),''), nullif(trim(coalesce(p_phone,'')),''), now())
  on conflict (class_id, subject) do update
    set teacher_name = excluded.teacher_name, phone = excluded.phone, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_gvbm(text, text, text, text) to anon, authenticated;
