-- Danh sách học sinh các lớp bộ môn (không phải lớp chủ nhiệm).
-- CHỈ tạo bảng + RPC ở đây (không chứa tên học sinh thật) vì repo này là public trên GitHub —
-- dữ liệu tên thật (400+ học sinh) được nạp riêng bằng 1 script KHÔNG commit vào git,
-- xem hướng dẫn Claude đưa kèm ngoài repo.

create table if not exists bcs_subject_class_roster (
  id uuid primary key default gen_random_uuid(),
  class_name text not null,
  seq int not null,
  student_name text not null,
  created_at timestamptz not null default now(),
  unique (class_name, seq)
);

create or replace function bcs_admin_get_subject_roster(p_admin_password text, p_class_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'names', (
    select coalesce(jsonb_agg(student_name order by seq), '[]'::jsonb)
    from bcs_subject_class_roster
    where class_name = trim(p_class_name)
  ));
end;
$$;
grant execute on function bcs_admin_get_subject_roster(text, text) to anon, authenticated;
