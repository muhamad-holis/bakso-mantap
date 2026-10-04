import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

const _red = Color(0xFFC62828);

/// Dialog isi kas awal untuk membuka shift.
Future<void> showOpenShiftDialog(BuildContext context) async {
  final s = context.read<AppState>();
  final c = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text('Buka Shift'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hitung uang tunai di laci, lalu isi sebagai kas awal.'),
        SizedBox(height: 12),
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          decoration: InputDecoration(labelText: 'Kas awal (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Buka Shift')),
      ],
    ),
  );
  if (ok == true) s.startShift(int.tryParse(c.text) ?? 0);
}

Widget _kv(String a, String b, {Color? color, bool bold = false}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(a, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
        Text(b, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
      ]),
    );

/// Kartu ringkas shift di tab Akun / Pengaturan.
class ShiftCard extends StatelessWidget {
  ShiftCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.activeShift;
    final unsent = cloudEnabled ? s.shifts.where((x) => !x.isOpen && !x.synced).length : 0;
    return Container(
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Shift Kasir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        if (a == null)
          Text('Shift belum dibuka. Isi kas awal sebelum mulai berjualan.')
        else
          Text('Shift berjalan sejak ${jam(a.openedAt)} (${tgl(a.openedAt)})\nKas awal: ${rp(a.openingCash)}'),
        if (unsent > 0)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('$unsent shift belum terkirim ke bos (akan dicoba lagi otomatis).', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
          ),
        SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: a == null
                ? FilledButton.icon(onPressed: () => showOpenShiftDialog(context), icon: Icon(Icons.lock_open), label: Text('Buka Shift'))
                : FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _red),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TutupShiftPage())),
                    icon: Icon(Icons.lock_outline),
                    label: Text('Tutup Shift'),
                  ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShiftHistoryPage())),
              icon: Icon(Icons.history),
              label: FittedBox(fit: BoxFit.scaleDown, child: Text('Riwayat Shift', maxLines: 1)),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Tutup shift: kasir mengisi kas akhir (hasil hitung uang), sistem menghitung selisihnya.
class TutupShiftPage extends StatefulWidget {
  TutupShiftPage({super.key});
  @override
  State<TutupShiftPage> createState() => _TutupShiftPageState();
}

class _TutupShiftPageState extends State<TutupShiftPage> {
  final cash = TextEditingController();
  final note = TextEditingController();

  @override
  void dispose() {
    cash.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.read<AppState>();
    final a = s.activeShift;
    if (a == null) {
      Navigator.pop(context);
      return;
    }
    final counted = int.tryParse(cash.text);
    if (counted == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Isi kas akhir (hasil hitung uang di laci)')));
      return;
    }
    await s.refreshOpenOrders();
    if (!mounted) return;
    if (s.openOrders.isNotEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Masih ada meja belum bayar'),
          content: Text('Meja: ${s.openOrders.map((o) => o.tableNo).join(', ')}\n\nSelesaikan pembayarannya dulu. Pesanan yang dibayar setelah shift ditutup akan masuk shift berikutnya.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Kembali')),
            TextButton(onPressed: () => Navigator.pop(d, true), child: Text('Tetap Tutup Shift', style: TextStyle(color: _red))),
          ],
        ),
      );
      if (go != true || !mounted) return;
    }
    final sales = s.cashSalesSince(a.openedAt);
    final expected = a.openingCash + sales;
    final diff = counted - expected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Tutup shift sekarang?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _kv('Kas awal', rp(a.openingCash)),
          _kv('Tunai masuk (sistem)', rp(sales)),
          _kv('Kas seharusnya', rp(expected), bold: true),
          Divider(height: 18),
          _kv('Kas akhir (hitungan)', rp(counted), bold: true),
          _kv('Selisih', selisihText(diff), bold: true, color: diff == 0 ? green : _red),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Periksa lagi')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Ya, Tutup Shift')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final closed = s.endShift(counted, note.text);
    if (closed == null) return;
    final m = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    m.showSnackBar(SnackBar(content: Text('Shift ditutup • ${selisihText(closed.difference)}')));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.activeShift;
    return Scaffold(
      appBar: AppBar(title: Text('Tutup Shift'), backgroundColor: navy, foregroundColor: Colors.white),
      body: a == null
          ? Center(child: Text('Tidak ada shift yang berjalan'))
          : ListView(padding: EdgeInsets.all(12), children: [
              Container(
                padding: EdgeInsets.all(14),
                decoration: cardDeco(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Shift berjalan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  _kv('Dibuka', '${tgl(a.openedAt)} ${jam(a.openedAt)}'),
                  _kv('Kasir', s.kasir),
                  _kv('Kas awal', rp(a.openingCash)),
                ]),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(14),
                decoration: cardDeco(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hitung uang tunai di laci', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  SizedBox(height: 10),
                  TextField(
                    controller: cash,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: 'Kas akhir (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
                  ),
                  if (cash.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(rp(int.tryParse(cash.text) ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
                    ),
                  SizedBox(height: 12),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: 'Catatan shift (opsional)', border: OutlineInputBorder()),
                  ),
                  SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _red, minimumSize: Size.fromHeight(50)),
                    onPressed: _submit,
                    icon: Icon(Icons.lock_outline),
                    label: Text('Tutup Shift'),
                  ),
                ]),
              ),
            ]),
    );
  }
}

class ShiftHistoryPage extends StatelessWidget {
  ShiftHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.shifts;
    return Scaffold(
      appBar: AppBar(title: Text('Riwayat Shift'), backgroundColor: navy, foregroundColor: Colors.white),
      body: list.isEmpty
          ? Center(child: Text('Belum ada riwayat shift', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (c, i) {
                final x = list[i];
                final closed = x.closedAt;
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(14),
                  decoration: cardDeco(),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          '${tgl(x.openedAt)}  ${jam(x.openedAt)} – ${closed == null ? 'berjalan' : jam(closed)}',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (cloudEnabled && closed != null) Icon(x.synced ? Icons.cloud_done : Icons.cloud_upload_outlined, size: 20, color: x.synced ? green : Colors.orange),
                    ]),
                    SizedBox(height: 6),
                    _kv('Kas awal', rp(x.openingCash)),
                    if (closed != null) ...[
                      _kv('Tunai masuk (sistem)', rp(x.cashSales)),
                      _kv('Kas seharusnya', rp(x.expectedCash)),
                      _kv('Kas akhir (hitungan)', rp(x.closingCash)),
                      _kv('Selisih', selisihText(x.difference), bold: true, color: x.difference == 0 ? green : _red),
                      if (x.note.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text('Catatan: ${x.note}', style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                    ],
                  ]),
                );
              },
            ),
    );
  }
}
