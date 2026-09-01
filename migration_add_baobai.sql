-- Cho phép thêm loại "bao_bai" (Viết báo bài) vào bcs_submit_note
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
  if k not in ('vi_pham','khen_thuong','thong_bao','bao_bai') then
    return jsonb_build_object('ok', false, 'error', 'forbidden_kind');
  end if;
  insert into bcs_notes(role_id, role_name, category, student_name, content, occur_date, subject, period, kind)
  values (r.id, r.name, coalesce(p_category,''), nullif(trim(p_student_name),''), nullif(trim(coalesce(p_content,'')),''), p_date, p_subject, p_period, k)
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_submit_note(text, text, text, text, date, text, smallint, text) to anon, authenticated;
