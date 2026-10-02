-- TAHAP 7: pengeluaran harian (belanja bahan, dll) yang dicatat bos, untuk menghitung laba.
-- Jalankan SEBELUM memasang APK baru. Aman dijalankan berulang kali.
-- (SQL Editor -> New query -> paste -> Run)

create table if not exists public.expenses (
  id         text primary key,
  date       date not null,
  branch     text not null default '',      -- kosong = umum (semua cabang)
  category   text not null default 'Bahan baku',
  name       text not null,
  amount     int  not null check (amount > 0),
  note       text not null default '',
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);

create index if not exists expenses_date_idx on public.expenses (date desc);

alter table public.expenses enable row level security;
grant select, insert, update, delete on public.expenses to authenticated;

-- hanya bos yang boleh melihat & mengelola pengeluaran
drop policy if exists "bos kelola pengeluaran" on public.expenses;
create policy "bos kelola pengeluaran" on public.expenses
  for all to authenticated using (public.is_bos()) with check (public.is_bos());

notify pgrst, 'reload schema';

-- CEK: pengeluaran terbaru
select id, date, branch, category, name, amount from public.expenses order by date desc, created_at desc limit 10;
