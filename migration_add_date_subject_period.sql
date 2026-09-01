-- Thêm ngày / môn / tiết vào ghi chú, và cho phép nội dung ghi chú để trống (không bắt buộc).

alter table bcs_notes
  add column if not exists occur_date date,
  add column if not exists subject text,
  add column if not exists period smallint;

-- bcs_list_notes và bcs_admin_get_notes dùng to_jsonb(t) trên cả dòng nên tự động
-- trả về 3 cột mới này, không cần sửa 2 hàm đó.

drop function if exists bcs_submit_note(text, text, text, text);
create or replace function bcs_submit_note(
  p_password text, p_category text, p_student_name text, p_content text,
  p_date date default null, p_subject text default null, p_period smallint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare n bcs_notes%rowtype;
begin
  select * into r from bcs_roles where password = p_password and active = true limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  insert into bcs_notes(role_id, role_name, category, student_name, content, occur_date, subject, period)
  values (r.id, r.name, coalesce(p_category,''), nullif(trim(p_student_name),''), nullif(trim(coalesce(p_content,'')),''), p_date, p_subject, p_period)
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_submit_note(text, text, text, text, date, text, smallint) to anon, authenticated;

drop function if exists bcs_update_note(text, uuid, text, text, text);
create or replace function bcs_update_note(
  p_password text, p_id uuid, p_category text, p_student_name text, p_content text,
  p_date date default null, p_subject text default null, p_period smallint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare n bcs_notes%rowtype;
begin
  select * into r from bcs_roles where password = p_password and active = true limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  update bcs_notes
    set category = coalesce(p_category, category),
        student_name = nullif(trim(p_student_name),''),
        content = nullif(trim(coalesce(p_content,'')),''),
        occur_date = p_date,
        subject = p_subject,
        period = p_period
  where id = p_id and role_id = r.id
  returning * into n;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found_or_forbidden');
  end if;
  return jsonb_build_object('ok', true, 'id', n.id);
end;
$$;
grant execute on function bcs_update_note(text, uuid, text, text, text, date, text, smallint) to anon, authenticated;
