-- M1: Thêm khái niệm "lớp" (bcs_classes) và class_id vào mọi bảng, gán dữ liệu hiện có vào lớp "8A9".
-- Chỉ thêm cấu trúc, KHÔNG đổi hàm RPC nào ở bước này -> app đang chạy không bị ảnh hưởng.

create table if not exists bcs_classes (
  id uuid primary key default gen_random_uuid(),
  class_name text not null,
  admin_password text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table bcs_roles add column if not exists class_id uuid references bcs_classes(id);
alter table bcs_notes add column if not exists class_id uuid references bcs_classes(id);
alter table bcs_seating add column if not exists class_id uuid references bcs_classes(id);
alter table bcs_seating_rules add column if not exists class_id uuid references bcs_classes(id);
alter table bcs_student_groups add column if not exists class_id uuid references bcs_classes(id);

-- Backfill: tạo lớp "8A9" từ mật khẩu quản trị hiện có trong bcs_admin, gán mọi dòng dữ liệu cũ vào lớp này.
do $$
declare v_class_id uuid;
declare v_admin_pw text;
begin
  if exists (select 1 from bcs_classes where class_name = '8A9') then
    raise notice 'Lớp 8A9 đã tồn tại, bỏ qua backfill.';
    return;
  end if;

  select password into v_admin_pw from bcs_admin limit 1;
  insert into bcs_classes(class_name, admin_password)
  values ('8A9', coalesce(v_admin_pw, 'CHANGE_ME'))
  returning id into v_class_id;

  update bcs_roles set class_id = v_class_id where class_id is null;
  update bcs_notes set class_id = v_class_id where class_id is null;
  update bcs_seating set class_id = v_class_id where class_id is null;
  update bcs_seating_rules set class_id = v_class_id where class_id is null;
  update bcs_student_groups set class_id = v_class_id where class_id is null;
end $$;

-- Kiểm tra nhanh sau khi chạy: mọi dòng phải có class_id (kết quả các câu dưới đây phải là 0)
select count(*) as roles_missing_class from bcs_roles where class_id is null;
select count(*) as notes_missing_class from bcs_notes where class_id is null;
select count(*) as seating_missing_class from bcs_seating where class_id is null;

-- Đặt NOT NULL sau khi đã chắc chắn mọi dòng có class_id (chỉ chạy nếu 3 câu SELECT trên đều ra 0)
alter table bcs_roles alter column class_id set not null;
alter table bcs_notes alter column class_id set not null;
alter table bcs_seating alter column class_id set not null;
alter table bcs_seating_rules alter column class_id set not null;
alter table bcs_student_groups alter column class_id set not null;
