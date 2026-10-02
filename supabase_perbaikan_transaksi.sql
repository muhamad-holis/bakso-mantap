-- PERBAIKAN: transaksi kasir tidak muncul di laporan bos.
-- Aman dijalankan berulang kali. (SQL Editor -> New query -> paste -> Run)

create or replace function public.is_bos() returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'bos');
$$;

alter table public.transactions enable row level security;
alter table public.transactions alter column kasir_id set default auth.uid();
grant select, insert on public.transactions to authenticated;

drop policy if exists "kasir kirim transaksi" on public.transactions;
create policy "kasir kirim transaksi" on public.transactions
  for insert to authenticated with check (kasir_id = auth.uid());

-- kasir boleh membaca transaksi miliknya sendiri (dibutuhkan saat kirim/upsert)
drop policy if exists "kasir baca transaksi sendiri" on public.transactions;
create policy "kasir baca transaksi sendiri" on public.transactions
  for select to authenticated using (kasir_id = auth.uid());

drop policy if exists "bos baca semua transaksi" on public.transactions;
create policy "bos baca semua transaksi" on public.transactions
  for select to authenticated using (public.is_bos());

-- realtime (abaikan jika sudah aktif)
do $$ begin
  alter publication supabase_realtime add table public.transactions;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';

-- CEK: transaksi yang sudah masuk ke database (urut terbaru)
select id, branch, kasir, total, created_at
from public.transactions order by created_at desc limit 10;
