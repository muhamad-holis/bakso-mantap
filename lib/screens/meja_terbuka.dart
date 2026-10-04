import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'payment_page.dart';
import 'printer_page.dart';

/// Lama sejak [d], mis. '12 mnt' atau '1 j 5 mnt'.
String lamaSejak(DateTime d) {
  final m = DateTime.now().difference(d).inMinutes;
  if (m < 1) return 'baru saja';
  if (m < 60) return '$m mnt';
  return '${m ~/ 60} j ${m % 60} mnt';
}

/// Daftar meja yang belum bayar di cabang ini (pelanggan makan dulu, bayar belakangan).
class MejaTerbukaPage extends StatefulWidget {
  MejaTerbukaPage({super.key});
  @override
  State<MejaTerbukaPage> createState() => _MejaTerbukaPageState();
}

class _MejaTerbukaPageState extends State<MejaTerbukaPage> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppState>().refreshOpenOrders();
    });
    _t = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) context.read<AppState>().refreshOpenOrders();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<bool> _load(BuildContext context, AppState s, OpenOrder o) async {
    if (s.cart.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text('Ganti keranjang?'),
          content: Text('Keranjang yang sedang diisi akan dikosongkan dan diganti dengan pesanan Meja ${o.tableNo}.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Ya, Ganti')),
          ],
        ),
      );
      if (ok != true) return false;
    }
    s.loadOrderToCart(o);
    return true;
  }

  void _detail(BuildContext context, AppState s, OpenOrder o) {
    final total = s.orderTotal(o);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Meja ${o.tableNo}${o.customerName.isEmpty ? '' : ' • ${o.customerName}'}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text('Dibuka ${jam(o.createdAt)} (${lamaSejak(o.createdAt)}) oleh ${o.kasir.isEmpty ? '-' : o.kasir}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            SizedBox(height: 8),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final l in o.lines)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${l.qty} x ${l.name}', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: _sub(o, l),
                    trailing: Text(rp(l.price * l.qty), style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            Divider(),
            _kv('Subtotal', rp(o.subtotal)),
            _kv('Pajak', rp(total - o.subtotal)),
            _kv('Total', rp(total), bold: true),
            SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                  onPressed: () async {
                    if (!await _load(context, s, o)) return;
                    if (d.mounted) Navigator.pop(d);
                    s.tabRequest.value = 0;
                  },
                  icon: Icon(Icons.add),
                  label: Text('Tambah'),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: Size.fromHeight(48), backgroundColor: green),
                  onPressed: () async {
                    if (!await _load(context, s, o)) return;
                    if (d.mounted) Navigator.pop(d);
                    if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentPage()));
                  },
                  icon: Icon(Icons.payments_outlined),
                  label: Text('Bayar'),
                ),
              ),
              SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Cetak rincian pesanan',
                onPressed: () => printKitchenFlow(context, o, o.lines, title: 'RINCIAN PESANAN'),
                icon: Icon(Icons.print),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget? _sub(OpenOrder o, OpenLine l) {
    final parts = <String>[
      if (l.note.isNotEmpty) 'Catatan: ${l.note}',
      if (o.isExtra(l)) 'Tambahan ${l.addedAt == null ? '' : jam(l.addedAt!)}${l.addedBy.isEmpty ? '' : ' • ${l.addedBy}'}',
    ];
    return parts.isEmpty ? null : Text(parts.join('\n'), style: TextStyle(fontSize: 12));
  }

  Widget _kv(String a, String b, {bool bold = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.openOrders;
    final sum = list.fold<int>(0, (a, o) => a + s.orderTotal(o));
    return RefreshIndicator(
      onRefresh: s.refreshOpenOrders,
      child: ListView(physics: AlwaysScrollableScrollPhysics(), padding: EdgeInsets.all(12), children: [
        Container(
          padding: EdgeInsets.all(14),
          decoration: cardDeco(color: Color(0xFFFFF4E0)),
          child: Row(children: [
            Icon(Icons.table_restaurant, color: Color(0xFFB45309)),
            SizedBox(width: 10),
            Expanded(child: Text('Meja belum bayar: ${list.length}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            Text(rp(sum), style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7A3E00))),
          ]),
        ),
        SizedBox(height: 10),
        if (s.openOrdersError != null)
          Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(s.openOrdersError!, style: TextStyle(color: Color(0xFFC62828), fontSize: 12)),
          ),
        if (list.isEmpty && s.openOrdersError == null)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Text(
              'Tidak ada meja yang belum bayar.\nSimpan pesanan dari tab Kasir untuk pelanggan yang makan dulu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        for (final o in list)
          Container(
            margin: EdgeInsets.only(bottom: 8),
            decoration: cardDeco(),
            child: ListTile(
              onTap: () => _detail(context, s, o),
              leading: CircleAvatar(backgroundColor: navy, child: Text(o.tableNo, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
              title: Text(o.customerName.isEmpty ? 'Meja ${o.tableNo}' : '${o.customerName} • Meja ${o.tableNo}', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${o.itemCount} item • sejak ${jam(o.createdAt)} (${lamaSejak(o.createdAt)})'),
              trailing: Text(rp(s.orderTotal(o)), style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}
