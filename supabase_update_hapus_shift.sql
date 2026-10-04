-- TAHAP: bos boleh menghapus riwayat closing (tabel shifts).
-- Jalankan SEKALI sebelum memakai tombol hapus/Bersihkan di aplikasi bos.
-- Aman dijalankan berulang kali. (SQL Editor -> New query -> paste -> Run)
-- Kasir TIDAK mendapat izin hapus.

grant delete on public.shifts to authenticated;

drop policy if exists "bos hapus shift" on public.shifts;
create policy "bos hapus shift" on public.shifts
  for delete to authenticated using (public.is_bos());

notify pgrst, 'reload schema';

-- CEK: harus muncul 1 baris policy untuk perintah DELETE
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'shifts' and cmd = 'DELETE';
