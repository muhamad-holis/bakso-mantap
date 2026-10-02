import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'receipt_page.dart';

class PaymentPage extends StatefulWidget {
  PaymentPage({super.key});
  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String method = 'Tunai';
  String input = '';
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  int _paid(AppState s) => method == 'Tunai' ? (int.tryParse(input) ?? 0) : s.total;

  void _press(String d) {
    if (input.isEmpty && d.startsWith('0')) return;
    if (input.length + d.length > 9) return;
    setState(() => input += d);
  }

  void _process(AppState s) {
    final t = s.checkout(method: method, paid: _paid(s), note: note.text.trim());
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t, fresh: true)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // keranjang kosong (mis. setelah checkout) -> tampilkan kosong saja
    final total = s.total;
    final paid = _paid(s);
    final ok = total > 0 && paid >= total;

    final left = Column(children: [_totalCard(s), SizedBox(height: 12), _methodCard(), if (method == 'Tunai') ...[SizedBox(height: 12), _cashCard(s, paid)]]);
    final right = Column(children: [
      if (method == 'Tunai') ...[_keypad(s, ok), SizedBox(height: 12)],
      _rincian(s, paid),
      SizedBox(height: 12),
      _noteCard(),
      SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: ok ? () => _process(s) : null,
          icon: Icon(Icons.check_circle_outline),
          label: Text('Proses Pembayaran', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
      ),
    ]);

    return Scaffold(
      appBar: AppBar(title: Text('Pembayaran'), backgroundColor: navy, foregroundColor: Colors.white),
      body: LayoutBuilder(builder: (c, box) {
        if (box.maxWidth >= 800) {
          return Padding(
            padding: EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: SingleChildScrollView(child: left)),
              SizedBox(width: 12),
              Expanded(child: SingleChildScrollView(child: right)),
            ]),
          );
        }
        return ListView(padding: EdgeInsets.all(12), children: [left, SizedBox(height: 12), right]);
      }),
    );
  }

  Widget _totalCard(AppState s) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(16),
        decoration: cardDeco(color: Color(0xFFEAF1FC)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Total Tagihan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(rp(s.total), style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: navy)),
          SizedBox(height: 4),
          Text('${s.itemCount} Item', style: TextStyle(color: Colors.grey[700])),
        ]),
      );

  Widget _methodCard() {
    final ms = [
      ['Tunai', Icons.payments_outlined],
      ['QRIS', Icons.qr_code_2],
      ['Transfer', Icons.account_balance],
      ['Non Tunai', Icons.credit_card],
    ];
    return Row(children: [
      for (final m in ms)
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                method = m[0] as String;
                input = '';
              }),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: method == m[0] ? Color(0xFFE6EEFB) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: method == m[0] ? blue : lineColor, width: method == m[0] ? 2 : 1),
                ),
                child: Column(children: [
                  Icon(m[1] as IconData, color: navy),
                  SizedBox(height: 6),
                  Text(m[0] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _cashCard(AppState s, int paid) {
    final quick = [10000, 20000, 50000, 100000];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Nominal Diterima', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: blue)),
          child: Text(rp(paid), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        ),
        SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(label: Text('Uang Pas'), onPressed: () => setState(() => input = '${s.total}')),
          for (final q in quick) ActionChip(label: Text(rp(q)), onPressed: () => setState(() => input = '$q')),
        ]),
      ]),
    );
  }

  Widget _key(String t, VoidCallback? onTap, {Color color = navy, double h = 52, Widget? child}) => Expanded(
        child: Padding(
          padding: EdgeInsets.all(3),
          child: SizedBox(
            height: h,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Color(0xFFB8C7DE),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: EdgeInsets.zero,
              ),
              onPressed: onTap,
              child: child ?? Text(t, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  Widget _keypad(AppState s, bool ok) {
    Widget d(String t) => _key(t, () => _press(t));
    return Container(
      padding: EdgeInsets.all(8),
      decoration: cardDeco(),
      child: Column(children: [
        Row(children: [
          d('7'), d('8'), d('9'),
          _key('', input.isEmpty ? null : () => setState(() => input = input.substring(0, input.length - 1)),
              color: navy2, child: Icon(Icons.backspace_outlined)),
        ]),
        Row(children: [
          d('4'), d('5'), d('6'),
          _key('C', () => setState(() => input = ''), color: navy2),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Column(children: [
              Row(children: [d('1'), d('2'), d('3')]),
              Row(children: [d('0'), d('00'), d('000')]),
            ]),
          ),
          _key('OK', ok ? () => _process(s) : null, color: blue, h: 110),
        ]),
      ]),
    );
  }

  Widget _rincian(AppState s, int paid) {
    final kurang = paid < s.total;
    Widget row(String a, String b, {Color? bg, Color? fg, bool bold = false}) => Container(
          margin: EdgeInsets.symmetric(vertical: 3),
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: fg, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(b, style: TextStyle(color: fg, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 18 : 15)),
          ]),
        );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Rincian', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        row('Total Belanja', rp(s.total)),
        row('$method Diterima', rp(paid)),
        if (kurang)
          row('Kurang', rp(s.total - paid), bg: Color(0xFFFDECEC), fg: Color(0xFFC62828), bold: true)
        else
          row('Kembalian', rp(paid - s.total), bg: Color(0xFFDCF5E3), fg: Color(0xFF14753A), bold: true),
      ]),
    );
  }

  Widget _noteCard() => Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Catatan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Contoh: tanpa sambal, extra kerupuk, dll...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
      );
}
