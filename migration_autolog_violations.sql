-- Mỗi khi ban cán sự ghi 1 "Vi phạm" có gắn tên học sinh, tự động lưu thêm 1 bản ghi
-- vào hồ sơ riêng của học sinh đó (kind = nhan_xet_ca_nhan) — không bị xoá khi Reset.
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
declare student text;
declare archive_text text;
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

  student := nullif(trim(p_student_name),'');
  if k = 'vi_pham' and student is not null then
    archive_text := 'Vi phạm: ' || coalesce(p_category,'');
    if p_content is not null and length(trim(p_content)) > 0 then
      archive_text := archive_text || E'\nGhi chú: ' || trim(p_content);
    end if;
    if p_date is not null then
      archive_text := archive_text || E'\nNgày: ' || to_char(p_date,'DD/MM/YYYY');
    end if;
    if p_subject is not null and length(trim(p_subject)) > 0 then
      archive_text := archive_text || ' · Môn: ' || p_subject;
    end if;
    if p_period is not null then
      archive_text := archive_text || ' · Tiết ' || p_period;
    end if;
    insert into bcs_notes(role_id, role_name, category, student_name, content, kind)
    values (r.id, r.name, student, student, archive_text, 'nhan_xet_ca_nhan');
  end if;

  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_submit_note(text, text, text, text, date, text, smallint, text) to anon, authenticated;
