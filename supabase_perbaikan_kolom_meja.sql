-- PERBAIKAN: "Could not find the 'customer_name' column of 'transactions' in the schema cache" (PGRST204)
-- Penyebab: kolom meja/pelanggan belum ada di tabel transactions, atau cache API belum dimuat ulang.
-- Aman dijalankan berulang kali. (SQL Editor -> New query -> paste -> Run)

alter table public.transactions add column if not exists branch        text not null default '';
alter table public.transactions add column if not exists order_type    text not null default '';
alter table public.transactions add column if not exists table_no      text not null default '';
alter table public.transactions add column if not exists customer_name text not null default '';

-- muat ulang schema cache API Supabase
notify pgrst, 'reload schema';

-- CEK: ketiga kolom ini harus muncul (order_type, table_no, customer_name)
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'transactions'
  and column_name in ('branch', 'order_type', 'table_no', 'customer_name');
