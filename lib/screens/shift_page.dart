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
        Text('Hitung uang tunai yang ada di laci sekarang, lalu tulis di sini sebagai uang modal awal.'),
        SizedBox(height: 12),
        TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
          decoration: InputDecoration(labelText: 'Uang modal di laci (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
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

/// Kunci kasir: selama shift belum dibuka, layar [child] (Kasir / Meja) tidak bisa dipakai.
/// [autoPrompt] = dialog "Buka Shift" langsung muncul saat aplikasi dibuka.
class ShiftGate extends StatefulWidget {
  final Widget child;
  final bool autoPrompt;
  ShiftGate({super.key, required this.child, this.autoPrompt = false});
  @override
  State<ShiftGate> createState() => _ShiftGateState();
}

class _ShiftGateState extends State<ShiftGate> {
  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (context.read<AppState>().activeShift == null) showOpenShiftDialog(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.activeShift != null) return widget.child;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 380),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(color: Color(0xFFFFF4E0), shape: BoxShape.circle),
              child: Icon(Icons.lock_outline, size: 48, color: Color(0xFFB45309)),
            ),
            SizedBox(height: 18),
            Text('Kasir terkunci', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy)),
            SizedBox(height: 8),
            Text(
              'Buka shift dulu sebelum mulai melayani pelanggan. Hitung uang tunai yang ada di laci, lalu isi sebagai uang modal awal.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700], height: 1.4),
            ),
            SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(54), backgroundColor: blue),
              onPressed: () => showOpenShiftDialog(context),
              icon: Icon(Icons.lock_open),
              label: Text('Buka Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}

const _quick = ['Kerupuk', 'Sampah', 'Es batu', 'Gas', 'Sayur', 'Lainnya'];

/// Catat uang yang keluar dari laci selama shift. Otomatis mengurangi "uang seharusnya di laci".
Future<void> showCashOutSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: _CashOutSheet(),
    ),
  );
}

class _CashOutSheet extends StatefulWidget {
  _CashOutSheet();
  @override
  State<_CashOutSheet> createState() => _CashOutSheetState();
}

class _CashOutSheetState extends State<_CashOutSheet> {
  final amount = TextEditingController();
  final label = TextEditingController();
  String chip = '';

  @override
  void dispose() {
    amount.dispose();
    label.dispose();
    super.dispose();
  }

  void _save() {
    final s = context.read<AppState>();
    final v = int.tryParse(amount.text) ?? 0;
    final name = label.text.trim().isNotEmpty ? label.text.trim() : chip;
    if (v <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Isi jumlah uang yang keluar')));
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pilih atau tulis untuk apa uang itu')));
      return;
    }
    s.addCashOut(name, v);
    setState(() {
      amount.clear();
      label.clear();
      chip = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final a = s.activeShift;
    final outs = a?.cashOuts ?? <CashOut>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Uang Keluar dari Laci', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('Catat uang laci yang dipakai (beli kerupuk, bayar sampah, dll). Jumlahnya otomatis mengurangi uang yang seharusnya ada di laci.',
              style: TextStyle(color: Colors.grey[700], fontSize: 12)),
          SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final c in _quick)
              ChoiceChip(
                label: Text(c),
                selected: chip == c,
                showCheckmark: false,
                selectedColor: blue,
                labelStyle: TextStyle(color: chip == c ? Colors.white : navy, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() => chip = c),
              ),
          ]),
          SizedBox(height: 10),
          TextField(
            controller: label,
            decoration: InputDecoration(labelText: 'Atau tulis sendiri (opsional)', border: OutlineInputBorder(), isDense: true),
          ),
          SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: 'Jumlah (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
          ),
          SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: Size.fromHeight(48)),
            onPressed: a == null ? null : _save,
            icon: Icon(Icons.add),
            label: Text('Simpan Uang Keluar'),
          ),
          if (outs.isNotEmpty) ...[
            SizedBox(height: 16),
            Text('Sudah dicatat di shift ini', style: TextStyle(fontWeight: FontWeight.w800)),
            for (var i = 0; i < outs.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(outs[i].label, style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(jam(outs[i].at)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(rp(outs[i].amount), style: TextStyle(fontWeight: FontWeight.w800)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 20), onPressed: () => s.removeCashOut(i)),
                ]),
              ),
            Divider(),
            _kv('Total uang keluar', rp(a?.cashOutTotal ?? 0), bold: true),
          ],
        ]),
      ),
    );
  }
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
          Text('Shift belum dibuka. Isi uang modal di laci sebelum mulai berjualan.')
        else
          Text('Shift berjalan sejak ${jam(a.openedAt)} (${tgl(a.openedAt)})\nUang modal di laci: ${rp(a.openingCash)}${a.cashOuts.isEmpty ? '' : '\nUang keluar: ${rp(a.cashOutTotal)}'}'),
        if (unsent > 0)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('$unsent shift belum terkirim ke bos (akan dicoba lagi otomatis).', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
          ),
        if (a != null)
          Padding(
            padding: EdgeInsets.only(top: 10),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(44)),
              onPressed: () => showCashOutSheet(context),
              icon: Icon(Icons.payments_outlined),
              label: Text('Catat Uang Keluar'),
            ),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tulis berapa uang yang ada di laci sekarang')));
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
    final out = a.cashOutTotal;
    final nonCash = s.nonCashSince(a.openedAt);
    final expected = a.openingCash + sales - out;
    final diff = counted - expected;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Tutup shift sekarang?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _kv('Uang modal awal', rp(a.openingCash)),
            _kv('Penjualan tunai', '+ ${rp(sales)}'),
            _kv('Uang keluar', '- ${rp(out)}'),
            _kv('Uang seharusnya di laci', rp(expected), bold: true),
            Divider(height: 18),
            _kv('Uang di laci (hitungan)', rp(counted), bold: true),
            _kv('Selisih', selisihText(diff), bold: true, color: diff == 0 ? green : _red),
            if (nonCash.isNotEmpty) ...[
              Divider(height: 18),
              Align(alignment: Alignment.centerLeft, child: Text('Tidak masuk laci (uang di rekening):', style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
              for (final e in nonCash.entries) _kv(e.key, rp(e.value), color: Colors.grey[700]),
            ],
          ]),
        ),
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
                  Text('Berapa uang di laci sekarang?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Hitung semua uang tunai yang ada di laci, lalu tulis totalnya di bawah. Jangan masukkan uang transfer atau QRIS.',
                      style: TextStyle(color: Colors.grey[700], fontSize: 13)),
                  SizedBox(height: 12),
                  TextField(
                    controller: cash,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    decoration: InputDecoration(labelText: 'Uang di laci (Rp)', prefixText: 'Rp ', border: OutlineInputBorder()),
                  ),
                  if (cash.text.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(rp(int.tryParse(cash.text) ?? 0), style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
                    ),
                ]),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(14),
                decoration: cardDeco(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Uang keluar dari laci', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
                    TextButton.icon(onPressed: () => showCashOutSheet(context), icon: Icon(Icons.add, size: 18), label: Text('Catat')),
                  ]),
                  if (a.cashOuts.isEmpty)
                    Text('Belum ada. Kalau tadi ada uang laci yang dipakai (kerupuk, sampah, dll), catat dulu supaya hitungannya pas.',
                        style: TextStyle(color: Colors.grey[700], fontSize: 12))
                  else ...[
                    for (final c in a.cashOuts) _kv(c.label, rp(c.amount)),
                    Divider(height: 14),
                    _kv('Total uang keluar', rp(a.cashOutTotal), bold: true),
                  ],
                ]),
              ),
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(14),
                decoration: cardDeco(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _kv('Dibuka', '${tgl(a.openedAt)} ${jam(a.openedAt)}'),
                  _kv('Kasir', s.kasir),
                  _kv('Uang modal awal', rp(a.openingCash)),
                  SizedBox(height: 10),
                  TextField(
                    controller: note,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: 'Catatan lain (opsional)', border: OutlineInputBorder()),
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
                    _kv('Uang modal awal', rp(x.openingCash)),
                    if (closed != null) ...[
                      _kv('Penjualan tunai', '+ ${rp(x.cashSales)}'),
                      _kv('Uang keluar', '- ${rp(x.cashOutTotal)}'),
                      for (final c in x.cashOuts) Padding(padding: EdgeInsets.only(left: 12), child: _kv(c.label, rp(c.amount), color: Colors.grey[700])),
                      _kv('Uang seharusnya di laci', rp(x.expectedCash)),
                      _kv('Uang di laci (hitungan)', rp(x.closingCash)),
                      _kv('Selisih', selisihText(x.difference), bold: true, color: x.difference == 0 ? green : _red),
                      for (final e in x.nonCash.entries) _kv('${e.key} (tidak masuk laci)', rp(e.value), color: Colors.grey[700]),
                      if (x.note.isNotEmpty) Padding(padding: EdgeInsets.only(top: 4), child: Text('Catatan: ${x.note}', style: TextStyle(color: Colors.grey[700], fontSize: 12))),
                    ],
                  ]),
                );
              },
            ),
    );
  }
}
