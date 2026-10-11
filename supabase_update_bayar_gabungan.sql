-- TAHAP 10: PEMBAYARAN GABUNGAN (mis. Tunai + QRIS pada satu nota).
-- Jalankan sekali di Supabase: SQL Editor -> New query -> paste -> Run. Aman dijalankan berulang kali.
-- Transaksi lama dan transaksi bayar biasa tidak berubah.
-- Jika belum dijalankan, aplikasi tetap jalan: rincian bayar gabungan dititipkan di kolom catatan.

alter table public.transactions add column if not exists payments jsonb;

notify pgrst, 'reload schema';
