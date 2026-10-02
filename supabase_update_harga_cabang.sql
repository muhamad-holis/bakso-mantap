-- TAHAP 4: harga & foto menu berbeda per cabang + nama resto.
-- Jalankan SETELAH supabase_setup.sql, supabase_update_menu.sql, supabase_update_cabang_menu.sql
-- (SQL Editor -> New query -> paste -> Run)

-- 1) Tabel menu per cabang: harga & foto tiap cabang sendiri-sendiri.
--    Menu hanya muncul di cabang yang punya barisnya di tabel ini.
create table if not exists public.menu_branch (
  menu_id   text not null references public.menus(id) on delete cascade,
  branch    text not null,
  price     int  not null check (price >= 0),
  image_url text not null default '',
  primary key (menu_id, branch)
);

alter table public.menu_branch enable row level security;

drop policy if exists "login baca menu cabang" on public.menu_branch;
create policy "login baca menu cabang" on public.menu_branch
  for select to authenticated using (true);

drop policy if exists "bos kelola menu cabang" on public.menu_branch;
create policy "bos kelola menu cabang" on public.menu_branch
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

-- 2) Pindahkan menu & harga lama ke setiap cabang yang sudah ada
--    (mengikuti kolom menus.branches; kosong = semua cabang)
insert into public.menu_branch (menu_id, branch, price)
select m.id, b.branch, m.price
from public.menus m
cross join (select distinct branch from public.profiles where branch <> '') b
where cardinality(m.branches) = 0 or b.branch = any (m.branches)
on conflict (menu_id, branch) do nothing;

-- 3) Tempat penyimpanan foto menu (publik dibaca, hanya bos yang boleh unggah)
insert into storage.buckets (id, name, public)
values ('menu-images', 'menu-images', true)
on conflict (id) do update set public = true;

drop policy if exists "foto menu dibaca" on storage.objects;
create policy "foto menu dibaca" on storage.objects
  for select using (bucket_id = 'menu-images');

drop policy if exists "bos unggah foto menu" on storage.objects;
create policy "bos unggah foto menu" on storage.objects
  for insert to authenticated with check (bucket_id = 'menu-images' and public.is_bos());

drop policy if exists "bos ubah foto menu" on storage.objects;
create policy "bos ubah foto menu" on storage.objects
  for update to authenticated
  using (bucket_id = 'menu-images' and public.is_bos())
  with check (bucket_id = 'menu-images' and public.is_bos());

drop policy if exists "bos hapus foto menu" on storage.objects;
create policy "bos hapus foto menu" on storage.objects
  for delete to authenticated using (bucket_id = 'menu-images' and public.is_bos());

-- 4) Nama resto
insert into public.app_settings (key, value)
values ('store_name', 'Bakso TITATI Wonogiri Opik Jon')
on conflict (key) do update set value = excluded.value;
