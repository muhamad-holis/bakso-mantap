import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cloud.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'receipt_page.dart';

class BosPage extends StatefulWidget {
  BosPage({super.key});
  @override
  State<BosPage> createState() => _BosPageState();
}

class _BosPageState extends State<BosPage> {
  String period = 'Hari ini';
  String branch = 'Semua Cabang';
  final periods = ['Hari ini', 'Kemarin', '7 Hari', '30 Hari'];

  // 1000 transaksi terbaru, update otomatis (realtime)
  late final Stream<List<Map<String, dynamic>>> stream =
      sb.from('transactions').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(1000);

  bool _inBranch(Trx t) => branch == 'Semua Cabang' || t.branch == branch;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<Trx> _filter(List<Trx> all) {
    final today = _today;
    DateTime from;
    DateTime? to;
    switch (period) {
      case 'Kemarin':
        from = today.subtract(Duration(days: 1));
        to = today;
        break;
      case '7 Hari':
        from = today.subtract(Duration(days: 6));
        break;
      case '30 Hari':
        from = today.subtract(Duration(days: 29));
        break;
      default:
        from = today;
    }
    return all
        .where((t) => !t.date.isBefore(from) && (to == null || t.date.isBefore(to)) && _inBranch(t))
        .toList();
  }

  Widget _stat(String label, String value) => Expanded(
        child: Container(
          margin: EdgeInsets.all(4),
          padding: EdgeInsets.all(14),
          decoration: cardDeco(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
            SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: navy)),
          ]),
        ),
      );

  Widget _title(String t) => Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _row(String a, String b) => Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardDeco(),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(fontWeight: FontWeight.w600))),
          Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppState>().storeName;
    return Scaffold(
      body: Column(children: [
        Container(
          color: navy,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(children: [
                Icon(Icons.insights, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(store, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    Text('Mode Bos', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                  ]),
                ),
                Icon(Icons.circle, color: Colors.greenAccent, size: 10),
                SizedBox(width: 4),
                Text('Live', style: TextStyle(color: Colors.white, fontSize: 12)),
                IconButton(
                  tooltip: 'Keluar',
                  icon: Icon(Icons.logout, color: Colors.white),
                  onPressed: () => context.read<AppState>().logout(),
                ),
              ]),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (c, snap) {
              if (snap.hasError) {
                return Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Gagal memuat data.\n${snap.error}', textAlign: TextAlign.center)));
              }
              if (!snap.hasData) return Center(child: CircularProgressIndicator());
              final all = snap.data!.map((e) => Trx.fromCloud(e)).toList();
              final list = _filter(all);
              final branches = {...all.map((t) => t.branch).where((b) => b.isNotEmpty)}.toList()..sort();

              final omzet = list.fold<int>(0, (a, t) => a + t.total);
              final items = list.fold<int>(0, (a, t) => a + t.itemCount);
              final avg = list.isEmpty ? 0 : (omzet / list.length).round();

              final byMethod = <String, int>{};
              final byMenu = <String, int>{};
              final byBranch = <String, int>{};
              for (final t in list) {
                final bn = t.branch.isEmpty ? '(tanpa cabang)' : t.branch;
                byBranch[bn] = (byBranch[bn] ?? 0) + t.total;
                byMethod[t.method] = (byMethod[t.method] ?? 0) + t.total;
                for (final l in t.lines) {
                  byMenu[l.name] = (byMenu[l.name] ?? 0) + l.qty;
                }
              }
              final top = byMenu.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

              String? kemarin;
              if (period == 'Hari ini') {
                final y = _today.subtract(Duration(days: 1));
                final yo = all.where((t) => !t.date.isBefore(y) && t.date.isBefore(_today) && _inBranch(t)).fold<int>(0, (a, t) => a + t.total);
                kemarin = 'Kemarin: ${rp(yo)}';
              }

              return ListView(padding: EdgeInsets.all(12), children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final p in periods)
                      Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(p),
                          selected: period == p,
                          showCheckmark: false,
                          selectedColor: blue,
                          backgroundColor: Colors.white,
                          labelStyle: TextStyle(color: period == p ? Colors.white : navy, fontWeight: FontWeight.w600),
                          shape: StadiumBorder(side: BorderSide(color: lineColor)),
                          onSelected: (_) => setState(() => period = p),
                        ),
                      ),
                  ]),
                ),
                if (branches.isNotEmpty) ...[
                  SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final b in ['Semua Cabang', ...branches])
                        Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(b),
                            selected: branch == b,
                            showCheckmark: false,
                            selectedColor: navy2,
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(color: branch == b ? Colors.white : navy, fontWeight: FontWeight.w600),
                            shape: StadiumBorder(side: BorderSide(color: lineColor)),
                            onSelected: (_) => setState(() => branch = b),
                          ),
                        ),
                    ]),
                  ),
                ],
                SizedBox(height: 10),
                Container(
                  padding: EdgeInsets.all(18),
                  decoration: BoxDecoration(color: navy2, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Omzet $period', style: TextStyle(color: Color(0xFFB8C7DE))),
                    SizedBox(height: 4),
                    Text(rp(omzet), style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                    if (kemarin != null) Text(kemarin, style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                  ]),
                ),
                SizedBox(height: 6),
                Row(children: [_stat('Transaksi', '${list.length}'), _stat('Item terjual', '$items')]),
                Row(children: [_stat('Rata-rata / transaksi', rp(avg)), _stat('Pajak terkumpul', rp(list.fold<int>(0, (a, t) => a + t.tax)))]),
                if (branch == 'Semua Cabang' && byBranch.length > 1) ...[
                  _title('Omzet per cabang'),
                  for (final e in (byBranch.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) _row(e.key, rp(e.value)),
                ],
                _title('Metode pembayaran'),
                if (byMethod.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
                for (final e in byMethod.entries) _row(e.key, rp(e.value)),
                _title('Menu terlaris'),
                if (top.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
                for (final e in top.take(5)) _row(e.key, '${e.value} terjual'),
                _title('Transaksi terbaru'),
                if (list.isEmpty) Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)),
                for (final t in list.take(30))
                  Container(
                    margin: EdgeInsets.only(bottom: 6),
                    decoration: cardDeco(),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t))),
                      title: Text(rp(t.total), style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${jam(t.date)} • ${tgl(t.date)} • ${t.itemCount} item • ${t.method}\nKasir: ${t.kasir}${t.branch.isEmpty ? '' : ' • ${t.branch}'}'),
                      isThreeLine: true,
                      trailing: Icon(Icons.chevron_right),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
