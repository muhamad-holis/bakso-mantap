# Setup Mode Bos (Supabase)

1. Buat project di https://supabase.com (gratis).
2. **SQL Editor** -> New query -> paste isi `supabase_setup.sql` -> Run.
2b. Jalankan juga `supabase_update_menu.sql` (menu & harga diatur bos).
2c. Jalankan juga `supabase_update_cabang_menu.sql` (menu per cabang).
2d. Jalankan juga `supabase_update_harga_cabang.sql` (harga & foto berbeda tiap cabang, bucket foto `menu-images`, nama resto Bakso TITATI Wonogiri Opik Jon).
3. **Authentication -> Users -> Add user** untuk 1 bos dan 3 kasir
   (centang *Auto Confirm User*). Contoh: bos@contoh.com, kasir1@contoh.com,
   kasir2@contoh.com, kasir3@contoh.com.
4. Jadikan akun bos: jalankan query `update public.profiles set role='bos' ...`
   (ada di bagian bawah `supabase_setup.sql`). Akun lain otomatis jadi kasir.
   Atur nama dan cabang tiap kasir dengan query `update public.profiles set name=..., branch=...`
   (contohnya ada di `supabase_setup.sql`). Jika SQL versi lama sudah pernah dijalankan,
   jalankan dua baris `alter table ... add column branch` di file itu.
5. **Project Settings -> API**: salin *Project URL* dan *anon public key*.
6. GitHub repo -> **Settings -> Secrets and variables -> Actions -> New repository secret**:
   - `SUPABASE_URL` = Project URL
   - `SUPABASE_ANON_KEY` = anon public key
7. Push ke `main` (atau Run workflow). Instal APK yang baru di HP kasir dan HP bos.

Catatan:
- Tanpa kedua secret itu, APK tetap jalan sebagai kasir offline (tanpa login).
- Kasir tetap bisa jualan saat internet mati; transaksi terkirim otomatis saat online
  (ikon awan di tab Transaksi: hijau = sudah terkirim).
- Layar bos menampilkan 1.000 transaksi terbaru.
- Di Mode Bos ada filter cabang dan ringkasan omzet per cabang.
- Menu, harga, nama toko, dan pajak hanya bisa diubah bos (tab Menu & Harga / Pengaturan). Kasir otomatis mengikuti dalam +-30 detik.
- Di mode login, kasir hanya punya tab Kasir, Transaksi, Akun. Diskon manual dinonaktifkan untuk kasir.
- Di tab Menu & Harga, bos memilih cabang dulu (chip di atas), lalu tambah/edit menu. Harga dan foto hanya berlaku di cabang yang dipilih; nama, kategori, dan emoji berlaku di semua cabang.
- Saat tambah menu baru, bos bisa mencentang cabang lain agar menu yang sama ikut ditambahkan. Tombol 'Salin menu dari cabang lain' mempercepat cabang baru.
- Foto diambil dari Galeri/Kamera HP bos, diunggah ke Supabase Storage, dan otomatis muncul di HP kasir cabang itu (disimpan di cache, tetap tampil saat internet mati).
- Daftar cabang diambil dari kolom `branch` akun kasir.
