-- Quy tắc xếp chỗ: cặp học sinh không nên ngồi cạnh nhau + học sinh cần lưu ý đặc biệt (kèm ghi chú, chỉ GV xem)
create table if not exists bcs_seating_rules (
  id uuid primary key default gen_random_uuid(),
  rule_type text not null check (rule_type in ('avoid','special')),
  student_a text not null,
  student_b text,
  note text,
  created_at timestamptz not null default now()
);

create or replace function bcs_admin_get_seating_rules(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  return jsonb_build_object('ok', true, 'rules', (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.created_at), '[]'::jsonb) from bcs_seating_rules t
  ));
end;
$$;
grant execute on function bcs_admin_get_seating_rules(text) to anon, authenticated;

create or replace function bcs_admin_add_avoid_pair(p_admin_password text, p_student_a text, p_student_b text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n bcs_seating_rules%rowtype;
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  if p_student_a is null or p_student_b is null or trim(p_student_a) = '' or trim(p_student_b) = '' or trim(p_student_a) = trim(p_student_b) then
    return jsonb_build_object('ok', false, 'error', 'invalid_pair');
  end if;
  insert into bcs_seating_rules(rule_type, student_a, student_b)
  values ('avoid', trim(p_student_a), trim(p_student_b))
  returning * into n;
  return jsonb_build_object('ok', true, 'id', n.id);
end;
$$;
grant execute on function bcs_admin_add_avoid_pair(text, text, text) to anon, authenticated;

create or replace function bcs_admin_set_special_note(p_admin_password text, p_student_name text, p_note text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare n bcs_seating_rules%rowtype;
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  delete from bcs_seating_rules where rule_type = 'special' and student_a = trim(p_student_name);
  if p_note is not null and length(trim(p_note)) > 0 then
    insert into bcs_seating_rules(rule_type, student_a, note)
    values ('special', trim(p_student_name), trim(p_note))
    returning * into n;
  end if;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_set_special_note(text, text, text) to anon, authenticated;

create or replace function bcs_admin_delete_seating_rule(p_admin_password text, p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  delete from bcs_seating_rules where id = p_id;
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_admin_delete_seating_rule(text, uuid) to anon, authenticated;
