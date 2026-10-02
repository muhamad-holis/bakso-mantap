import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'printer_page.dart';

class ReceiptPage extends StatelessWidget {
  final Trx trx;
  final bool fresh;
  ReceiptPage({super.key, required this.trx, this.fresh = false});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final t = trx;
    Widget kv(String a, String b, {bool bold = false}) => Padding(
          padding: EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(fresh ? 'Pembayaran Berhasil' : 'Detail Transaksi'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: !fresh,
        actions: [
          IconButton(
            tooltip: 'Pengaturan printer',
            icon: Icon(Icons.print_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PrinterPage())),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 480),
          child: ListView(padding: EdgeInsets.all(16), children: [
            if (fresh) ...[
              Icon(Icons.check_circle, color: green, size: 56),
              SizedBox(height: 6),
              Text('Pembayaran Berhasil', textAlign: TextAlign.center, style: TextStyle(color: green, fontSize: 20, fontWeight: FontWeight.w800)),
              Text('Terima kasih atas kunjungan Anda', textAlign: TextAlign.center),
              SizedBox(height: 14),
            ],
            Container(
              padding: EdgeInsets.all(16),
              decoration: cardDeco(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.storeName, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                Text(s.tagline, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                Divider(height: 22),
                kv('No. Transaksi', t.id),
                kv('Tanggal', '${tgl(t.date)} ${jam(t.date)}'),
                kv('Kasir', t.kasir),
                if (t.branch.isNotEmpty) kv('Cabang', t.branch),
                kv('Metode', t.method),
                Divider(height: 22),
                for (final l in t.lines)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.name, style: TextStyle(fontWeight: FontWeight.w600)),
                          Text('${l.qty} x ${rp(l.price)}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                        ]),
                      ),
                      Text(rp(l.price * l.qty), style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                Divider(height: 22),
                kv('Subtotal', rp(t.subtotal)),
                if (t.discount > 0) kv('Diskon', '-${rp(t.discount)}'),
                kv('Pajak', rp(t.tax)),
                kv('Total', rp(t.total), bold: true),
                kv('Bayar', rp(t.paid)),
                kv('Kembalian', rp(t.change), bold: true),
                if (t.note.isNotEmpty) ...[Divider(height: 22), Text('Catatan: ${t.note}')],
                Divider(height: 22),
                Text('Terima kasih, semoga hari Anda menyenangkan!', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ]),
            ),
            SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50), backgroundColor: green),
              onPressed: () => printReceiptFlow(context, t, s.storeName, s.tagline),
              icon: Icon(Icons.print),
              label: Text('Cetak Struk'),
            ),
            SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(50)),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: receiptText(t, s.storeName)));
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Struk disalin')));
                  },
                  icon: Icon(Icons.copy),
                  label: Text('Salin Struk'),
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50), backgroundColor: blue),
                  onPressed: () => fresh ? Navigator.popUntil(context, (r) => r.isFirst) : Navigator.pop(context),
                  icon: Icon(fresh ? Icons.add_shopping_cart : Icons.arrow_back),
                  label: Text(fresh ? 'Transaksi Baru' : 'Kembali'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
