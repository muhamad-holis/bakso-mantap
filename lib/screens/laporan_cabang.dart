import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'receipt_page.dart';

/// Laporan transaksi & pendapatan untuk akun kasir/cabang (mode login).
/// Data diambil dari riwayat cabang ini di HP (s.myTransactions), jadi tetap
/// bisa dibuka saat internet mati dan sudah termasuk transaksi yang belum terkirim.
class LaporanCabangPage extends StatefulWidget {
  LaporanCabangPage({super.key});
  @override
  State<LaporanCabangPage> createState() => _LaporanCabangPageState();
}

class _LaporanCabangPageState extends State<LaporanCabangPage> {
  String period = 'Hari ini';
  final periods = ['Hari ini', 'Kemarin', '7 Hari', '30 Hari'];

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime _daysAgo(int n) {
    final t = _today;
    return DateTime(t.year, t.month, t.day - n);
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Trx> _filter(List<Trx> all) {
    final DateTime from;
    final DateTime? end;
    switch (period) {
      case 'Kemarin':
        from = _daysAgo(1);
        end = _today;
        break;
      case '7 Hari':
        from = _daysAgo(6);
        end = null;
        break;
      case '30 Hari':
        from = _daysAgo(29);
        end = null;
        break;
      default:
        from = _today;
        end = null;
    }
    return all.where((t) {
      if (t.date.isBefore(from)) return false;
      if (end != null && !t.date.isBefore(end)) return false;
      return true;
    }).toList();
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

  Widget _row(String a, String b, {String? sub}) => Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardDeco(),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a, style: TextStyle(fontWeight: FontWeight.w600)),
              if (sub != null) Text(sub, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
          Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final all = s.myTransactions;
    final list = _filter(all);

    final omzet = list.fold<int>(0, (a, t) => a + t.total);
    final items = list.fold<int>(0, (a, t) => a + t.itemCount);
    final avg = list.isEmpty ? 0 : (omzet / list.length).round();
    final pajak = list.fold<int>(0, (a, t) => a + t.tax);

    final byMethod = <String, int>{};
    final byMenu = <String, int>{};
    for (final t in list) {
      byMethod[t.method] = (byMethod[t.method] ?? 0) + t.total;
      for (final l in t.lines) {
        byMenu[l.name] = (byMenu[l.name] ?? 0) + l.qty;
      }
    }
    final top = byMenu.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    String? kemarin;
    if (period == 'Hari ini') {
      final y = _daysAgo(1);
      final yo = all.where((t) => _sameDay(t.date, y)).fold<int>(0, (a, t) => a + t.total);
      kemarin = 'Kemarin: ${rp(yo)}';
    }

    // rincian per hari untuk periode 7 / 30 hari (hari terbaru di atas)
    final dayCount = period == '7 Hari' ? 7 : (period == '30 Hari' ? 30 : 0);
    final perHari = <Widget>[];
    for (var i = 0; i < dayCount; i++) {
      final d = _daysAgo(i);
      final dayTrx = list.where((t) => _sameDay(t.date, d)).toList();
      final dayOmzet = dayTrx.fold<int>(0, (a, t) => a + t.total);
      perHari.add(_row(i == 0 ? '${tgl(d)} (hari ini)' : tgl(d), rp(dayOmzet), sub: '${dayTrx.length} transaksi'));
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
      SizedBox(height: 10),
      Container(
        padding: EdgeInsets.all(18),
        decoration: BoxDecoration(color: navy2, borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Pendapatan $period${s.branch.isEmpty ? '' : ' • ${s.branch}'}', style: TextStyle(color: Color(0xFFB8C7DE))),
          SizedBox(height: 4),
          Text(rp(omzet), style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          if (kemarin != null) Text(kemarin, style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
        ]),
      ),
      SizedBox(height: 6),
      Row(children: [_stat('Transaksi', '${list.length}'), _stat('Item terjual', '$items')]),
      Row(children: [_stat('Rata-rata / transaksi', rp(avg)), _stat('Pajak terkumpul', rp(pajak))]),
      if (dayCount > 0) ...[
        _title('Pendapatan per hari'),
        ...perHari,
      ],
      _title('Metode pembayaran'),
      if (byMethod.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
      for (final e in byMethod.entries) _row(e.key, rp(e.value)),
      _title('Menu terlaris'),
      if (top.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
      for (final e in top.take(5)) _row(e.key, '${e.value} terjual'),
      _title('Transaksi $period'),
      if (list.isEmpty) Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)),
      for (final t in list.take(30))
        Container(
          margin: EdgeInsets.only(bottom: 6),
          decoration: cardDeco(),
          child: ListTile(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t))),
            title: Text(rp(t.total), style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${jam(t.date)} • ${tgl(t.date)} • ${t.itemCount} item • ${t.method}'),
            trailing: Icon(Icons.chevron_right),
          ),
        ),
      if (list.length > 30)
        Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Menampilkan 30 dari ${list.length} transaksi. Daftar lengkap ada di tab Transaksi.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        ),
    ]);
  }
}
