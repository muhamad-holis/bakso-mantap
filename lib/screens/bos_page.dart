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
  List<Expense> expenses = []; // pengeluaran ~40 hari terakhir
  String? expenseError; // pesan jika data pengeluaran gagal dimuat (mis. SQL belum dijalankan)
  List<Shift> shifts = []; // shift yang sudah ditutup kasir
  List<String> knownBranches = []; // cabang dari akun kasir, tampil walau belum ada transaksi

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _loadShifts();
    _loadExpenses();
    expenseChanged.addListener(_loadExpenses);
  }

  @override
  void dispose() {
    expenseChanged.removeListener(_loadExpenses);
    super.dispose();
  }

  Future<void> _loadExpenses() async {
    try {
      final from = DateTime.now().subtract(Duration(days: 40));
      final r = await sb.from('expenses').select().gte('date', dbDate(from)).order('date', ascending: false).limit(2000);
      final list = [for (final e in r) Expense.fromCloud(Map<String, dynamic>.from(e as Map))];
      if (mounted) {
        setState(() {
          expenses = list;
          expenseError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => expenseError = '$e');
    }
  }

  Future<void> _loadShifts() async {
    try {
      final r = await sb.from('shifts').select().order('closed_at', ascending: false).limit(50);
      final list = [for (final e in r) Shift.fromCloud(Map<String, dynamic>.from(e as Map))];
      if (mounted) setState(() => shifts = list);
    } catch (_) {}
  }

  Future<void> _loadBranches() async {
    try {
      final r = await sb.from('profiles').select('branch');
      final set = <String>{
        for (final e in r)
          if ((e['branch'] as String?)?.isNotEmpty ?? false) e['branch'] as String,
      };
      if (mounted) setState(() => knownBranches = set.toList()..sort());
    } catch (_) {}
  }

  // 1000 transaksi terbaru, update otomatis (realtime)
  // Diambil ulang tiap 10 detik (tidak bergantung pada fitur realtime Supabase)
  late final Stream<List<Map<String, dynamic>>> stream = _poll();

  Stream<List<Map<String, dynamic>>> _poll() async* {
    var first = true;
    while (mounted) {
      try {
        final r = await sb.from('transactions').select().order('created_at', ascending: false).limit(1000);
        yield [for (final e in r) Map<String, dynamic>.from(e as Map)];
      } catch (e) {
        if (first) rethrow; // gagal pertama kali: tampilkan pesan error
      }
      first = false;
      _loadShifts();
      _loadExpenses();
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  bool _inBranch(Trx t) => branch == 'Semua Cabang' || t.branch == branch;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime get _from {
    final t = _today;
    switch (period) {
      case 'Kemarin':
        return t.subtract(Duration(days: 1));
      case '7 Hari':
        return t.subtract(Duration(days: 6));
      case '30 Hari':
        return t.subtract(Duration(days: 29));
      default:
        return t;
    }
  }

  List<Expense> _filterExp(List<Expense> all) {
    final from = _from;
    final to = period == 'Kemarin' ? _today : null;
    return all
        .where((e) => !e.date.isBefore(from) && (to == null || e.date.isBefore(to)) && (branch == 'Semua Cabang' || e.branch == branch))
        .toList();
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _labaCard(int omzet, int pajak, int pengeluaran) {
    final laba = omzet - pajak - pengeluaran;
    Widget r(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
            Text(b, style: TextStyle(color: color, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 20 : 14)),
          ]),
        );
    return Container(
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Laba $period${branch == 'Semua Cabang' ? '' : ' • $branch'}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 6),
        r('Omzet', rp(omzet)),
        r('Pajak (PPN) terkumpul', '-${rp(pajak)}'),
        r('Pengeluaran', '-${rp(pengeluaran)}'),
        Divider(height: 16),
        r('Laba', rp(laba), bold: true, color: laba >= 0 ? green : Color(0xFFC62828)),
        if (expenseError != null)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Data pengeluaran belum bisa dimuat, jadi laba di atas belum memperhitungkannya. Jalankan supabase_update_pengeluaran.sql di Supabase.',
                style: TextStyle(color: Colors.orange[800], fontSize: 12)),
          )
        else if (pengeluaran == 0)
          Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Belum ada pengeluaran dicatat di periode ini. Catat belanja di tab Pengeluaran.', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _rowSub(String a, String sub, String b, Color color) => Container(
        margin: EdgeInsets.only(bottom: 6),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: cardDeco(),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a, style: TextStyle(fontWeight: FontWeight.w600)),
              Text(sub, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            ]),
          ),
          Text(b, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
        ]),
      );

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
              final branches = {...knownBranches, ...all.map((t) => t.branch).where((b) => b.isNotEmpty)}.toList()..sort();

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

              final exp = _filterExp(expenses);
              final pengeluaran = exp.fold<int>(0, (a, e) => a + e.amount);
              final pajak = list.fold<int>(0, (a, t) => a + t.tax);
              final taxByBranch = <String, int>{};
              final expByBranch = <String, int>{};
              for (final t in list) {
                final bn = t.branch.isEmpty ? '(tanpa cabang)' : t.branch;
                taxByBranch[bn] = (taxByBranch[bn] ?? 0) + t.tax;
              }
              for (final e in exp) {
                final bn = e.branch.isEmpty ? 'Umum (semua cabang)' : e.branch;
                expByBranch[bn] = (expByBranch[bn] ?? 0) + e.amount;
              }
              final labaBranches = {...byBranch.keys, ...expByBranch.keys}.toList();
              final labaOf = {for (final k in labaBranches) k: (byBranch[k] ?? 0) - (taxByBranch[k] ?? 0) - (expByBranch[k] ?? 0)};
              labaBranches.sort((a, b) => labaOf[b]!.compareTo(labaOf[a]!));
              final expByCat = <String, int>{};
              for (final e in exp) {
                expByCat[e.category] = (expByCat[e.category] ?? 0) + e.amount;
              }
              final dayCount = period == '7 Hari' ? 7 : (period == '30 Hari' ? 30 : 0);
              final perHari = <Widget>[];
              for (var i = 0; i < dayCount; i++) {
                final d = DateTime(_today.year, _today.month, _today.day - i);
                final dt = list.where((t) => _sameDay(t.date, d)).toList();
                final de = exp.where((e) => _sameDay(e.date, d)).toList();
                final o = dt.fold<int>(0, (a, t) => a + t.total);
                final tx = dt.fold<int>(0, (a, t) => a + t.tax);
                final ex = de.fold<int>(0, (a, e) => a + e.amount);
                final l = o - tx - ex;
                perHari.add(_rowSub(i == 0 ? '${tgl(d)} (hari ini)' : tgl(d), 'Omzet ${rp(o)} • Pengeluaran ${rp(ex)}', rp(l), l >= 0 ? green : Color(0xFFC62828)));
              }

              final shiftList = shifts.where((x) => branch == 'Semua Cabang' || x.branch == branch).toList();

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
                SizedBox(height: 10),
                _labaCard(omzet, pajak, pengeluaran),
                SizedBox(height: 6),
                Row(children: [_stat('Transaksi', '${list.length}'), _stat('Item terjual', '$items')]),
                Row(children: [_stat('Rata-rata / transaksi', rp(avg)), _stat('Pajak terkumpul', rp(list.fold<int>(0, (a, t) => a + t.tax)))]),
                if (dayCount > 0) ...[
                  _title('Laba per hari'),
                  ...perHari,
                ],
                if (branch == 'Semua Cabang' && labaBranches.length > 1) ...[
                  _title('Laba per cabang'),
                  for (final k in labaBranches)
                    _rowSub(k, 'Omzet ${rp(byBranch[k] ?? 0)} • Pengeluaran ${rp(expByBranch[k] ?? 0)}', rp(labaOf[k]!), labaOf[k]! >= 0 ? green : Color(0xFFC62828)),
                ],
                if (expByCat.isNotEmpty) ...[
                  _title('Pengeluaran per kategori'),
                  for (final e in (expByCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) _row(e.key, rp(e.value)),
                ],
                _title('Metode pembayaran'),
                if (byMethod.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
                for (final e in byMethod.entries) _row(e.key, rp(e.value)),
                _title('Menu terlaris'),
                if (top.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
                for (final e in top.take(5)) _row(e.key, '${e.value} terjual'),
                _title('Tutup shift terbaru'),
                if (shiftList.isEmpty) Text('Belum ada data', style: TextStyle(color: Colors.grey)),
                for (final x in shiftList.take(10))
                  Container(
                    margin: EdgeInsets.only(bottom: 6),
                    decoration: cardDeco(),
                    child: ListTile(
                      title: Text('${x.kasir.isEmpty ? '-' : x.kasir}${x.branch.isEmpty ? '' : ' • ${x.branch}'}', style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${tgl(x.openedAt)} ${jam(x.openedAt)}–${jam(x.closedAt!)}\nKas awal ${rp(x.openingCash)} • Tunai sistem ${rp(x.cashSales)}\nKas akhir ${rp(x.closingCash)}${x.note.isEmpty ? '' : '\nCatatan: ${x.note}'}'),
                      isThreeLine: true,
                      trailing: Text(selisihText(x.difference), style: TextStyle(fontWeight: FontWeight.w800, color: x.difference == 0 ? green : Color(0xFFC62828))),
                    ),
                  ),
                _title('Transaksi terbaru'),
                if (list.isEmpty) Text('Belum ada transaksi', style: TextStyle(color: Colors.grey)),
                for (final t in list.take(30))
                  Container(
                    margin: EdgeInsets.only(bottom: 6),
                    decoration: cardDeco(),
                    child: ListTile(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReceiptPage(trx: t))),
                      title: Text(rp(t.total), style: TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${jam(t.date)} • ${tgl(t.date)} • ${t.itemCount} item • ${t.method}\nKasir: ${t.kasir}${t.branch.isEmpty ? '' : ' • ${t.branch}'}${t.orderLabel.isEmpty ? '' : '\n${t.orderLabel}'}'),
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
