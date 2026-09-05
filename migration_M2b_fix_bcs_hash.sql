-- Vá gấp: các hàm phía ban cán sự (không phải quản trị) vẫn so mật khẩu dạng chữ thường
-- (where password = p_password) trong khi mật khẩu đã được hash ở bước M2+M3 -> đang bị hỏng.
-- Sửa lại dùng crypt() giống bcs_login.

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
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  k := coalesce(p_kind, 'vi_pham');
  if k not in ('vi_pham','khen_thuong','thong_bao','bao_bai') then
    return jsonb_build_object('ok', false, 'error', 'forbidden_kind');
  end if;
  insert into bcs_notes(role_id, role_name, category, student_name, content, occur_date, subject, period, kind, class_id)
  values (r.id, r.name, coalesce(p_category,''), nullif(trim(p_student_name),''), nullif(trim(coalesce(p_content,'')),''), p_date, p_subject, p_period, k, r.class_id)
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
    insert into bcs_notes(role_id, role_name, category, student_name, content, kind, class_id)
    values (r.id, r.name, student, student, archive_text, 'nhan_xet_ca_nhan', r.class_id);
  end if;

  return jsonb_build_object('ok', true, 'id', n.id, 'created_at', n.created_at);
end;
$$;
grant execute on function bcs_submit_note(text, text, text, text, date, text, smallint, text) to anon, authenticated;

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
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
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

create or replace function bcs_delete_note(p_password text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare del_count int;
begin
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  delete from bcs_notes where id = p_id and role_id = r.id;
  get diagnostics del_count = row_count;
  if del_count = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found_or_forbidden');
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_delete_note(text, uuid) to anon, authenticated;

create or replace function bcs_list_notes(p_password text, p_start timestamptz default null, p_end timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
begin
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  return jsonb_build_object('ok', true, 'notes', (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at desc), '[]'::jsonb)
    from bcs_notes t
    where coalesce(t.kind,'vi_pham') <> 'nhan_xet_ca_nhan'
      and t.class_id = r.class_id
      and (p_start is null or t.created_at >= p_start)
      and (p_end is null or t.created_at <= p_end)
  ));
end;
$$;
grant execute on function bcs_list_notes(text, timestamptz, timestamptz) to anon, authenticated;

create or replace function bcs_get_seating(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
begin
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  return jsonb_build_object('ok', true, 'seats', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_seating t where t.class_id = r.class_id
  ));
end;
$$;
grant execute on function bcs_get_seating(text) to anon, authenticated;

create or replace function bcs_set_seat(p_password text, p_seat_index int, p_student_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
begin
  select * into r from bcs_roles where active = true and crypt(p_password, password) = password limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  insert into bcs_seating(seat_index, student_name, updated_at, class_id)
  values (p_seat_index, nullif(trim(p_student_name),''), now(), r.class_id)
  on conflict (seat_index) do update set student_name = excluded.student_name, updated_at = now(), class_id = excluded.class_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_set_seat(text, int, text) to anon, authenticated;
