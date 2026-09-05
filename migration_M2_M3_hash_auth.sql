-- M2 + M3 (gộp): hash mật khẩu bằng bcrypt (pgcrypto) + cập nhật đăng nhập/xác thực cho phù hợp.
-- Chỉ sửa 4 hàm: bcs_login, bcs_admin_check, bcs_admin_upsert_role, bcs_admin_change_password.
-- Các hàm admin khác không cần sửa vì chỉ gọi bcs_admin_check (giữ nguyên tên + kiểu trả về boolean).

create extension if not exists pgcrypto;

-- Hash mật khẩu hiện có (an toàn để chạy lại nhiều lần: bỏ qua giá trị đã hash rồi)
update bcs_classes set admin_password = crypt(admin_password, gen_salt('bf'))
  where admin_password !~ '^\$2[abxy]\$';
update bcs_roles set password = crypt(password, gen_salt('bf'))
  where password !~ '^\$2[abxy]\$';

-- Hàm lõi: từ mật khẩu quản trị -> tìm đúng lớp (class_id), null nếu sai mật khẩu
create or replace function bcs_admin_class(p_password text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  select id into v_id from bcs_classes
  where active = true and crypt(p_password, admin_password) = admin_password
  limit 1;
  return v_id;
end;
$$;
grant execute on function bcs_admin_class(text) to anon, authenticated;

-- Dùng khi đăng nhập quản trị: trả về tên lớp để hiển thị (chuẩn bị cho bước sau)
create or replace function bcs_admin_login(p_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare c bcs_classes%rowtype;
begin
  select * into c from bcs_classes
  where active = true and crypt(p_password, admin_password) = admin_password
  limit 1;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  return jsonb_build_object('ok', true, 'class_id', c.id, 'class_name', c.class_name);
end;
$$;
grant execute on function bcs_admin_login(text) to anon, authenticated;

-- Giữ nguyên tên + kiểu trả về boolean để mọi hàm admin khác không cần sửa
create or replace function bcs_admin_check(p_password text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select bcs_admin_class(p_password) is not null;
$$;
grant execute on function bcs_admin_check(text) to anon, authenticated;

-- Đăng nhập ban cán sự: kiểm tra hash, trả thêm class_name
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
  where active = true and crypt(p_password, password) = password
  limit 1;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  select class_name into cname from bcs_classes where id = r.class_id;
  return jsonb_build_object('ok', true, 'role_id', r.id, 'role_name', r.name, 'scope', r.scope, 'class_name', cname);
end;
$$;
grant execute on function bcs_login(text) to anon, authenticated;

-- Thêm/sửa vai trò: hash mật khẩu khi ghi. Khi SỬA, để trống p_password = giữ nguyên mật khẩu cũ.
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
    values (p_name, crypt(p_password, gen_salt('bf')), coalesce(p_scope,'all'), coalesce(p_active,true), v_class_id)
    returning id into rid;
  else
    if p_password is not null and length(trim(p_password)) > 0 then
      update bcs_roles set name=p_name, password=crypt(p_password, gen_salt('bf')), scope=coalesce(p_scope,'all'), active=coalesce(p_active,true)
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

-- Đổi mật khẩu quản trị: giờ cập nhật bcs_classes.admin_password (không dùng bảng bcs_admin cũ nữa)
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
  update bcs_classes set admin_password = crypt(p_new_password, gen_salt('bf')) where id = v_class_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_change_password(text, text) to anon, authenticated;

-- Danh sách vai trò: không trả mật khẩu về nữa (đã hash, hiện ra cũng vô nghĩa)
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
