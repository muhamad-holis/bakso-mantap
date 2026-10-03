import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'payment_page.dart';
import 'shift_page.dart';

class KasirPage extends StatefulWidget {
  KasirPage({super.key});
  @override
  State<KasirPage> createState() => _KasirPageState();
}

class _KasirPageState extends State<KasirPage> {
  String cat = 'Semua';
  String q = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final wide = MediaQuery.of(context).size.width >= 900;
    final cats = s.categories;
    if (!cats.contains(cat)) cat = 'Semua';
    final list = s.menus
        .where((m) => (cat == 'Semua' || m.category == cat) && m.name.toLowerCase().contains(q.toLowerCase()))
        .toList();

    final left = Padding(
      padding: EdgeInsets.all(12),
      child: Column(children: [
        if (s.activeShift == null)
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Material(
              color: Color(0xFFFFF4E0),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => showOpenShiftDialog(context),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.lock_open, size: 18, color: Color(0xFFB45309)),
                    SizedBox(width: 8),
                    Expanded(child: Text('Shift belum dibuka. Ketuk untuk isi kas awal.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7A3E00)))),
                    Icon(Icons.chevron_right, size: 18, color: Color(0xFFB45309)),
                  ]),
                ),
              ),
            ),
          ),
        TextField(
          onChanged: (v) => setState(() => q = v),
          decoration: InputDecoration(
            hintText: 'Cari menu...',
            prefixIcon: Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.symmetric(vertical: 0),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: lineColor)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: lineColor)),
          ),
        ),
        SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final c in cats)
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(c),
                  selected: cat == c,
                  showCheckmark: false,
                  selectedColor: blue,
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(color: cat == c ? Colors.white : navy, fontWeight: FontWeight.w600),
                  shape: StadiumBorder(side: BorderSide(color: lineColor)),
                  onSelected: (_) => setState(() => cat = c),
                ),
              ),
          ]),
        ),
        SizedBox(height: 10),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('Menu tidak ditemukan'))
              : GridView.builder(
                  itemCount: list.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 190,
                    childAspectRatio: 0.82,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                  ),
                  itemBuilder: (c, i) => _MenuCard(item: list[i], qty: s.qtyOf(list[i].id)),
                ),
        ),
      ]),
    );

    if (wide) {
      return Row(children: [
        Expanded(child: left),
        SizedBox(width: 370, child: Padding(padding: EdgeInsets.fromLTRB(0, 12, 12, 12), child: CartPanel())),
      ]);
    }
    return Column(children: [
      Expanded(child: left),
      if (s.cart.isNotEmpty)
        Material(
          color: blue,
          child: InkWell(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CartPage())),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Icon(Icons.shopping_cart, color: Colors.white),
                SizedBox(width: 10),
                Text('${s.itemCount} item', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                Spacer(),
                Text(rp(s.subtotal), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: Colors.white),
              ]),
            ),
          ),
        ),
    ]);
  }
}

class _MenuCard extends StatelessWidget {
  final MenuItem item;
  final int qty;
  _MenuCard({required this.item, required this.qty});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => context.read<AppState>().addToCart(item),
      child: Container(
        decoration: cardDeco(),
        padding: EdgeInsets.all(6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: MenuImage(item))),
              if (qty > 0)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: blue, borderRadius: BorderRadius.circular(12)),
                    child: Text('$qty', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
          SizedBox(height: 6),
          Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          SizedBox(height: 2),
          Row(children: [
            Expanded(child: Text(rp(item.price), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(color: blue, shape: BoxShape.circle),
              child: Icon(Icons.add, color: Colors.white, size: 20),
            ),
          ]),
        ]),
      ),
    );
  }
}

class CartPage extends StatelessWidget {
  CartPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Keranjang'), backgroundColor: navy, foregroundColor: Colors.white),
      body: Padding(padding: EdgeInsets.all(12), child: CartPanel()),
    );
  }
}

class CartPanel extends StatefulWidget {
  CartPanel({super.key});
  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: context.read<AppState>().customerName);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    // setelah checkout / hapus semua, nama pelanggan di state kosong -> kosongkan kolom juga
    if (s.customerName.isEmpty && _name.text.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && context.read<AppState>().customerName.isEmpty) _name.clear();
      });
    }
    return Container(
      decoration: cardDeco(),
      child: Column(children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(children: [
            Text('Keranjang', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Spacer(),
            TextButton.icon(
              onPressed: s.cart.isEmpty ? null : s.clearCart,
              icon: Icon(Icons.delete_outline, color: s.cart.isEmpty ? Colors.grey : Colors.red, size: 18),
              label: Text('Hapus Semua', style: TextStyle(color: s.cart.isEmpty ? Colors.grey : Colors.red)),
            ),
          ]),
        ),
        Divider(height: 1),
        Expanded(
          child: ListView(padding: EdgeInsets.all(10), children: [
            _orderInfo(s),
            if (s.cart.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Keranjang kosong\nKetuk menu untuk menambah', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
              )
            else
              for (final l in s.cart.values) _line(context, s, l),
          ]),
        ),
        Padding(
          padding: EdgeInsets.all(12),
          child: Column(children: [
            _row('${s.itemCount} Item', rp(s.subtotal)),
            InkWell(
              onTap: (s.cart.isEmpty || cloudEnabled) ? null : () => _discountDialog(context, s),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: _row(cloudEnabled ? 'Diskon' : 'Diskon (ketuk untuk ubah)', rp(s.discount)),
              ),
            ),
            _row('Pajak (PPN ${s.taxPercent}%)', rp(s.tax)),
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(color: Color(0xFFE6EEFB), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Text('Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
                Spacer(),
                Text(rp(s.total), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: blue)),
              ]),
            ),
            SizedBox(height: 10),
            if (s.cart.isNotEmpty && !s.orderReady)
              Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Pilih nomor meja dulu (atau pilih Bawa Pulang)', style: TextStyle(color: Color(0xFFC62828), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: (s.cart.isEmpty || !s.orderReady) ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage())),
                icon: Text('Checkout', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                label: Icon(Icons.arrow_forward),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _orderInfo(AppState s) {
    final takeaway = s.orderType == orderTakeaway;
    Widget type(String label, IconData icon) {
      final sel = s.orderType == label;
      return Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => s.setOrderType(label),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: sel ? Color(0xFFE6EEFB) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? blue : lineColor, width: sel ? 2 : 1),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: navy),
                SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(8),
      decoration: cardDeco(color: Color(0xFFFAFCFF)),
      child: Column(children: [
        Row(children: [type(orderDineIn, Icons.restaurant), type(orderTakeaway, Icons.shopping_bag_outlined)]),
        if (!takeaway) ...[
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 3),
            child: Row(children: [
              SizedBox(
                width: 118,
                child: DropdownButtonFormField<String>(
                  value: (s.tableNo.isEmpty || (int.tryParse(s.tableNo) ?? 0) > s.tableCount) ? null : s.tableNo,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'No. Meja',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  hint: Text('Pilih'),
                  items: [for (var i = 1; i <= s.tableCount; i++) DropdownMenuItem(value: '$i', child: Text('Meja $i'))],
                  onChanged: (v) => s.setTableNo(v ?? ''),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  onChanged: s.setCustomerName,
                  decoration: InputDecoration(
                    labelText: 'Nama pelanggan',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: Color(0xFF44546A)))),
          Text(b, style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _qty(IconData i, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(color: Color(0xFFE6EEFB), borderRadius: BorderRadius.circular(8)),
          child: Icon(i, size: 18, color: blue),
        ),
      );

  Widget _line(BuildContext context, AppState s, CartLine l) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(8),
      decoration: cardDeco(color: Color(0xFFFAFCFF)),
      child: Row(children: [
        ClipRRect(borderRadius: BorderRadius.circular(8), child: MenuImage(l.item, size: 56)),
        SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
            Text(rp(l.item.price), style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            SizedBox(height: 4),
            Row(children: [
              _qty(Icons.remove, () => s.dec(l.key)),
              SizedBox(width: 30, child: Text('${l.qty}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700))),
              _qty(Icons.add, () => s.inc(l.key)),
            ]),
            InkWell(
              onTap: () => _noteDialog(context, s, l),
              child: Padding(
                padding: EdgeInsets.only(top: 6, bottom: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(l.note.isEmpty ? Icons.edit_note : Icons.sticky_note_2_outlined, size: 16, color: l.note.isEmpty ? blue : Color(0xFFB45309)),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      l.note.isEmpty ? 'Tambah catatan' : l.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: l.note.isEmpty ? blue : Color(0xFFB45309)),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          InkWell(onTap: () => s.remove(l.key), child: Icon(Icons.close, size: 18, color: Colors.grey)),
          SizedBox(height: 22),
          Text(rp(l.total), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ]),
    );
  }

  Future<void> _noteDialog(BuildContext context, AppState s, CartLine l) async {
    final c = TextEditingController(text: l.note);
    var n = l.qty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text('Catatan • ${l.item.name}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: c,
                autofocus: true,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: 'Contoh: tanpa sambal'),
              ),
              Wrap(spacing: 6, children: [
                for (final q in ['Tanpa sambal', 'Pedas', 'Tanpa seledri', 'Kuah dipisah'])
                  ActionChip(label: Text(q, style: TextStyle(fontSize: 12)), onPressed: () => c.text = q),
              ]),
              if (l.qty > 1) ...[
                SizedBox(height: 12),
                Text('Berlaku untuk berapa porsi?', style: TextStyle(fontWeight: FontWeight.w600)),
                Row(children: [
                  IconButton(icon: Icon(Icons.remove_circle_outline), onPressed: n > 1 ? () => setS(() => n--) : null),
                  Text('$n dari ${l.qty}', style: TextStyle(fontWeight: FontWeight.w700)),
                  IconButton(icon: Icon(Icons.add_circle_outline), onPressed: n < l.qty ? () => setS(() => n++) : null),
                ]),
              ],
            ]),
          ),
          actions: [
            if (l.note.isNotEmpty)
              TextButton(
                onPressed: () {
                  c.clear();
                  Navigator.pop(d, true);
                },
                child: Text('Hapus', style: TextStyle(color: Colors.red)),
              ),
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok == true) s.setLineNote(l.key, c.text, n);
  }

  Future<void> _discountDialog(BuildContext context, AppState s) async {
    final c = TextEditingController(text: s.discount == 0 ? '' : '${s.discount}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Diskon (Rp)'),
        content: TextField(controller: c, keyboardType: TextInputType.number, autofocus: true, decoration: InputDecoration(hintText: '0')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Simpan')),
        ],
      ),
    );
    if (ok == true) s.setDiscount(int.tryParse(c.text) ?? 0);
  }
}
