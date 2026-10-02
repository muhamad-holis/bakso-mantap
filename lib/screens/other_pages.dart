import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'receipt_page.dart';

// ================= TRANSAKSI =================
class TransaksiPage extends StatelessWidget {
  TransaksiPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.myTransactions;
    if (list.isEmpty) return Center(child: Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      padding: EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (c, i) {
        final t = list[i];
        return Container(
          margin: EdgeInsets.only(bottom: 8),
          decoration: cardDeco(),
          child: ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t))),
            leading: cloudEnabled ? Icon(t.synced ? Icons.cloud_done : Icons.cloud_upload_outlined, color: t.synced ? green : Colors.orange) : null,
            title: Text(t.id, style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${tgl(t.date)} ${jam(t.date)} • ${t.itemCount} item • ${t.method}'),
            trailing: Text(rp(t.total), style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
          ),
        );
      },
    );
  }
}

// ================= MENU =================
class MenuPage extends StatelessWidget {
  MenuPage({super.key});

  Future<void> _edit(BuildContext context, MenuItem? m) async {
    final name = TextEditingController(text: m?.name ?? '');
    final price = TextEditingController(text: m?.price.toString() ?? '');
    final cat = TextEditingController(text: m?.category ?? 'Bakso');
    final emoji = TextEditingController(text: m?.emoji ?? '🍜');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(m == null ? 'Tambah Menu' : 'Edit Menu'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: InputDecoration(labelText: 'Nama menu')),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Harga (Rp)')),
            TextField(controller: cat, decoration: InputDecoration(labelText: 'Kategori (Bakso/Mie/Minuman/Paket)')),
            TextField(controller: emoji, decoration: InputDecoration(labelText: 'Emoji (jika tanpa foto)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Simpan')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final p = int.tryParse(price.text) ?? 0;
    if (name.text.trim().isEmpty || p <= 0) return;
    context.read<AppState>().saveMenu(
          m,
          name.text.trim(),
          p,
          cat.text.trim().isEmpty ? 'Bakso' : cat.text.trim(),
          emoji.text.trim().isEmpty ? '🍜' : emoji.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        onPressed: () => _edit(context, null),
        icon: Icon(Icons.add),
        label: Text('Tambah Menu'),
      ),
      body: ListView.builder(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: s.menus.length,
        itemBuilder: (c, i) {
          final m = s.menus[i];
          return Container(
            margin: EdgeInsets.only(bottom: 8),
            decoration: cardDeco(),
            child: ListTile(
              leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: MenuImage(m, size: 48)),
              title: Text(m.name, style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${m.category} • ${rp(m.price)}\nFoto: assets/images/${m.id}.jpg'),
              isThreeLine: true,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: Icon(Icons.edit_outlined), onPressed: () => _edit(context, m)),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: Text('Hapus menu?'),
                        content: Text(m.name),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
                          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted) context.read<AppState>().deleteMenu(m);
                  },
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ================= LAPORAN =================
class LaporanPage extends StatelessWidget {
  LaporanPage({super.key});

  Widget _stat(String label, String value) => Container(
        width: 200,
        padding: EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: navy)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = DateTime.now();
    final today = s.transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).toList();
    final omzet = today.fold<int>(0, (a, t) => a + t.total);
    final items = today.fold<int>(0, (a, t) => a + t.itemCount);
    final allOmzet = s.transactions.fold<int>(0, (a, t) => a + t.total);
    final byMenu = <String, int>{};
    for (final t in today) {
      for (final l in t.lines) {
        byMenu[l.name] = (byMenu[l.name] ?? 0) + l.qty;
      }
    }
    final top = byMenu.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(padding: EdgeInsets.all(12), children: [
      Text('Hari ini • ${tgl(now)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 10, children: [
        _stat('Omzet hari ini', rp(omzet)),
        _stat('Jumlah transaksi', '${today.length}'),
        _stat('Item terjual', '$items'),
        _stat('Omzet keseluruhan', rp(allOmzet)),
      ]),
      SizedBox(height: 16),
      Text('Menu terlaris hari ini', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      SizedBox(height: 8),
      if (top.isEmpty) Text('Belum ada penjualan hari ini', style: TextStyle(color: Colors.grey)),
      for (final e in top)
        Container(
          margin: EdgeInsets.only(bottom: 6),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: cardDeco(),
          child: Row(children: [
            Expanded(child: Text(e.key, style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${e.value} terjual', style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
          ]),
        ),
    ]);
  }
}

// ================= PENGATURAN =================
class PengaturanPage extends StatefulWidget {
  PengaturanPage({super.key});
  @override
  State<PengaturanPage> createState() => _PengaturanPageState();
}

class _PengaturanPageState extends State<PengaturanPage> {
  late final TextEditingController store;
  late final TextEditingController kasir;
  late final TextEditingController tax;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    store = TextEditingController(text: s.storeName);
    kasir = TextEditingController(text: s.kasir);
    tax = TextEditingController(text: '${s.taxPercent}');
  }

  @override
  void dispose() {
    store.dispose();
    kasir.dispose();
    tax.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(padding: EdgeInsets.all(12), children: [
      Container(
        padding: EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Column(children: [
          TextField(controller: store, decoration: InputDecoration(labelText: 'Nama toko')),
          TextField(controller: kasir, decoration: InputDecoration(labelText: 'Nama kasir')),
          TextField(controller: tax, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Pajak PPN (%)  — isi 0 jika tanpa pajak')),
          SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: Size.fromHeight(48)),
              onPressed: () {
                final t = int.tryParse(tax.text) ?? 0;
                s.saveSettings(store.text.trim().isEmpty ? 'Bakso TITATI Wonogiri Opik Jon' : store.text.trim(),
                    kasir.text.trim().isEmpty ? 'admin' : kasir.text.trim(), t.clamp(0, 100));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pengaturan disimpan')));
              },
              child: Text('Simpan'),
            ),
          ),
        ]),
      ),
      SizedBox(height: 14),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48), foregroundColor: Colors.red),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: Text('Hapus semua transaksi?'),
              content: Text('Riwayat transaksi dan laporan akan dihapus permanen.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
                FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
              ],
            ),
          );
          if (ok == true) s.clearTransactions();
        },
        icon: Icon(Icons.delete_forever),
        label: Text('Hapus Semua Transaksi'),
      ),
      if (cloudEnabled) ...[
        SizedBox(height: 14),
        Container(
          padding: EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Sinkron ke Bos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            SizedBox(height: 6),
            Text(s.pendingCount == 0 ? 'Semua transaksi sudah terkirim' : '${s.pendingCount} transaksi menunggu dikirim'),
            SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton.icon(onPressed: s.syncPending, icon: Icon(Icons.sync), label: Text('Kirim Sekarang'))),
              SizedBox(width: 10),
              Expanded(child: FilledButton.icon(onPressed: s.logout, icon: Icon(Icons.logout), label: Text('Keluar'))),
            ]),
          ]),
        ),
      ],
    ]);
  }
}

// ================= AKUN KASIR (mode cloud, tanpa edit) =================
class AkunPage extends StatelessWidget {
  AkunPage({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return ListView(padding: EdgeInsets.all(12), children: [
      Container(
        padding: EdgeInsets.all(16),
        decoration: cardDeco(),
        child: Row(children: [
          Icon(Icons.account_circle, size: 46, color: navy),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.kasir, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(s.branch.isEmpty ? 'Kasir' : 'Kasir • ${s.branch}', style: TextStyle(color: Colors.grey[700])),
            ]),
          ),
        ]),
      ),
      SizedBox(height: 12),
      Container(
        padding: EdgeInsets.all(14),
        decoration: cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sinkron ke Bos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          SizedBox(height: 6),
          Text(s.pendingCount == 0 ? 'Semua transaksi sudah terkirim' : '${s.pendingCount} transaksi menunggu dikirim'),
          if (s.syncError != null && s.pendingCount > 0)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Gagal kirim: ${s.syncError}', style: TextStyle(color: Colors.red, fontSize: 12)),
            ),
          SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final err = await s.syncPending();
                  s.pullConfig();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err == null ? 'Sinkron selesai' : 'Gagal kirim: $err')));
                  }
                },
                icon: Icon(Icons.sync),
                label: Text('Sinkron Sekarang'),
              ),
            ),
            SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: s.logout, icon: Icon(Icons.logout), label: Text('Keluar'))),
          ]),
        ]),
      ),
      SizedBox(height: 10),
      Text('Menu, harga, dan pajak diatur oleh bos.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
    ]);
  }
}
