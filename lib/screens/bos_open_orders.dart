import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cloud.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'meja_terbuka.dart' show lamaSejak;

/// Bos: daftar meja yang belum bayar (semua cabang atau cabang terpilih). Bos bisa membatalkan pesanan.
class BosOpenOrders extends StatefulWidget {
  final String branch; // 'Semua Cabang' = semua
  BosOpenOrders({super.key, required this.branch});
  @override
  State<BosOpenOrders> createState() => _BosOpenOrdersState();
}

class _BosOpenOrdersState extends State<BosOpenOrders> {
  List<OpenOrder> list = [];
  String? error;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _load();
    _t = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void didUpdateWidget(covariant BosOpenOrders old) {
    super.didUpdateWidget(old);
    if (old.branch != widget.branch) _load();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var q = sb.from('open_orders').select().eq('status', 'open');
      if (widget.branch != 'Semua Cabang') q = q.eq('branch', widget.branch);
      final r = await q.order('created_at');
      final l = [for (final e in r) OpenOrder.fromCloud(Map<String, dynamic>.from(e as Map))];
      if (mounted) {
        setState(() {
          list = l;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Belum bisa memuat pesanan terbuka (jalankan SQL supabase_update_pesanan_terbuka.sql).');
    }
  }

  int _total(OpenOrder o, int tax) => o.subtotal + (o.subtotal * tax / 100).round();

  void _detail(OpenOrder o, int tax) {
    showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Meja ${o.tableNo}${o.customerName.isEmpty ? '' : ' • ${o.customerName}'}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${o.branch} • dibuka ${jam(o.createdAt)} oleh ${o.kasir.isEmpty ? '-' : o.kasir}', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            SizedBox(height: 8),
            for (final l in o.lines)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(
                      '${l.qty} x ${l.name}${l.note.isEmpty ? '' : '\n   * ${l.note}'}${o.isExtra(l) ? '\n   Tambahan ${l.addedAt == null ? '' : jam(l.addedAt!)}${l.addedBy.isEmpty ? '' : ' • ${l.addedBy}'}' : ''}',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(rp(l.price * l.qty), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            Divider(),
            Row(children: [
              Expanded(child: Text('Total (termasuk pajak)', style: TextStyle(fontWeight: FontWeight.w800))),
              Text(rp(_total(o, tax)), style: TextStyle(fontWeight: FontWeight.w800)),
            ]),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('Tutup'))],
      ),
    );
  }

  Future<void> _cancel(OpenOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Batalkan pesanan?'),
        content: Text('Pesanan Meja ${o.tableNo} (${o.branch}) akan dibatalkan dan tidak masuk omzet. Tindakan ini tidak bisa diurungkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Kembali')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFC62828)),
            onPressed: () => Navigator.pop(d, true),
            child: Text('Ya, Batalkan'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await sb.from('open_orders').update({'status': 'cancelled', 'closed_at': now, 'updated_at': now}).eq('id', o.id);
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal membatalkan: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tax = context.read<AppState>().taxPercent;
    final sum = list.fold<int>(0, (a, o) => a + _total(o, tax));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 0, 4),
        child: Row(children: [
          Expanded(child: Text('Meja belum bayar (${list.length})', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
          if (list.isNotEmpty) Text(rp(sum), style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF7A3E00))),
        ]),
      ),
      if (error != null) Text(error!, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
      if (error == null && list.isEmpty) Text('Tidak ada meja yang belum bayar', style: TextStyle(color: Colors.grey)),
      for (final o in list)
        Container(
          margin: EdgeInsets.only(bottom: 6),
          decoration: cardDeco(color: Color(0xFFFFFAF0)),
          child: ListTile(
            onTap: () => _detail(o, tax),
            title: Text('Meja ${o.tableNo}${o.customerName.isEmpty ? '' : ' • ${o.customerName}'}', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${o.branch} • ${o.itemCount} item • sejak ${jam(o.createdAt)} (${lamaSejak(o.createdAt)})'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(rp(_total(o, tax)), style: TextStyle(fontWeight: FontWeight.w800)),
              IconButton(
                tooltip: 'Batalkan pesanan',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.cancel_outlined, size: 20, color: Color(0xFFC62828)),
                onPressed: () => _cancel(o),
              ),
            ]),
          ),
        ),
    ]);
  }
}
