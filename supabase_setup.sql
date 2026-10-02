-- Jalankan di Supabase: SQL Editor -> New query -> paste -> Run

create table if not exists public.profiles (
  id   uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  role text not null default 'kasir' check (role in ('kasir', 'bos')),
  branch text not null default ''
);

create table if not exists public.transactions (
  id         text primary key,
  created_at timestamptz not null,
  kasir      text not null,
  kasir_id   uuid default auth.uid(),
  branch     text not null default '',
  item_count int not null,
  subtotal   int not null,
  discount   int not null,
  tax        int not null,
  total      int not null,
  paid       int not null,
  change     int not null,
  method     text not null,
  note       text not null default '',
  lines      jsonb not null
);

create index if not exists transactions_created_at_idx on public.transactions (created_at desc);

alter table public.profiles enable row level security;
alter table public.transactions enable row level security;

create or replace function public.is_bos() returns boolean
language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'bos');
$$;

create policy "baca profil sendiri" on public.profiles
  for select to authenticated using (id = auth.uid());

create policy "kasir kirim transaksi" on public.transactions
  for insert to authenticated with check (kasir_id = auth.uid());

create policy "bos baca semua transaksi" on public.transactions
  for select to authenticated using (public.is_bos());

-- profil otomatis dibuat saat akun baru dibuat
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)));
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- aktifkan realtime untuk layar bos
alter publication supabase_realtime add table public.transactions;

-- Jika SQL versi sebelumnya sudah pernah dijalankan, jalankan 2 baris ini saja:
alter table public.profiles add column if not exists branch text not null default '';
alter table public.transactions add column if not exists branch text not null default '';

-- Atur nama & cabang tiap kasir (ganti email, nama, dan cabang):
-- update public.profiles set name = 'Andi', branch = 'Cabang 1'
-- where id = (select id from auth.users where email = 'kasir1@contoh.com');
-- update public.profiles set name = 'Budi', branch = 'Cabang 2'
-- where id = (select id from auth.users where email = 'kasir2@contoh.com');
-- update public.profiles set name = 'Citra', branch = 'Cabang 3'
-- where id = (select id from auth.users where email = 'kasir3@contoh.com');

-- Setelah akun bos dibuat di Authentication -> Users, jadikan bos (ganti emailnya):
-- update public.profiles set role = 'bos', name = 'Bos'
-- where id = (select id from auth.users where email = 'bos@contoh.com');
