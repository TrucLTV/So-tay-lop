-- Reset toàn bộ Thông báo / Vi phạm / Khen thưởng / Nhận xét của GV (cả trang ban cán sự lẫn trang GV).
-- Hồ sơ riêng từng học sinh (kind = nhan_xet_ca_nhan) KHÔNG bị xoá, giữ suốt năm học.
create or replace function bcs_admin_reset_notes(p_admin_password text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare del_count int;
begin
  if not bcs_admin_check(p_admin_password) then
    return jsonb_build_object('ok', false, 'error', 'unauthorized');
  end if;
  delete from bcs_notes where coalesce(kind,'vi_pham') <> 'nhan_xet_ca_nhan';
  get diagnostics del_count = row_count;
  return jsonb_build_object('ok', true, 'deleted', del_count);
end;
$$;
grant execute on function bcs_admin_reset_notes(text) to anon, authenticated;
