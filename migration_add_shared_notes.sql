-- Cho phép mọi ban cán sự (bất kỳ role đang active) xem TOÀN BỘ ghi chú (cả 4 mục),
-- và tự sửa / xoá ghi chú CỦA CHÍNH MÌNH (so theo role_id suy ra từ mật khẩu).
-- Theo đúng khuôn mẫu bảo mật các hàm bcs_* hiện có: SECURITY DEFINER, tự tra role qua mật khẩu.

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
    where (p_start is null or t.created_at >= p_start)
      and (p_end is null or t.created_at <= p_end)
  ));
end;
$$;

create or replace function bcs_update_note(p_password text, p_id uuid, p_category text, p_student_name text, p_content text)
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
  if length(trim(coalesce(p_content,''))) = 0 then
    return jsonb_build_object('ok', false, 'error', 'empty_content');
  end if;
  update bcs_notes
    set category = coalesce(p_category, category),
        student_name = nullif(trim(p_student_name),''),
        content = trim(p_content)
  where id = p_id and role_id = r.id
  returning * into n;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found_or_forbidden');
  end if;
  return jsonb_build_object('ok', true, 'id', n.id);
end;
$$;

create or replace function bcs_delete_note(p_password text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare r bcs_roles%rowtype;
declare del_count int;
begin
  select * into r from bcs_roles where password = p_password and active = true limit 1;
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

grant execute on function bcs_list_notes(text, timestamptz, timestamptz) to anon, authenticated;
grant execute on function bcs_update_note(text, uuid, text, text, text) to anon, authenticated;
grant execute on function bcs_delete_note(text, uuid) to anon, authenticated;
