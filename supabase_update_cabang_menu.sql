-- TAHAP 3: menu bisa dipilih per cabang.
-- Jalankan SETELAH supabase_setup.sql dan supabase_update_menu.sql
-- (SQL Editor -> New query -> paste -> Run)

-- daftar cabang tempat menu tersedia. Kosong = semua cabang.
alter table public.menus add column if not exists branches text[] not null default '{}';

-- bos perlu membaca daftar cabang dari akun kasir
drop policy if exists "bos baca semua profil" on public.profiles;
create policy "bos baca semua profil" on public.profiles
  for select to authenticated using (public.is_bos());
