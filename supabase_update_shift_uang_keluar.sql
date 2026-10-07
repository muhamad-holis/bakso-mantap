-- TAHAP 7: uang keluar dari laci + rincian penjualan non-tunai per shift.
-- Jalankan sekali di Supabase (SQL Editor -> New query -> paste -> Run). Aman dijalankan berulang kali.
-- Jika belum dijalankan, aplikasi tetap jalan: uang keluar ikut tersimpan di kolom Catatan.

alter table public.shifts add column if not exists cash_out        int   not null default 0;
alter table public.shifts add column if not exists cash_out_items  jsonb not null default '[]'::jsonb;
alter table public.shifts add column if not exists noncash         jsonb not null default '{}'::jsonb;

notify pgrst, 'reload schema';

-- CEK: shift terbaru
select kasir, branch, opening_cash, cash_sales, cash_out, expected_cash, closing_cash, difference, noncash, closed_at
from public.shifts order by closed_at desc limit 10;
