-- Sửa dứt điểm: dùng extensions.crypt(...) / extensions.gen_salt(...) rõ ràng ở MỌI hàm
-- (crypt/gen_salt nằm trong schema "extensions", không phải "public").
-- Gồm lại toàn bộ các hàm của M2+M3 + M2b vào 1 file duy nhất, chạy 1 lần cho chắc.

create extension if not exists pgcrypto with schema extensions;

update bcs_classes set admin_password = extensions.crypt(admin_password, extensions.gen_salt('bf'))
  where admin_password !~ '^\$2[abxy]\$';
update bcs_roles set password = extensions.crypt(password, extensions.gen_salt('bf'))
  where password !~ '^\$2[abxy]\$';

create or replace function bcs_admin_class(p_password text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  select id into v_id from bcs_classes
  where active = true and extensions.crypt(p_password, admin_password) = admin_password
  limit 1;
  return v_id;
end;
$$;
grant execute on function bcs_admin_class(text) to anon, authenticated;

create or replace function bcs_admin_login(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare c bcs_classes%rowtype;
begin
  select * into c from bcs_classes
  where active = true and extensions.crypt(p_password, admin_password) = admin_password
  limit 1;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object('ok', true, 'class_id', c.id, 'class_name', c.class_name);
end;
$$;
grant execute on function bcs_admin_login(text) to anon, authenticated;

create or replace function bcs_admin_check(p_password text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select bcs_admin_class(p_password) is not null;
$$;
grant execute on function bcs_admin_check(text) to anon, authenticated;

create or replace function bcs_login(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare cname text;
begin
  select * into r from bcs_roles
  where active = true and extensions.crypt(p_password, password) = password
  limit 1;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  select class_name into cname from bcs_classes where id = r.class_id;
  return jsonb_build_object('ok', true, 'role_id', r.id, 'role_name', r.name, 'scope', r.scope, 'class_name', cname);
end;
$$;
grant execute on function bcs_login(text) to anon, authenticated;

create or replace function bcs_admin_upsert_role(p_admin_password text, p_id uuid, p_name text, p_password text, p_scope text, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare rid uuid;
declare v_class_id uuid;
begin
  v_class_id := bcs_admin_class(p_admin_password);
  if v_class_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_id is null then
    if p_password is null or length(trim(p_password)) = 0 then
      return jsonb_build_object('ok', false, 'error', 'password_required');
    end if;
    insert into bcs_roles(name, password, scope, active, class_id)
    values (p_name, extensions.crypt(p_password, extensions.gen_salt('bf')), coalesce(p_scope,'all'), coalesce(p_active,true), v_class_id)
    returning id into rid;
  else
    if p_password is not null and length(trim(p_password)) > 0 then
      update bcs_roles set name=p_name, password=extensions.crypt(p_password, extensions.gen_salt('bf')), scope=coalesce(p_scope,'all'), active=coalesce(p_active,true)
      where id=p_id and class_id = v_class_id
      returning id into rid;
    else
      update bcs_roles set name=p_name, scope=coalesce(p_scope,'all'), active=coalesce(p_active,true)
      where id=p_id and class_id = v_class_id
      returning id into rid;
    end if;
  end if;
  return jsonb_build_object('ok', true, 'id', rid);
end;
$$;
grant execute on function bcs_admin_upsert_role(text, uuid, text, text, text, boolean) to anon, authenticated;

create or replace function bcs_admin_change_password(p_old_password text, p_new_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_class_id uuid;
begin
  v_class_id := bcs_admin_class(p_old_password);
  if v_class_id is null then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  update bcs_classes set admin_password = extensions.crypt(p_new_password, extensions.gen_salt('bf')) where id = v_class_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_change_password(text, text) to anon, authenticated;

create or replace function bcs_admin_list_roles(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'roles', (
    select coalesce(jsonb_agg((to_jsonb(t) - 'password') order by t.name), '[]'::jsonb)
    from bcs_roles t
  ));
end;
$$;
grant execute on function bcs_admin_list_roles(text) to anon, authenticated;

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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
  select * into r from bcs_roles where active = true and extensions.crypt(p_password, password) = password limit 1;
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
