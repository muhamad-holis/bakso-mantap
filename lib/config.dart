/// Diisi lewat --dart-define (GitHub Secrets). Jika kosong, aplikasi berjalan
/// sebagai kasir offline biasa tanpa login & tanpa koneksi ke bos.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get cloudEnabled => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

/// Nomor build dari GitHub Actions (untuk memastikan APK yang terpasang adalah yang terbaru).
const buildNumber = String.fromEnvironment('BUILD_NUMBER', defaultValue: 'lokal');

/// Jumlah meja bawaan (dipakai bila bos belum mengatur jumlah meja cabang).
const defaultTableCount = 20;
