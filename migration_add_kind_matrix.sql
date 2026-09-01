-- Thêm "loại nội dung" (kind) cho mỗi ghi chú: vi_pham (đang có) / khen_thuong / thong_bao / nhan_xet_gv
alter table bcs_notes add column if not exists kind text not null default 'vi_pham';

-- Vai trò hệ thống đại diện cho GV khi ghi "Nhận xét của GV" (active=false nên không thể dùng để đăng nhập)
insert into bcs_roles(name, password, scope, active)
select 'Giáo viên (hệ thống)', md5(random()::text || clock_timestamp()::text), 'all', false
where not exists (select 1 from bcs_roles where name = 'Giáo viên (hệ thống)');

-- bcs_submit_note: thêm p_kind, ban cán sự chỉ được dùng vi_pham/khen_thuong/thong_bao
drop function if exists bcs_submit_note(text, text, text, text, date, text, smallint);
create or replace function bcs_submit_note(
  p_password text, p_category text, p_student_name text, p_content text,
  p_date date default null, p_subject text default null, p_period smallint default null,
  p_kind text default 'vi_pham'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare n bcs_notes%rowtype;
declare k text;
begin
  select * into r from bcs_roles where password = p_password and active = true limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  k := coalesce(p_kind, 'vi_pham');
  if k not in ('vi_pham','khen_thuong','thong_bao') then
    return jsonb_build_object('ok', false, 'error', 'forbidden_kind');
  end if;
  insert into bcs_notes(role_id, role_name, category, student_name, content, occur_date, subject, period, kind)
  values (r.id, r.name, coalesce(p_category,''), nullif(trim(p_student_name),''), nullif(trim(coalesce(p_content,'')),''), p_date, p_subject, p_period, k)
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_submit_note(text, text, text, text, date, text, smallint, text) to anon, authenticated;

-- Hàm mới: chỉ GV (admin) dùng để ghi "Nhận xét của GV" theo từng mục
create or replace function bcs_admin_submit_remark(p_admin_password text, p_category text, p_content text)
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
  insert into bcs_notes(role_id, role_name, category, content, kind)
  values (gv_id, 'Giáo viên', coalesce(p_category,''), trim(p_content), 'nhan_xet_gv')
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_admin_submit_remark(text, text, text) to anon, authenticated;
