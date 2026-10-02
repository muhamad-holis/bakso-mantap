-- TAHAP 5: nomor meja, nama pelanggan, dan jenis pesanan (makan di tempat / bawa pulang).
-- Jalankan SEBELUM memasang APK baru. Aman dijalankan berulang kali.
-- (SQL Editor -> New query -> paste -> Run)

alter table public.transactions add column if not exists order_type    text not null default '';
alter table public.transactions add column if not exists table_no      text not null default '';
alter table public.transactions add column if not exists customer_name text not null default '';

-- transaksi lama dibiarkan kosong (tidak diketahui makan di tempat atau bawa pulang).
-- Policy RLS yang sudah ada tidak perlu diubah.

-- CEK: pesanan terbaru beserta meja & pelanggan
select id, branch, order_type, table_no, customer_name, total, created_at
from public.transactions order by created_at desc limit 10;
