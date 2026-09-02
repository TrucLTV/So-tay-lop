-- Ghi chú (content) là tuỳ chọn ở nhiều loại (Vi phạm, Khen thưởng, Báo bài...),
-- nhưng cột đang bắt buộc NOT NULL từ trước -> gây lỗi khi để trống. Bỏ ràng buộc này.
alter table bcs_notes alter column content drop not null;
