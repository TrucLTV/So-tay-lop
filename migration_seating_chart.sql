-- Sơ đồ lớp: 4 dãy x 6 bàn đôi = 48 chỗ (seat_index 0..47), kéo-thả đổi chỗ, dùng chung cho cả lớp.
create table if not exists bcs_seating (
  seat_index int primary key,
  student_name text,
  updated_at timestamptz not null default now()
);

create or replace function bcs_get_seating(p_password text)
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
  return jsonb_build_object('ok', true, 'seats', (
    select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb) from bcs_seating t
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
  select * into r from bcs_roles where password = p_password and active = true limit 1;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;
  insert into bcs_seating(seat_index, student_name, updated_at)
  values (p_seat_index, nullif(trim(p_student_name),''), now())
  on conflict (seat_index) do update set student_name = excluded.student_name, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_set_seat(text, int, text) to anon, authenticated;
