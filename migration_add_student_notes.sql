-- 1) bcs_list_notes: ẩn hẳn ghi chú riêng cho từng học sinh (kind = nhan_xet_ca_nhan) khỏi mọi ban cán sự
create or replace function bcs_list_notes(p_password text, p_start timestamptz default null, p_end timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
begin
  select * into r from bcs_roles where password = p_password and active = true limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  return jsonb_build_object('ok', true, 'notes', (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
    from bcs_notes t
    where coalesce(t.kind,'vi_pham') <> 'nhan_xet_ca_nhan'
      and (p_start is null or t.created_at >= p_start)
      and (p_end is null or t.created_at <= p_end)
  ));
end;
$$;
grant execute on function bcs_list_notes(text, timestamptz, timestamptz) to anon, authenticated;

-- 2) GV ghi nhận xét riêng cho 1 học sinh cụ thể (chỉ GV xem)
create or replace function bcs_admin_submit_student_note(p_admin_password text, p_student_name text, p_content text)
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
  if length(trim(coalesce(p_student_name,''))) = 0 then
    return jsonb_build_object('ok', false, 'error', 'missing_student');
  end if;
  select id into gv_id from bcs_roles where name = 'Giáo viên (hệ thống)' limit 1;
  insert into bcs_notes(role_id, role_name, category, student_name, content, kind)
  values (gv_id, 'Giáo viên', trim(p_student_name), trim(p_student_name), trim(p_content), 'nhan_xet_ca_nhan')
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_admin_submit_student_note(text, text, text) to anon, authenticated;

-- 3) GV xem lại các nhận xét riêng đã ghi cho 1 học sinh
create or replace function bcs_admin_get_student_notes(p_admin_password text, p_student_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'notes', (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
    from bcs_notes t
    where t.kind = 'nhan_xet_ca_nhan' and t.student_name = p_student_name
  ));
end;
$$;
grant execute on function bcs_admin_get_student_notes(text, text) to anon, authenticated;
