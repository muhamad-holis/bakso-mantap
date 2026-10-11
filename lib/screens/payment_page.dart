import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models.dart';
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
  // Pembayaran gabungan (mis. Tunai + QRIS pada satu nota)
  final List<PayPart> parts = [];
  String partMethod = 'Tunai';
  final note = TextEditingController();

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  int _paid(AppState s) => method == 'Gabungan'
      ? parts.fold<int>(0, (a, p) => a + p.tendered)
      : method == 'Tunai'
          ? (int.tryParse(input) ?? 0)
          : s.total;

  /// Sisa tagihan yang belum tertutup oleh bagian-bagian pembayaran gabungan.
  int _sisa(AppState s) => s.total - parts.fold<int>(0, (a, p) => a + p.amount);

  bool _canAdd(AppState s) {
    final amt = int.tryParse(input) ?? 0;
    final sisa = _sisa(s);
    if (sisa <= 0 || amt <= 0) return false;
    if (partMethod != 'Tunai' && amt > sisa) return false; // QRIS/Transfer/Non Tunai harus pas, tanpa kembalian
    return true;
  }

  void _addPart(AppState s) {
    if (!_canAdd(s)) return;
    final amt = int.tryParse(input) ?? 0;
    final sisa = _sisa(s);
    final net = partMethod == 'Tunai' ? (amt > sisa ? sisa : amt) : amt;
    final i = parts.indexWhere((p) => p.method == partMethod);
    setState(() {
      if (i >= 0) {
        final o = parts[i];
        parts[i] = PayPart(partMethod, o.amount + net, o.tendered + amt);
      } else {
        parts.add(PayPart(partMethod, net, amt));
      }
      input = '';
    });
  }

  void _press(String d) {
    if (input.isEmpty && d.startsWith('0')) return;
    if (input.length + d.length > 9) return;
    setState(() => input += d);
  }

  void _process(AppState s) {
    if (s.newOrderOnTakenTable) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Meja ${s.tableNo} sudah terisi. Buka pesanannya dari tab Meja.')));
      Navigator.pop(context);
      return;
    }
    if (s.activeShift == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Buka shift dulu sebelum menerima pembayaran')));
      Navigator.pop(context);
      return;
    }
    final split = method == 'Gabungan';
    final t = s.checkout(
      method: split ? parts.map((p) => p.method).join(' + ') : method,
      paid: _paid(s),
      note: note.text.trim(),
      payments: split ? List<PayPart>.from(parts) : const [],
    );
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t, fresh: true)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // keranjang kosong (mis. setelah checkout) -> tampilkan kosong saja
    final total = s.total;
    final paid = _paid(s);
    final ok = method == 'Gabungan' ? (total > 0 && _sisa(s) <= 0 && parts.length >= 2) : (total > 0 && paid >= total);

    final left = Column(children: [
      _totalCard(s),
      SizedBox(height: 12),
      _methodCard(),
      if (method == 'Tunai') ...[SizedBox(height: 12), _cashCard(s, paid)],
      if (method == 'QRIS') ...[SizedBox(height: 12), _qrisCard(s)],
      if (method == 'Transfer') ...[SizedBox(height: 12), _transferCard(s)],
      if (method == 'Gabungan') ...[
        SizedBox(height: 12),
        _splitCard(s),
        if (_sisa(s) > 0 && partMethod == 'QRIS') ...[SizedBox(height: 12), _qrisCard(s, int.tryParse(input) ?? _sisa(s))],
        if (_sisa(s) > 0 && partMethod == 'Transfer') ...[SizedBox(height: 12), _transferCard(s, int.tryParse(input) ?? _sisa(s))],
      ],
    ]);
    final right = Column(children: [
      if (method == 'Tunai') ...[_keypad(s, ok), SizedBox(height: 12)],
      if (method == 'Gabungan' && _sisa(s) > 0) ...[_keypad(s, _canAdd(s)), SizedBox(height: 12)],
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
      ['Gabungan', Icons.call_split],
    ];
    return Row(children: [
      for (final m in ms)
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() {
                method = m[0] as String;
                input = '';
                if (method != 'Gabungan') parts.clear();
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
                  Text(m[0] as String, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }

  void _zoomQris(String url) => showDialog(
        context: context,
        builder: (d) => Dialog(
          backgroundColor: Colors.white,
          insetPadding: EdgeInsets.all(12),
          child: Stack(children: [
            InteractiveViewer(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
            Positioned(right: 0, top: 0, child: IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(d))),
          ]),
        ),
      );

  Widget _notSet(String msg) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(color: Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(10)),
        child: Text(msg, style: TextStyle(color: Color(0xFF7A3E00), fontWeight: FontWeight.w600)),
      );

  Widget _qrisCard(AppState s, [int? amount]) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(children: [
        Text('Scan QRIS untuk membayar', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text(rp(amount ?? s.total), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy)),
        SizedBox(height: 10),
        if (s.qrisUrl.isEmpty)
          _notSet('Gambar QRIS belum diatur oleh bos.')
        else
          InkWell(
            onTap: () => _zoomQris(s.qrisUrl),
            child: Container(
              color: Colors.white,
              constraints: BoxConstraints(maxHeight: 380),
              child: CachedNetworkImage(
                imageUrl: s.qrisUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => _notSet('Gambar QRIS belum bisa dimuat. Periksa koneksi internet.'),
              ),
            ),
          ),
        if (s.qrisUrl.isNotEmpty) Padding(padding: EdgeInsets.only(top: 6), child: Text('Ketuk gambar untuk memperbesar', style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
      ]),
    );
  }

  Widget _transferCard(AppState s, [int? amount]) {
    final has = s.bankAccount.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Transfer ke rekening', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text(rp(amount ?? s.total), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: navy)),
        SizedBox(height: 10),
        if (!has)
          _notSet('Nomor rekening belum diatur oleh bos.')
        else ...[
          if (s.bankName.isNotEmpty) Text(s.bankName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.grey[800])),
          Row(children: [
            Expanded(child: SelectableText(s.bankAccount, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 1))),
            IconButton(
              tooltip: 'Salin nomor rekening',
              icon: Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: s.bankAccount));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Nomor rekening disalin')));
              },
            ),
          ]),
          if (s.bankHolder.isNotEmpty) Text('a.n. ${s.bankHolder}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ]),
    );
  }

  Widget _splitCard(AppState s) {
    final sisa = _sisa(s);
    final amt = int.tryParse(input) ?? 0;
    final methods = ['Tunai', 'QRIS', 'Transfer', 'Non Tunai'];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pembayaran Gabungan', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        SizedBox(height: 4),
        Text('Tambahkan pembayaran satu per satu sampai sisa tagihan Rp 0.', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        SizedBox(height: 10),
        if (parts.isNotEmpty) ...[
          for (var i = 0; i < parts.length; i++)
            Container(
              margin: EdgeInsets.only(bottom: 6),
              padding: EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(color: Color(0xFFE6F6EC), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.check_circle, size: 18, color: green),
                SizedBox(width: 8),
                Expanded(child: Text(parts[i].method, style: TextStyle(fontWeight: FontWeight.w700))),
                Text(rp(parts[i].amount), style: TextStyle(fontWeight: FontWeight.w800)),
                IconButton(
                  tooltip: 'Hapus',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => parts.removeAt(i)),
                ),
              ]),
            ),
          SizedBox(height: 4),
        ],
        Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: sisa > 0 ? Color(0xFFFFF4E0) : Color(0xFFDCF5E3), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(child: Text(sisa > 0 ? 'Sisa tagihan' : 'Tagihan lunas', style: TextStyle(fontWeight: FontWeight.w700))),
            Text(rp(sisa > 0 ? sisa : 0), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: sisa > 0 ? Color(0xFF7A3E00) : Color(0xFF14753A))),
          ]),
        ),
        if (sisa > 0) ...[
          SizedBox(height: 12),
          Text('Bayar dengan', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final m in methods)
              ChoiceChip(
                label: Text(m),
                selected: partMethod == m,
                showCheckmark: false,
                selectedColor: blue,
                labelStyle: TextStyle(color: partMethod == m ? Colors.white : navy, fontWeight: FontWeight.w600),
                onSelected: (_) => setState(() {
                  partMethod = m;
                  input = '';
                }),
              ),
          ]),
          SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: blue)),
            child: Text(amt == 0 ? 'Ketik nominal $partMethod' : rp(amt), style: TextStyle(fontSize: amt == 0 ? 14 : 22, fontWeight: FontWeight.w800, color: amt == 0 ? Colors.grey : null)),
          ),
          SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            ActionChip(label: Text('Sisa ${rp(sisa)}'), onPressed: () => setState(() => input = '$sisa')),
            if (partMethod == 'Tunai') for (final q in [50000, 100000]) ActionChip(label: Text(rp(q)), onPressed: () => setState(() => input = '$q')),
          ]),
          if (partMethod != 'Tunai' && amt > sisa)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Nominal $partMethod tidak boleh lebih dari sisa tagihan.', style: TextStyle(color: Color(0xFFC62828), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: Size.fromHeight(46), backgroundColor: blue),
            onPressed: _canAdd(s) ? () => _addPart(s) : null,
            icon: Icon(Icons.add),
            label: Text('Tambah Pembayaran'),
          ),
        ] else if (parts.length < 2)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Gabungan butuh minimal 2 metode. Hapus salah satu lalu isi nominal yang lebih kecil, atau pilih metode biasa.', style: TextStyle(color: Color(0xFFC62828), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
      ]),
    );
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
          _key('OK', ok ? () => (method == 'Gabungan' ? _addPart(s) : _process(s)) : null, color: blue, h: 110),
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
        if (method == 'Gabungan') ...[
          for (final x in parts) row('${x.method} diterima', rp(x.tendered)),
          row('Total diterima', rp(paid)),
        ] else
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
          Text('Catatan Transaksi (umum)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          SizedBox(height: 8),
          TextField(
            controller: note,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Catatan untuk seluruh pesanan (opsional). Catatan per item diisi di keranjang.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
      );
}
