-- Trực lớp: mỗi ngày gán 2 học sinh trực, nhận xét Đạt/Chưa đạt, ghi chú.
-- Mở cho mọi ban cán sự đang đăng nhập (giống quyền Sơ đồ lớp bên BCS — không giới hạn theo scope).

create table if not exists bcs_class_duty (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references bcs_classes(id),
  duty_date date not null,
  student1 text,
  student2 text,
  rating text check (rating in ('dat','chua_dat')),
  note text,
  updated_at timestamptz not null default now(),
  unique (class_id, duty_date)
);
alter table bcs_class_duty enable row level security;
-- Không tạo policy nào — bảng chỉ truy cập được qua RPC security definer bên dưới,
-- giống mọi bảng bcs_* khác trong dự án này.

create or replace function bcs_list_class_duty(p_password text, p_start date default null, p_end date default null)
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
  return jsonb_build_object('ok', true, 'rows', (
    select coalesce(jsonb_agg(to_jsonb(t) order by t.duty_date desc), '[]'::jsonb)
    from bcs_class_duty t
    where t.class_id = r.class_id
      and (p_start is null or t.duty_date >= p_start)
      and (p_end is null or t.duty_date <= p_end)
  ));
end;
$$;
grant execute on function bcs_list_class_duty(text, date, date) to anon, authenticated;

create or replace function bcs_set_class_duty(p_password text, p_date date, p_student1 text, p_student2 text, p_rating text, p_note text)
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
  if p_rating is not null and p_rating not in ('dat','chua_dat') then
    return jsonb_build_object('ok', false, 'error', 'invalid_rating');
  end if;
  insert into bcs_class_duty(class_id, duty_date, student1, student2, rating, note, updated_at)
  values (r.class_id, p_date, nullif(trim(coalesce(p_student1,'')),''), nullif(trim(coalesce(p_student2,'')),''), p_rating, nullif(trim(coalesce(p_note,'')),''), now())
  on conflict (class_id, duty_date) do update
    set student1 = excluded.student1, student2 = excluded.student2, rating = excluded.rating, note = excluded.note, updated_at = now();
  return jsonb_build_object('ok', true);
end;
$$;
grant execute on function bcs_set_class_duty(text, date, text, text, text, text) to anon, authenticated;

create or replace function bcs_delete_class_duty(p_password text, p_date date)
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
  delete from bcs_class_duty where class_id = r.class_id and duty_date = p_date;
  get diagnostics del_count = row_count;
  return jsonb_build_object('ok', true, 'deleted', del_count);
end;
$$;
grant execute on function bcs_delete_class_duty(text, date) to anon, authenticated;
