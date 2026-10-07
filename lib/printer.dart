import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';
import 'utils.dart';

/// Pengaturan printer disimpan di HP ini saja (tiap HP/cabang punya printer sendiri),
/// jadi tidak perlu tabel baru di Supabase.
class PrinterConfig {
  final String mac;
  final String name;
  final int paperMm; // 55 atau 80
  PrinterConfig({this.mac = '', this.name = '', this.paperMm = 55});

  bool get hasPrinter => mac.isNotEmpty;

  /// Jumlah karakter per baris: kertas 55mm = 32, kertas 80mm = 48.
  int get cols => paperMm == 80 ? 48 : 32;

  PrinterConfig copyWith({String? mac, String? name, int? paperMm}) =>
      PrinterConfig(mac: mac ?? this.mac, name: name ?? this.name, paperMm: paperMm ?? this.paperMm);

  static Future<PrinterConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final mm = p.getInt('printer_paper') ?? 55;
    return PrinterConfig(
      mac: p.getString('printer_mac') ?? '',
      name: p.getString('printer_name') ?? '',
      paperMm: mm == 80 ? 80 : 55,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('printer_mac', mac);
    await p.setString('printer_name', name);
    await p.setInt('printer_paper', paperMm);
  }
}

class ThermalPrinter {
  static bool _busy = false;
  static String? _connectedMac;

  /// Cek izin Bluetooth & status Bluetooth. Mengembalikan pesan error, atau null jika siap.
  static Future<String?> ensureReady() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await [Permission.bluetoothConnect, Permission.bluetoothScan].request();
      }
      if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
        return 'Izin Bluetooth belum diberikan. Buka Pengaturan HP > Aplikasi > Izin > Perangkat sekitar, lalu izinkan.';
      }
      if (!await PrintBluetoothThermal.bluetoothEnabled) {
        return 'Bluetooth HP belum aktif. Nyalakan Bluetooth dulu.';
      }
    } catch (e) {
      return 'Bluetooth tidak bisa diakses: $e';
    }
    return null;
  }

  /// Daftar perangkat Bluetooth yang sudah dipasangkan (paired) di HP.
  static Future<List<BluetoothInfo>> paired() => PrintBluetoothThermal.pairedBluetooths;

  /// Kirim data ke printer. Mengembalikan pesan error, atau null jika berhasil.
  static Future<String?> send(String mac, List<int> bytes) async {
    if (_busy) return 'Sedang mencetak, tunggu sebentar.';
    _busy = true;
    try {
      final ready = await ensureReady();
      if (ready != null) return ready;
      for (var attempt = 0; attempt < 2; attempt++) {
        if (_connectedMac != mac || !await PrintBluetoothThermal.connectionStatus) {
          await PrintBluetoothThermal.disconnect;
          _connectedMac = null;
          final ok = await PrintBluetoothThermal.connect(macPrinterAddress: mac);
          if (!ok) continue;
          _connectedMac = mac;
        }
        if (await PrintBluetoothThermal.writeBytes(bytes)) return null;
        _connectedMac = null; // koneksi putus, coba sambung ulang sekali
      }
      return 'Gagal terhubung ke printer. Pastikan printer menyala, dekat dengan HP, dan sudah dipasangkan di Bluetooth HP.';
    } catch (e) {
      _connectedMac = null;
      return 'Gagal mencetak: $e';
    } finally {
      _busy = false;
    }
  }
}

// ---------------- pembuat data ESC/POS ----------------

/// Printer thermal hanya pakai teks ASCII; karakter lain (emoji, dll) dibuang.
String _ascii(String s) => String.fromCharCodes(s.runes.where((r) => r >= 32 && r < 127));

List<String> _wrap(String s, int w) {
  final out = <String>[];
  var line = '';
  for (final word in _ascii(s).split(' ')) {
    if (word.isEmpty) continue;
    var wd = word;
    while (wd.length > w) {
      if (line.isNotEmpty) {
        out.add(line);
        line = '';
      }
      out.add(wd.substring(0, w));
      wd = wd.substring(w);
    }
    if (line.isEmpty) {
      line = wd;
    } else if (line.length + 1 + wd.length <= w) {
      line = '$line $wd';
    } else {
      out.add(line);
      line = wd;
    }
  }
  if (line.isNotEmpty) out.add(line);
  return out.isEmpty ? [''] : out;
}

/// Teks kiri dan kanan dalam satu baris selebar [w] karakter.
String _lr(String l, String r, int w) {
  l = _ascii(l);
  r = _ascii(r);
  final maxL = w - r.length - 1;
  if (maxL < 1) return r;
  if (l.length > maxL) l = l.substring(0, maxL);
  return l + ' ' * (w - l.length - r.length) + r;
}

class _Esc {
  final List<int> b = [];
  final int w;
  _Esc(this.w) {
    b.addAll([0x1B, 0x40]); // reset printer
  }
  void align(int a) => b.addAll([0x1B, 0x61, a]); // 0 kiri, 1 tengah
  void size(int n) => b.addAll([0x1D, 0x21, n]); // 0 normal, 0x11 = lebar & tinggi 2x
  void bold(bool on) => b.addAll([0x1B, 0x45, on ? 1 : 0]);
  void line(String s) {
    b.addAll(_ascii(s).codeUnits);
    b.add(10);
  }

  void wrapped(String s) {
    for (final l in _wrap(s, w)) {
      line(l);
    }
  }

  void sep([String ch = '-']) => line(ch * w);
  void kv(String l, String r) => line(_lr(l, r, w));
  void feed(int n) => b.addAll([0x1B, 0x64, n]);
  void cut() => b.addAll([0x1D, 0x56, 0x42, 0x00]); // potong parsial (diabaikan jika tak ada pemotong)
}

List<int> buildReceiptBytes({
  required Trx t,
  required String store,
  required String tagline,
  required int paperMm,
}) {
  final w = paperMm == 80 ? 48 : 32;
  final e = _Esc(w);

  e.align(1);
  e.bold(true);
  e.wrapped(store);
  e.bold(false);
  if (tagline.isNotEmpty) e.wrapped(tagline);
  if (t.branch.isNotEmpty) e.wrapped('Cabang ${t.branch}');
  e.sep();

  e.align(0);
  e.wrapped('No: ${t.id}');
  e.kv(tgl(t.date), jam(t.date));
  e.kv('Kasir', t.kasir);
  e.kv('Metode', t.method);
  if (t.orderType.isNotEmpty) {
    e.sep();
    e.bold(true);
    e.wrapped(t.orderType.toUpperCase());
    if (t.tableNo.isNotEmpty) e.wrapped('MEJA ${t.tableNo}');
    if (t.customerName.isNotEmpty) e.wrapped('Nama: ${t.customerName}');
    e.bold(false);
  }
  e.sep();

  for (final l in t.lines) {
    e.wrapped(l.name);
    e.kv('  ${l.qty} x ${rp(l.price)}', rp(l.price * l.qty));
    if (l.note.isNotEmpty) e.wrapped('  * ${l.note}');
  }
  e.sep();

  e.kv('Subtotal', rp(t.subtotal));
  if (t.discount > 0) e.kv('Diskon', '-${rp(t.discount)}');
  e.kv('Pajak', rp(t.tax));
  e.bold(true);
  e.kv('TOTAL', rp(t.total));
  e.bold(false);
  e.kv('Bayar', rp(t.paid));
  e.kv('Kembali', rp(t.change));
  if (t.note.isNotEmpty) {
    e.sep();
    e.wrapped('Catatan: ${t.note}');
  }
  e.sep();

  e.align(1);
  e.wrapped('Terima kasih, semoga hari Anda menyenangkan!');
  e.feed(paperMm == 80 ? 5 : 4);
  if (paperMm == 80) e.cut();
  return e.b;
}

List<int> buildTestBytes({required String printerName, required int paperMm}) {
  final w = paperMm == 80 ? 48 : 32;
  final e = _Esc(w);
  e.align(1);
  e.bold(true);
  e.line('TES CETAK');
  e.bold(false);
  e.wrapped(printerName);
  e.line('Kertas $paperMm mm ($w karakter)');
  e.sep('=');
  e.align(0);
  // penggaris: pastikan tulisan pas selebar kertas
  final ruler = StringBuffer();
  for (var i = 1; i <= w; i++) {
    ruler.write(i % 10 == 0 ? (i ~/ 10) % 10 : '.');
  }
  e.line(ruler.toString());
  e.kv('Kiri', 'Kanan');
  e.sep('=');
  e.align(1);
  e.line('Printer siap dipakai');
  e.feed(paperMm == 80 ? 5 : 4);
  if (paperMm == 80) e.cut();
  return e.b;
}

/// Bon dapur: hanya nomor meja, nama, dan item (tanpa harga).
/// [title] mis. 'PESANAN BARU', 'TAMBAHAN PESANAN', atau 'RINCIAN PESANAN'.
List<int> buildKitchenBytes({
  required String title,
  required String tableNo,
  required String customer,
  required String kasir,
  required List<OpenLine> lines,
  required int paperMm,
}) {
  final w = paperMm == 80 ? 48 : 32;
  final e = _Esc(w);
  final now = DateTime.now();
  e.align(1);
  e.bold(true);
  e.wrapped(title);
  if (tableNo.isNotEmpty) {
    e.size(0x11);
    e.line('MEJA $tableNo');
    e.size(0);
  }
  e.bold(false);
  if (customer.isNotEmpty) e.wrapped(customer);
  e.align(0);
  e.kv(tgl(now), jam(now));
  e.wrapped('Kasir: $kasir');
  e.sep();
  for (final l in lines) {
    e.bold(true);
    e.wrapped('${l.qty}x ${l.name}');
    e.bold(false);
    if (l.note.isNotEmpty) e.wrapped('   * ${l.note}');
  }
  e.sep();
  e.feed(paperMm == 80 ? 5 : 4);
  if (paperMm == 80) e.cut();
  return e.b;
}

/// Laporan tutup shift untuk printer thermal (diserahkan ke bos / ditempel).
List<int> buildShiftBytes({required Shift x, required String store, required int paperMm}) {
  final w = paperMm == 80 ? 48 : 32;
  final e = _Esc(w);
  final closed = x.closedAt ?? DateTime.now();
  e.align(1);
  e.bold(true);
  e.wrapped(store);
  e.wrapped('LAPORAN TUTUP SHIFT');
  e.bold(false);
  if (x.branch.isNotEmpty) e.wrapped('Cabang ${x.branch}');
  e.sep();
  e.align(0);
  e.kv('Kasir', x.kasir.isEmpty ? '-' : x.kasir);
  e.kv('Tanggal', tgl(x.openedAt));
  e.kv('Dibuka', jam(x.openedAt));
  e.kv('Ditutup', jam(closed));
  e.sep();
  e.kv('Uang modal awal', rp(x.openingCash));
  e.kv('Penjualan tunai', '+ ${rp(x.cashSales)}');
  e.kv('Uang keluar', '- ${rp(x.cashOutTotal)}');
  for (final c in x.cashOuts) {
    e.kv('  ${c.label}', rp(c.amount));
  }
  e.sep();
  e.kv('Seharusnya di laci', rp(x.expectedCash));
  e.kv('Uang di laci', rp(x.closingCash));
  e.bold(true);
  e.kv('SELISIH', selisihText(x.difference));
  e.bold(false);
  if (x.nonCash.isNotEmpty) {
    e.sep();
    e.wrapped('Tidak masuk laci (rekening):');
    for (final en in x.nonCash.entries) {
      e.kv('  ${en.key}', rp(en.value));
    }
  }
  e.sep();
  e.bold(true);
  e.kv('Total penjualan', rp(x.cashSales + x.nonCashTotal));
  e.bold(false);
  if (x.note.isNotEmpty) {
    e.sep();
    e.wrapped('Catatan: ${x.note}');
  }
  e.sep();
  final now = DateTime.now();
  e.line('Dicetak ${tgl(now)} ${jam(now)}');
  e.line('');
  e.line('');
  e.kv('TTD Kasir', 'TTD Bos');
  e.line('');
  e.line('');
  e.line(_lr('(.........)', '(.........)', w));
  e.feed(paperMm == 80 ? 5 : 4);
  if (paperMm == 80) e.cut();
  return e.b;
}
