import 'models.dart';

String two(int n) => n.toString().padLeft(2, '0');

String rp(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}Rp $b';
}

const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
String tgl(DateTime d) => '${two(d.day)} ${_bulan[d.month - 1]} ${d.year}';
String jam(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String receiptText(Trx t, String store) {
  final b = StringBuffer();
  b.writeln(store);
  b.writeln('No: ${t.id}');
  b.writeln('${tgl(t.date)} ${jam(t.date)}');
  b.writeln('Kasir: ${t.kasir}');
  if (t.branch.isNotEmpty) b.writeln('Cabang: ${t.branch}');
  if (t.orderType.isNotEmpty) b.writeln('Pesanan: ${t.orderType}');
  if (t.tableNo.isNotEmpty) b.writeln('Meja: ${t.tableNo}');
  if (t.customerName.isNotEmpty) b.writeln('Pelanggan: ${t.customerName}');
  b.writeln('--------------------------------');
  for (final l in t.lines) {
    b.writeln(l.name);
    b.writeln('  ${l.qty} x ${rp(l.price)} = ${rp(l.price * l.qty)}');
  }
  b.writeln('--------------------------------');
  b.writeln('Subtotal : ${rp(t.subtotal)}');
  if (t.discount > 0) b.writeln('Diskon   : -${rp(t.discount)}');
  b.writeln('Pajak    : ${rp(t.tax)}');
  b.writeln('TOTAL    : ${rp(t.total)}');
  b.writeln('Bayar (${t.method}): ${rp(t.paid)}');
  b.writeln('Kembali  : ${rp(t.change)}');
  if (t.note.isNotEmpty) b.writeln('Catatan  : ${t.note}');
  b.writeln('');
  b.writeln('Terima kasih, semoga hari Anda menyenangkan!');
  return b.toString();
}
