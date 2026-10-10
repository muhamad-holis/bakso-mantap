-- TAHAP 9: SATU MEJA = SATU PESANAN TERBUKA (mencegah pesanan ganda di meja yang sama).
-- Jalankan di Supabase: SQL Editor -> New query -> paste -> Run. Aman dijalankan berulang kali.
-- Menambah menu ke pesanan yang sudah ada TIDAK terpengaruh.

-- LANGKAH 1 - CEK dulu apakah sekarang ada meja yang punya lebih dari satu pesanan terbuka.
-- Kalau hasilnya 0 baris, lanjut ke LANGKAH 2.
-- Kalau ada baris, bayar atau batalkan salah satu pesanannya dulu di aplikasi, lalu jalankan ulang.
select branch, table_no, count(*) as jumlah_pesanan, array_agg(id order by created_at) as daftar_id
from public.open_orders
where status = 'open' and table_no <> ''
group by branch, table_no
having count(*) > 1;

-- LANGKAH 2 - kunci: satu meja hanya boleh punya satu pesanan berstatus 'open'.
-- (Gagal dengan pesan duplicate key = masih ada duplikat dari LANGKAH 1; rapikan dulu.)
create unique index if not exists open_orders_satu_meja
  on public.open_orders (branch, table_no)
  where status = 'open' and table_no <> '';

notify pgrst, 'reload schema';
