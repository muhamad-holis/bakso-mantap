-- TAHAP 8: daftar cabang resmi (buka cabang baru dari aplikasi bos) + jumlah meja per cabang.
-- Jalankan SEBELUM memasang APK yang baru. Aman dijalankan berulang kali.
-- (SQL Editor -> New query -> paste -> Run)

create table if not exists public.branches (
  name        text primary key,
  table_count int not null default 20 check (table_count between 1 and 200),
  created_at  timestamptz not null default now()
);

alter table public.branches enable row level security;
grant select, insert, update, delete on public.branches to authenticated;

-- semua akun login (kasir) boleh membaca daftar cabang & jumlah mejanya
drop policy if exists "login baca cabang" on public.branches;
create policy "login baca cabang" on public.branches
  for select to authenticated using (true);

-- hanya bos yang boleh menambah / mengubah / menghapus cabang
drop policy if exists "bos kelola cabang" on public.branches;
create policy "bos kelola cabang" on public.branches
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

-- bos boleh menetapkan akun kasir ke cabang (mengubah profil)
grant select, update on public.profiles to authenticated;
drop policy if exists "bos ubah profil" on public.profiles;
create policy "bos ubah profil" on public.profiles
  for update to authenticated using (public.is_bos()) with check (public.is_bos());

-- isi otomatis dari cabang yang sudah ada
insert into public.branches (name)
select distinct branch from public.profiles where branch <> ''
union
select distinct branch from public.menu_branch where branch <> ''
on conflict (name) do nothing;

notify pgrst, 'reload schema';

-- CEK: daftar cabang
select * from public.branches order by name;
