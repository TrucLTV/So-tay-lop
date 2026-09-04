-- Gán tổ (1-4) cho từng học sinh, dùng để cảnh báo khi xếp lệch dãy so với tổ.
create table if not exists bcs_student_groups (
  student_name text primary key,
  group_no smallint not null check (group_no between 1 and 4),
  updated_at timestamptz not null default now()
);

create or replace function bcs_admin_get_student_groups(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'groups', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_student_groups t
  ));
end;
$$;
grant execute on function bcs_admin_get_student_groups(text) to anon, authenticated;

create or replace function bcs_admin_set_student_group(p_admin_password text, p_student_name text, p_group_no smallint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_group_no is null then
    delete from bcs_student_groups where student_name = trim(p_student_name);
  else
    insert into bcs_student_groups(student_name, group_no, updated_at)
    values (trim(p_student_name), p_group_no, now())
    on conflict (student_name) do update set group_no = excluded.group_no, updated_at = now();
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_student_group(text, text, smallint) to anon, authenticated;
