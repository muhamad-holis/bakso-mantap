import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'state.dart';
import 'utils.dart';

/// Satu catatan uang keluar kasir beserta cabangnya (untuk laporan laba & rekap harian).
class CashOutEntry {
  final String branch;
  final String kasir;
  final CashOut item;
  CashOutEntry(this.branch, this.kasir, this.item);
}

/// Uang keluar kasir (dari shift yang sudah ditutup) pada rentang waktu [from, to).
/// [to] null = tanpa batas atas. [branch] 'Semua Cabang' = tanpa filter cabang.
List<CashOutEntry> cashOutEntries(List<Shift> shifts, {required DateTime from, DateTime? to, String branch = 'Semua Cabang'}) {
  final out = <CashOutEntry>[];
  for (final s in shifts) {
    if (branch != 'Semua Cabang' && s.branch != branch) continue;
    for (final c in s.cashOuts) {
      if (c.at.isBefore(from)) continue;
      if (to != null && !c.at.isBefore(to)) continue;
      out.add(CashOutEntry(s.branch, s.kasir, c));
    }
  }
  return out;
}

/// Ringkasan tutup shift dalam bentuk teks (untuk WhatsApp).
String shiftSummaryText(Shift x, String store) {
  final b = StringBuffer();
  final closed = x.closedAt ?? DateTime.now();
  b.writeln('*LAPORAN TUTUP SHIFT*');
  b.writeln(store);
  if (x.branch.isNotEmpty) b.writeln('Cabang: ${x.branch}');
  b.writeln('Kasir: ${x.kasir.isEmpty ? '-' : x.kasir}');
  b.writeln('${tgl(x.openedAt)}, ${jam(x.openedAt)} - ${jam(closed)}');
  b.writeln('');
  b.writeln('Uang modal awal: ${rp(x.openingCash)}');
  b.writeln('Penjualan tunai: ${rp(x.cashSales)}');
  b.writeln('Uang keluar: ${rp(x.cashOutTotal)}');
  for (final c in x.cashOuts) {
    b.writeln('   - ${c.label}: ${rp(c.amount)}');
  }
  b.writeln('Uang seharusnya di laci: ${rp(x.expectedCash)}');
  b.writeln('Uang di laci (hitungan): ${rp(x.closingCash)}');
  final mark = x.difference == 0 ? '✅' : '⚠️';
  b.writeln('$mark *Selisih: ${selisihText(x.difference)}*');
  if (x.nonCash.isNotEmpty) {
    b.writeln('');
    b.writeln('Tidak masuk laci (uang di rekening):');
    for (final e in x.nonCash.entries) {
      b.writeln('   ${e.key}: ${rp(e.value)}');
    }
  }
  b.writeln('');
  b.writeln('Total penjualan shift: ${rp(x.cashSales + x.nonCashTotal)}');
  if (x.note.isNotEmpty) b.writeln('Catatan: ${x.note}');
  return b.toString().trimRight();
}

/// Ubah nomor lokal (08xxx / +62xxx / 62xxx / 8xxx) menjadi format internasional tanpa tanda plus.
String waNumber(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  if (d.startsWith('0')) d = '62${d.substring(1)}';
  else if (d.startsWith('8')) d = '62$d';
  return d;
}

/// Buka WhatsApp dengan teks siap kirim. Jika nomor bos belum diatur, kasir memilih penerima sendiri.
Future<void> sendWhatsApp(BuildContext context, String text, {bool chooseContact = false}) async {
  final number = chooseContact ? '' : waNumber(context.read<AppState>().bosWa);
  final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(text)}');
  final m = ScaffoldMessenger.of(context);
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) m.showSnackBar(SnackBar(content: Text('WhatsApp tidak bisa dibuka. Pastikan WhatsApp sudah terpasang.')));
  } catch (_) {
    m.showSnackBar(SnackBar(content: Text('WhatsApp tidak bisa dibuka. Pastikan WhatsApp sudah terpasang.')));
  }
}
