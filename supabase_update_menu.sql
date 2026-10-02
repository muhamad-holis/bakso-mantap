-- TAHAP 2: menu & harga diatur bos. Jalankan SETELAH supabase_setup.sql
-- (SQL Editor -> New query -> paste -> Run)

create table if not exists public.menus (
  id       text primary key,
  name     text not null,
  category text not null default 'Bakso',
  price    int  not null check (price >= 0),
  emoji    text not null default '🍜'
);

create table if not exists public.app_settings (
  key   text primary key,
  value text not null
);

alter table public.menus enable row level security;
alter table public.app_settings enable row level security;

-- semua akun yang login boleh MEMBACA; hanya bos yang boleh mengubah
create policy "login baca menu" on public.menus
  for select to authenticated using (true);
create policy "bos kelola menu" on public.menus
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

create policy "login baca pengaturan" on public.app_settings
  for select to authenticated using (true);
create policy "bos kelola pengaturan" on public.app_settings
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

alter publication supabase_realtime add table public.menus;

-- menu awal (bisa diubah bos dari aplikasi)
insert into public.menus (id, name, category, price, emoji) values
  ('bakso-urat',     'Bakso Urat',     'Bakso',   15000, '🍲'),
  ('bakso-halus',    'Bakso Halus',    'Bakso',   13000, '🍲'),
  ('bakso-jumbo',    'Bakso Jumbo',    'Bakso',   18000, '🍲'),
  ('mie-ayam-bakso', 'Mie Ayam Bakso', 'Mie',     15000, '🍜'),
  ('mie-ayam',       'Mie Ayam',       'Mie',     12000, '🍜'),
  ('es-teh-manis',   'Es Teh Manis',   'Minuman',  5000, '🧋'),
  ('es-jeruk',       'Es Jeruk',       'Minuman',  6000, '🍊'),
  ('es-nutrisari',   'Es Nutrisari',   'Minuman',  5000, '🥤'),
  ('paket-hemat',    'Paket Hemat',    'Paket',   18000, '🍱')
on conflict (id) do nothing;

insert into public.app_settings (key, value) values
  ('store_name', 'Bakso TITATI Wonogiri Opik Jon'),
  ('tax_percent', '11')
on conflict (key) do nothing;
