-- Cho phép "Nhận xét cho ban cán sự" gắn kèm tên học sinh (khi GV đang chọn 1 học sinh trong lưới thống kê)
create or replace function bcs_admin_submit_remark(p_admin_password text, p_category text, p_content text, p_student_name text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare gv_id uuid;
declare n bcs_notes%rowtype;
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if length(trim(coalesce(p_content,''))) = 0 then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;
  select id into gv_id from bcs_roles where name = 'Giáo viên (hệ thống)' limit 1;
  insert into bcs_notes(role_id, role_name, category, student_name, content, kind)
  values (gv_id, 'Giáo viên', coalesce(p_category,''), nullif(trim(p_student_name),''), trim(p_content), 'nhan_xet_gv')
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_admin_submit_remark(text, text, text, text) to anon, authenticated;
