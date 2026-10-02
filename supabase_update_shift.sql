-- TAHAP 6: tutup kasir / shift (kas awal, kas akhir, selisih terhadap tunai di sistem).
-- Jalankan sebelum memasang APK baru. Aman dijalankan berulang kali.
-- (SQL Editor -> New query -> paste -> Run)

create table if not exists public.shifts (
  id            text primary key,
  kasir         text not null default '',
  kasir_id      uuid default auth.uid(),
  branch        text not null default '',
  opened_at     timestamptz not null,
  closed_at     timestamptz not null,
  opening_cash  int not null,
  closing_cash  int not null,
  cash_sales    int not null,
  expected_cash int not null,
  difference    int not null,
  note          text not null default ''
);

create index if not exists shifts_closed_at_idx on public.shifts (closed_at desc);

alter table public.shifts enable row level security;
grant select, insert on public.shifts to authenticated;

drop policy if exists "kasir kirim shift" on public.shifts;
create policy "kasir kirim shift" on public.shifts
  for insert to authenticated with check (kasir_id = auth.uid());

-- kasir perlu membaca shift miliknya sendiri (dibutuhkan saat kirim/upsert)
drop policy if exists "kasir baca shift sendiri" on public.shifts;
create policy "kasir baca shift sendiri" on public.shifts
  for select to authenticated using (kasir_id = auth.uid());

drop policy if exists "bos baca semua shift" on public.shifts;
create policy "bos baca semua shift" on public.shifts
  for select to authenticated using (public.is_bos());

notify pgrst, 'reload schema';

-- CEK: shift terbaru
select id, kasir, branch, opening_cash, cash_sales, closing_cash, difference, closed_at
from public.shifts order by closed_at desc limit 10;
