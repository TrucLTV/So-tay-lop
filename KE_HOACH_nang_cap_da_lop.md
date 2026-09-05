# Kế hoạch nâng cấp "Ghi chú Ban cán sự" thành app dùng chung nhiều lớp

Dựa trên: quyết định dùng **1 hệ thống backend chung**, cho phép **GV tự đăng ký lớp**, **mỗi GV gắn với đúng 1 lớp**, mình (Truc) là người vận hành lâu dài, và **giữ nguyên dữ liệu lớp 8A9** làm lớp đầu tiên.

---

## Checklist thực hiện (tick dần khi test xong từng bước)

- [x] **M1** — Schema: bảng `bcs_classes` + cột `class_id` khắp nơi + gán dữ liệu cũ vào lớp "8A9" ✅ đã xác nhận (1 dòng "8A9", 0 dòng thiếu class_id)
- [ ] **M2** — Hash mật khẩu (pgcrypto)
- [ ] **M3** — Viết lại RPC lõi: `bcs_login`, `bcs_admin_check`
- [ ] **M4** — Viết lại RPC ghi chú: `bcs_submit_note`, `bcs_update_note`, `bcs_delete_note`, `bcs_list_notes`
- [ ] **M5** — Viết lại RPC quản lý vai trò: `bcs_admin_list_roles`, `bcs_admin_upsert_role`, `bcs_admin_delete_role`, `bcs_admin_change_password`
- [ ] **M6** — Viết lại RPC thống kê/hồ sơ: `bcs_admin_get_notes`, `bcs_admin_delete_note`, `bcs_admin_submit_remark`, `bcs_admin_get_student_notes`, `bcs_admin_submit_student_note`, `bcs_admin_reset_notes`
- [ ] **M7** — Viết lại RPC sơ đồ lớp: `bcs_get_seating`, `bcs_set_seat`, `bcs_admin_get_seating`, `bcs_admin_set_seat`, `bcs_admin_get_seating_rules`, `bcs_admin_add_avoid_pair`, `bcs_admin_set_special_note`, `bcs_admin_delete_seating_rule`, `bcs_admin_get_student_groups`, `bcs_admin_set_student_group`
- [ ] **M8** — RPC mới: `bcs_create_class`
- [ ] **M9** — Client: bỏ hard-code "Lớp 8A9" (4 chỗ), gắn động theo `class_name`
- [ ] **M10** — Client: màn "Tạo lớp mới" trên `screenLogin`
- [ ] **M11** — Kiểm tra/bật RLS trên toàn bộ bảng `bcs_*`
- [ ] **M12** — Test hồi quy: đăng nhập lại 8A9 bằng mật khẩu cũ, xác nhận dữ liệu cũ còn nguyên
- [ ] **M13** *(sau, không gấp)* — Giới hạn tốc độ tạo lớp/đăng nhập
- [ ] **M14** *(sau, không gấp)* — Trang vận hành cho Truc xem/khoá lớp

---

## 1. Vấn đề của bản hiện tại

Đọc `bcs_app/index.html` (2071 dòng) + 7 file migration SQL, thấy 3 vấn đề chặn việc dùng chung:

1. **Không có khái niệm "lớp" trong dữ liệu.** Các bảng `bcs_roles`, `bcs_notes`, `bcs_seating` không có cột `class_id`. Tất cả hàm RPC (`bcs_login`, `bcs_submit_note`, `bcs_list_notes`…) chỉ lọc theo `password`/`role_id`, không lọc theo lớp → nếu 2 lớp cùng dùng 1 backend như hiện tại, **ban cán sự lớp này sẽ thấy được toàn bộ ghi chú/chỗ ngồi của lớp khác**.
2. **Chỉ có 1 mật khẩu quản trị (GV) duy nhất cho cả hệ thống** (`bcs_admin_check`), không phải theo từng lớp.
3. **Tên lớp bị hard-code** "Lớp 8A9" ở 4 chỗ trong HTML (tiêu đề trang, nhãn app, tiêu đề báo cáo, footer) và Supabase URL/anon key gắn cứng trong file → không cấu hình được theo lớp.

Ngoài ra, mật khẩu đang lưu **dạng text thuần** trong bảng và so khớp bằng `where password = p_password` — không hash. Chấp nhận được cho 1 lớp cá nhân, nhưng khi mở cho nhiều lớp/nhiều GV thì nên vá vì đây là hệ thống ghi nhận xét/vi phạm học sinh.

---

## 2. Kiến trúc mục tiêu

**Vẫn 1 Supabase project + 1 file HTML** (không tách app riêng cho từng GV — đúng như đã chọn, để đồng nghiệp "không rành công nghệ" không phải tự setup gì).

Điểm mấu chốt: thêm **bảng `bcs_classes`** làm gốc phân vùng dữ liệu, và mọi bảng khác trỏ về `class_id`.

```
bcs_classes            (id, class_name, admin_password_hash, created_at)
bcs_roles              (id, class_id →, name, password_hash, scope, active)
bcs_notes              (id, class_id →, role_id →, ...)
bcs_seating            (id, class_id →, seat_index, student_name, ...)
bcs_seating_rules      (id, class_id →, ...)
bcs_student_groups     (id, class_id →, ...)
```

Mọi hàm RPC (`bcs_login`, `bcs_submit_note`, `bcs_admin_*`…) sửa lại để **luôn resolve ra `class_id` từ mật khẩu trước**, rồi mọi truy vấn/insert bên trong đều `where class_id = ...`. Đây là thay đổi lớn nhất về code nhưng là **bắt buộc** — không có cách nào dùng chung an toàn nếu thiếu bước này.

### Vì sao không dùng Supabase Auth (email/password thật)?
Có thể cân nhắc sau, nhưng bản chất app hiện tại dùng "mật khẩu dùng chung theo vai trò" (cả lớp trưởng, lớp phó... login bằng 1 mật khẩu) chứ không phải tài khoản cá nhân — giữ mô hình này cho đơn giản, chỉ thêm lớp là đủ để dùng chung. Nâng lên Supabase Auth là việc riêng, không cần cho mục tiêu "nhiều GV dùng" lần này.

---

## 3. GV tự đăng ký lớp — luồng cụ thể

Thêm màn hình **"Tạo lớp mới"** trên `screenLogin` (nút phụ cạnh nút Đăng nhập):

1. GV nhập: Tên lớp (vd "9A2"), Mật khẩu quản trị (GV tự đặt), Mật khẩu ban cán sự đầu tiên (ít nhất 1, có thể thêm sau trong trang quản trị).
2. Hàm RPC mới `bcs_create_class(p_class_name, p_admin_password, p_role_name, p_role_password)`:
   - Kiểm tra `p_class_name` và `p_admin_password` chưa trùng lớp nào đang hoạt động.
   - Insert vào `bcs_classes`, insert role đầu tiên vào `bcs_roles` với `class_id` vừa tạo.
   - Trả về `class_id` (hoặc thẳng luôn admin session) để GV vào thẳng trang quản trị, không cần đăng nhập lại.
3. Vì "mỗi GV chỉ 1 lớp", **không cần màn hình chọn lớp** sau đăng nhập — mật khẩu tự nó xác định đúng 1 `class_id`, giữ nguyên UX đăng nhập hiện tại (chỉ nhập mật khẩu, không cần chọn lớp/nhập tên trường).
4. Tên lớp không còn hard-code — sau khi `bcs_login`/`bcs_admin_check` trả về, JS set lại tiêu đề trang, nhãn `.tag`, tiêu đề báo cáo, footer bằng `class_name` lấy từ kết quả login (bỏ 4 chỗ hard-code "Lớp 8A9").

**Rủi ro cần lường:** vì đăng ký mở, cần chặn spam/trùng tên: nên thêm ràng buộc unique nhẹ (vd. không cho trùng cặp tên lớp) và giới hạn tốc độ (xem mục 5) để đồng nghiệp lỡ bấm tạo 2 lần không sinh ra rác.

---

## 4. Migrate dữ liệu 8A9 hiện có

Vì có bảng cũ chưa có `class_id`, migration cần làm theo đúng thứ tự (viết thành 1 file SQL, chạy 1 lần):

1. Tạo bảng `bcs_classes`, insert 1 dòng cho "8A9" (lấy `admin_password` hiện tại trong bảng roles cũ hoặc mật khẩu quản trị hiện dùng — cần bạn cung cấp/xác nhận giá trị này lúc chạy).
2. `alter table bcs_roles/bcs_notes/bcs_seating/... add column class_id uuid references bcs_classes(id)`.
3. `update ... set class_id = '<id-của-8A9>'` cho toàn bộ dòng hiện có (vì hiện tại chỉ có 1 lớp, mọi dòng đều thuộc 8A9).
4. `alter table ... alter column class_id set not null` sau khi update xong.
5. Viết lại toàn bộ hàm RPC theo mẫu ở mục 2.
6. Kiểm thử: đăng nhập lại lớp 8A9 bằng mật khẩu cũ → xác nhận thấy đúng dữ liệu cũ, không mất gì.

→ Không mất lịch sử ghi chú/chỗ ngồi/mật khẩu ban cán sự đang có.

---

## 5. Bảo mật cần vá trước khi mời người ngoài dùng

Vì giờ đây có dữ liệu **nhận xét/vi phạm của học sinh nhiều lớp trên cùng 1 hệ thống**, nên xử lý trước khi mời đồng nghiệp:

- **Hash mật khẩu** (bcrypt qua extension `pgcrypto`/`crypt()` có sẵn trong Postgres) thay vì lưu/so text thuần. Sửa `bcs_login`, `bcs_admin_check`, và hàm tạo lớp/tạo vai trò để dùng `crypt(p_password, password_hash) = password_hash`.
- **Giới hạn tốc độ đăng nhập/tạo lớp** (rate limit) — Postgres function có thể tự đếm số lần thử trong bảng log nhỏ, hoặc đơn giản hơn: giới hạn ở tầng Supabase (Edge Function / Cloudflare nếu deploy qua đó). Vì mật khẩu là chuỗi ngắn dễ đoán, không có giới hạn thì ai cũng có thể dò.
- **Bật RLS (Row Level Security)** trên tất cả bảng `bcs_*`, chỉ cho phép truy cập qua các hàm `SECURITY DEFINER` hiện có (không cấp quyền SELECT/INSERT trực tiếp cho `anon` trên bảng) — cần kiểm tra lại vì hiện tại chưa rõ RLS đã bật chưa, nếu chưa bật thì client có thể đọc thẳng bảng qua REST API mà không qua RPC nào cả.
- Anon key + Supabase URL vẫn buộc phải lộ trong file HTML (bản chất app tĩnh) — chấp nhận được **miễn là** RLS + RPC là lớp bảo vệ thật sự, không dựa vào việc "giấu key".

---

## 6. Vai trò "vận hành" của bạn (super-admin)

Vì bạn là người vận hành chung, nên có 1 lớp bảo vệ nữa ở trên cả admin từng lớp — không bắt buộc ngay, nhưng nên có sớm:

- 1 màn hình/trang riêng (hoặc mở rộng trang admin) để bạn xem: danh sách lớp đang hoạt động, ai vừa tạo lớp, số lượng ghi chú mỗi lớp — để phát hiện lớp rác/spam hoặc lớp GV bỏ dùng.
- Khả năng khoá/xoá 1 lớp (đặt `active=false` ở `bcs_classes`) nếu cần, mà không đụng dữ liệu lớp khác — chính là lý do `class_id` tách bạch quan trọng.
- Theo dõi **hạn mức Supabase free tier** (dung lượng DB, số lượng request/tháng) khi số lớp tăng — free tier hiện đủ cho vài lớp nhỏ, nhưng nên để ý khi mời thêm người.

---

## 7. Lộ trình đề xuất (làm theo giai đoạn, không cần làm hết 1 lần)

| Giai đoạn | Nội dung | Vì sao trước/sau |
|---|---|---|
| **1. Bắt buộc trước khi mời ai** | Thêm `class_id` vào toàn bộ bảng + sửa toàn bộ RPC + migrate 8A9 | Không có bước này thì dữ liệu các lớp lẫn vào nhau — chặn cứng, không thể bỏ qua |
| **2. Bắt buộc trước khi mời ai** | Hash mật khẩu + xác nhận/bật RLS trên bảng | Bảo vệ dữ liệu nhận xét học sinh của nhiều GV khác nhau trên cùng hệ thống |
| **3. Bắt buộc trước khi mời ai** | Màn hình "Tạo lớp mới" + bỏ hard-code "Lớp 8A9" trong HTML (dùng `class_name` động) | Đây là tính năng đồng nghiệp cần dùng trực tiếp |
| **4. Nên có sớm** | Giới hạn tốc độ tạo lớp/đăng nhập | Tránh dò mật khẩu, tránh spam tạo lớp |
| **5. Có thể làm sau, không gấp** | Trang "vận hành" cho bạn xem danh sách lớp, khoá/xoá lớp | Chỉ cần thiết khi số lớp bắt đầu nhiều hơn vài lớp quen biết |
| **6. Có thể làm sau** | Hướng dẫn dùng ngắn (1 trang) cho GV mới: cách tạo lớp, cách gửi mật khẩu ban cán sự cho học sinh | Đồng nghiệp không rành công nghệ sẽ cần hướng dẫn bằng lời, không chỉ giao diện |

**Đề xuất:** làm gọn giai đoạn 1–3 thành một đợt migrate + sửa code duy nhất (vì đều đụng vào cùng các hàm RPC), test kỹ với chính lớp 8A9 trước, rồi mới gửi link cho đồng nghiệp đầu tiên thử.

---

## 8. Việc cần bạn xác nhận/cung cấp khi bắt tay code

- Mật khẩu quản trị hiện tại của lớp 8A9 (để gán đúng vào `bcs_classes` khi migrate) — hoặc xác nhận có thể lấy trực tiếp từ bảng `bcs_roles` hiện có.
- Tên hiển thị chính xác muốn dùng cho lớp 8A9 trong hệ thống mới (giữ "8A9" hay đổi thành "Lớp 8A9", "9A2 - Trường ABC"...).
- App hiện đang mở bằng cách nào (file local, hay đã host ở đâu đó)? Ảnh hưởng bước "gửi link" cho đồng nghiệp ở giai đoạn 3.
