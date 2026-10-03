# Setup Mode Bos (Supabase)

1. Buat project di https://supabase.com (gratis).
2. **SQL Editor** -> New query -> paste isi `supabase_setup.sql` -> Run.
2b. Jalankan juga `supabase_update_menu.sql` (menu & harga diatur bos).
2c. Jalankan juga `supabase_update_cabang_menu.sql` (menu per cabang).
2d. Jalankan juga `supabase_update_harga_cabang.sql` (harga & foto berbeda tiap cabang, bucket foto `menu-images`, nama resto Bakso TITATI Wonogiri Opik Jon).
2e. Jalankan juga `supabase_update_meja_pelanggan.sql` (nomor meja, nama pelanggan, makan di tempat / bawa pulang). Jalankan SEBELUM memasang APK yang baru.
2f. Jalankan juga `supabase_update_shift.sql` (tutup kasir/shift: kas awal, kas akhir, selisih). Jalankan SEBELUM memasang APK yang baru.
2g. Jalankan juga `supabase_update_pengeluaran.sql` (pengeluaran harian & laba untuk bos). Jalankan SEBELUM memasang APK yang baru.
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

- Jika transaksi kasir tidak muncul di laporan bos, jalankan `supabase_perbaikan_transaksi.sql` (aman diulang). Layar Akun kasir menampilkan pesan error bila pengiriman gagal.
- Di kasir, pilih Makan di Tempat (wajib pilih nomor meja dari dropdown, nama pelanggan diisi manual) atau Bawa Pulang (tanpa meja & nama). Info ini tampil di struk, riwayat transaksi, dan layar bos. Jumlah meja diatur lewat `tableCount` di `lib/config.dart`.
- Jika Akun kasir menampilkan error `Could not find the 'customer_name' column ... PGRST204`, jalankan `supabase_perbaikan_kolom_meja.sql` (aman diulang). Sebelum itu dijalankan, aplikasi tetap mengirim transaksi dan menyimpan info meja/pelanggan di catatan.
- Catatan per item: di keranjang, ketuk 'Tambah catatan' pada menu yang dipesan (mis. 'Tanpa sambal'). Jika menu dipesan lebih dari 1 porsi, kasir memilih catatan berlaku untuk berapa porsi; menu yang sama dengan catatan berbeda jadi baris terpisah. Catatan tampil di struk, riwayat transaksi, dan layar bos. Catatan di halaman pembayaran kini khusus catatan transaksi (umum).
- Shift kasir (tab Akun / Pengaturan): Buka Shift isi kas awal -> berjualan -> Tutup Shift isi kas akhir (hasil hitung uang). Selisih = kas akhir - (kas awal + total transaksi Tunai sejak shift dibuka). Shift yang ditutup dikirim ke bos (bagian 'Tutup shift terbaru' di layar Pantau); jika tabel `shifts` belum dibuat, riwayat tetap aman di HP dan dikirim otomatis setelah SQL dijalankan.
- Pengeluaran & laba (hanya bos): tab Pengeluaran untuk mencatat belanja bahan, gas/listrik, gaji, dll (per tanggal & cabang, atau Umum untuk semua cabang). Di layar Pantau, kartu Laba = Omzet - Pajak (PPN) terkumpul - Pengeluaran, lengkap dengan laba per hari (7/30 hari) dan laba per cabang. Kasir tidak bisa melihat data pengeluaran.
- Pengaturan pembayaran (hanya bos): di tab Pengaturan, unggah gambar QRIS dan isi nama bank, nomor rekening, atas nama, lalu tekan 'Simpan Pembayaran untuk Semua Cabang'. HP kasir semua cabang ikut berubah dalam +-30 detik. Saat kasir memilih metode QRIS, gambar QRIS tampil (ketuk untuk memperbesar); saat memilih Transfer, nomor rekening tampil dengan tombol salin. Tidak perlu SQL baru: memakai tabel `app_settings` dan bucket `menu-images` yang sudah ada (folder `pembayaran/`).
- Ikon aplikasi: file ikon ada di folder `android_res/` (ikon adaptif + ikon biasa) dan sumbernya di `branding/app_icon.png`. GitHub Actions menyalinnya otomatis ke proyek Android saat build, jadi tidak perlu langkah manual. Untuk mengganti ikon, ganti file di `android_res/mipmap-*/`.
