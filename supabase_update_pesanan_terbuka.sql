-- TAHAP 6: PESANAN TERBUKA (pelanggan makan dulu, bayar belakangan).
-- Jalankan SEBELUM memasang APK baru. Aman dijalankan berulang kali.
-- (SQL Editor -> New query -> paste -> Run)

create table if not exists public.open_orders (
  id            text primary key,
  branch        text not null default '',
  table_no      text not null default '',
  customer_name text not null default '',
  kasir         text not null default '',
  kasir_id      uuid default auth.uid(),
  status        text not null default 'open' check (status in ('open', 'paid', 'cancelled')),
  -- tiap batch item: menu_id, name, price, qty, note, added_by, added_at
  lines         jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  closed_at     timestamptz,
  trx_id        text not null default ''
);

create index if not exists open_orders_branch_status on public.open_orders (branch, status);

-- cabang milik akun yang sedang login
create or replace function public.my_branch() returns text
language sql security definer set search_path = public stable as $$
  select coalesce((select branch from public.profiles where id = auth.uid()), '');
$$;

alter table public.open_orders enable row level security;
grant select, insert, update on public.open_orders to authenticated;

-- kasir: hanya melihat/menambah/mengubah pesanan cabangnya sendiri (tidak bisa menghapus)
drop policy if exists "baca pesanan cabang" on public.open_orders;
create policy "baca pesanan cabang" on public.open_orders
  for select to authenticated using (public.is_bos() or branch = public.my_branch());

drop policy if exists "buat pesanan cabang" on public.open_orders;
create policy "buat pesanan cabang" on public.open_orders
  for insert to authenticated with check (branch = public.my_branch() and branch <> '');

drop policy if exists "ubah pesanan cabang" on public.open_orders;
create policy "ubah pesanan cabang" on public.open_orders
  for update to authenticated
  using (branch = public.my_branch())
  with check (branch = public.my_branch());

-- bos: kendali penuh (lihat semua cabang, batalkan pesanan)
drop policy if exists "bos kelola pesanan" on public.open_orders;
create policy "bos kelola pesanan" on public.open_orders
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

notify pgrst, 'reload schema';

-- CEK: tabel sudah ada (hasil 0 baris itu normal sebelum ada pesanan)
select id, branch, table_no, customer_name, status, created_at
from public.open_orders order by created_at desc limit 10;
