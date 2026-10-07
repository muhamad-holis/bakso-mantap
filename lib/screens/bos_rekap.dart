import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cloud.dart';
import '../models.dart';
import '../shift_report.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

const _red = Color(0xFFC62828);

class _Br {
  int omzet = 0, count = 0, tax = 0, expense = 0, kasirOut = 0;
  final byMethod = <String, int>{};
  final shifts = <Shift>[];
  int get laba => omzet - tax - expense - kasirOut;
}

/// Rekap satu hari untuk semua cabang sekaligus: omzet, metode bayar, pengeluaran,
/// uang keluar kasir, laba, dan hasil tutup shift tiap kasir.
class RekapHarianPage extends StatefulWidget {
  RekapHarianPage({super.key});
  @override
  State<RekapHarianPage> createState() => _RekapHarianPageState();
}

class _RekapHarianPageState extends State<RekapHarianPage> {
  late DateTime day;
  bool loading = true;
  String? error;
  String? expenseError;
  List<Trx> trx = [];
  List<Expense> expenses = [];
  List<Shift> shifts = [];
  List<String> branchNames = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    day = DateTime(n.year, n.month, n.day);
    _load();
  }

  DateTime get _start => DateTime(day.year, day.month, day.day);
  DateTime get _end => DateTime(day.year, day.month, day.day + 1);
  bool get _isToday {
    final n = DateTime.now();
    return day.year == n.year && day.month == n.month && day.day == n.day;
  }

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      expenseError = null;
    });
    try {
      final r = await sb
          .from('transactions')
          .select()
          .gte('created_at', _iso(_start))
          .lt('created_at', _iso(_end))
          .order('created_at', ascending: false)
          .limit(5000);
      final t = [for (final e in r) Trx.fromCloud(Map<String, dynamic>.from(e as Map))];
      var ex = <Expense>[];
      String? exErr;
      try {
        final r2 = await sb.from('expenses').select().eq('date', dbDate(day)).limit(2000);
        ex = [for (final e in r2) Expense.fromCloud(Map<String, dynamic>.from(e as Map))];
      } catch (e) {
        exErr = '$e';
      }
      var sh = <Shift>[];
      try {
        // termasuk shift yang ditutup lewat tengah malam, supaya uang keluarnya ikut terhitung
        final r3 = await sb
            .from('shifts')
            .select()
            .gte('closed_at', _iso(_start))
            .lt('closed_at', _iso(DateTime(day.year, day.month, day.day + 2)))
            .order('closed_at', ascending: false)
            .limit(500);
        sh = [for (final e in r3) Shift.fromCloud(Map<String, dynamic>.from(e as Map))];
      } catch (_) {}
      final names = await loadBranchNames();
      if (!mounted) return;
      setState(() {
        trx = t;
        expenses = ex;
        expenseError = exErr;
        shifts = sh;
        branchNames = names;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  String _bn(String b) => b.isEmpty ? '(tanpa cabang)' : b;

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (d == null) return;
    setState(() => day = DateTime(d.year, d.month, d.day));
    _load();
  }

  void _move(int delta) {
    final nd = DateTime(day.year, day.month, day.day + delta);
    if (nd.isAfter(DateTime.now())) return;
    setState(() => day = nd);
    _load();
  }

  Widget _kv(String a, String b, {bool bold = false, Color? color, bool small = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: 2.5),
        child: Row(children: [
          Expanded(
            child: Text(a, style: TextStyle(fontSize: small ? 12 : 14, color: color ?? (small ? Colors.grey[700] : null), fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ),
          Text(b, style: TextStyle(fontSize: small ? 12 : 14, color: color ?? (small ? Colors.grey[700] : null), fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );

  String _shareText(Map<String, _Br> br, int omzet, int laba, int generalExp) {
    final store = context.read<AppState>().storeName;
    final b = StringBuffer();
    b.writeln('*REKAP HARIAN*');
    b.writeln(store);
    b.writeln(tgl(day));
    b.writeln('');
    for (final e in br.entries) {
      final x = e.value;
      b.writeln('*${e.key}*');
      b.writeln('Omzet: ${rp(x.omzet)} (${x.count} transaksi)');
      for (final m in x.byMethod.entries) {
        b.writeln('   ${m.key}: ${rp(m.value)}');
      }
      b.writeln('Pengeluaran: ${rp(x.expense)}');
      b.writeln('Uang keluar kasir: ${rp(x.kasirOut)}');
      b.writeln('Laba: ${rp(x.laba)}');
      for (final s in x.shifts) {
        b.writeln('Shift ${s.kasir.isEmpty ? '-' : s.kasir} ${jam(s.openedAt)}-${jam(s.closedAt!)}: ${selisihText(s.difference)}');
      }
      b.writeln('');
    }
    if (generalExp > 0) b.writeln('Pengeluaran umum (semua cabang): ${rp(generalExp)}');
    b.writeln('*TOTAL omzet: ${rp(omzet)}*');
    b.writeln('*TOTAL laba: ${rp(laba)}*');
    return b.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    // ---- hitung per cabang ----
    final br = <String, _Br>{};
    _Br of(String name) => br.putIfAbsent(name, () => _Br());
    for (final n in branchNames) {
      of(n);
    }
    for (final t in trx) {
      final x = of(_bn(t.branch));
      x.omzet += t.total;
      x.count += 1;
      x.tax += t.tax;
      x.byMethod[t.method] = (x.byMethod[t.method] ?? 0) + t.total;
    }
    var generalExp = 0;
    for (final e in expenses) {
      if (e.branch.isEmpty) {
        generalExp += e.amount;
      } else {
        of(e.branch).expense += e.amount;
      }
    }
    for (final c in cashOutEntries(shifts, from: _start, to: _end)) {
      of(_bn(c.branch)).kasirOut += c.item.amount;
    }
    for (final s in shifts) {
      if (s.closedAt != null && !s.closedAt!.isBefore(_start) && s.closedAt!.isBefore(_end)) of(_bn(s.branch)).shifts.add(s);
    }
    // cabang tanpa aktivitas sama sekali disembunyikan
    br.removeWhere((k, v) => v.count == 0 && v.expense == 0 && v.kasirOut == 0 && v.shifts.isEmpty);

    final omzet = br.values.fold<int>(0, (a, x) => a + x.omzet);
    final count = br.values.fold<int>(0, (a, x) => a + x.count);
    final laba = br.values.fold<int>(0, (a, x) => a + x.laba) - generalExp;
    final cash = br.values.fold<int>(0, (a, x) => a + (x.byMethod['Tunai'] ?? 0));
    final names = br.keys.toList()..sort((a, b) => br[b]!.omzet.compareTo(br[a]!.omzet));

    return Scaffold(
      appBar: AppBar(title: Text('Rekap Harian'), backgroundColor: navy, foregroundColor: Colors.white),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(children: [
            IconButton(onPressed: () => _move(-1), icon: Icon(Icons.chevron_left)),
            Expanded(
              child: InkWell(
                onTap: _pick,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.calendar_today, size: 16, color: blue),
                    SizedBox(width: 8),
                    Text('${tgl(day)}${_isToday ? ' (hari ini)' : ''}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ]),
                ),
              ),
            ),
            IconButton(onPressed: _isToday ? null : () => _move(1), icon: Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: loading
              ? Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Gagal memuat rekap.\n$error', textAlign: TextAlign.center)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: EdgeInsets.all(12), children: [
                        Container(
                          padding: EdgeInsets.all(18),
                          decoration: BoxDecoration(color: navy2, borderRadius: BorderRadius.circular(14)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Total semua cabang', style: TextStyle(color: Color(0xFFB8C7DE))),
                            SizedBox(height: 4),
                            Text(rp(omzet), style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('$count transaksi • Tunai ${rp(cash)} • Non-tunai ${rp(omzet - cash)}', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                            SizedBox(height: 6),
                            Text('Laba ${rp(laba)}', style: TextStyle(color: laba >= 0 ? Color(0xFF86EFAC) : Color(0xFFFCA5A5), fontWeight: FontWeight.w800, fontSize: 16)),
                            if (generalExp > 0) Text('Sudah termasuk pengeluaran umum ${rp(generalExp)}', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 11)),
                          ]),
                        ),
                        if (expenseError != null)
                          Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('Data pengeluaran belum bisa dimuat, jadi laba belum memperhitungkannya.', style: TextStyle(color: Colors.orange[800], fontSize: 12)),
                          ),
                        SizedBox(height: 10),
                        if (names.isEmpty)
                          Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Belum ada aktivitas di tanggal ini', style: TextStyle(color: Colors.grey)))),
                        for (final n in names) _branchCard(n, br[n]!),
                        if (names.isNotEmpty) ...[
                          SizedBox(height: 4),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                            onPressed: () => sendWhatsApp(context, _shareText({for (final n in names) n: br[n]!}, omzet, laba, generalExp), chooseContact: true),
                            icon: Icon(Icons.send_outlined, color: green),
                            label: Text('Bagikan Rekap ke WhatsApp'),
                          ),
                        ],
                        SizedBox(height: 20),
                      ]),
                    ),
        ),
      ]),
    );
  }

  Widget _branchCard(String name, _Br x) {
    final noShift = x.count > 0 && x.shifts.isEmpty;
    return Container(
      margin: EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.storefront, size: 20, color: blue),
          SizedBox(width: 8),
          Expanded(child: Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        ]),
        Divider(height: 18),
        _kv('Omzet', rp(x.omzet), bold: true),
        _kv('${x.count} transaksi', '', small: true),
        for (final m in x.byMethod.entries) _kv(m.key, rp(m.value), small: true),
        Divider(height: 18),
        _kv('Pajak', '- ${rp(x.tax)}'),
        _kv('Pengeluaran (dicatat bos)', '- ${rp(x.expense)}'),
        _kv('Uang keluar kasir', '- ${rp(x.kasirOut)}'),
        _kv('Laba', rp(x.laba), bold: true, color: x.laba >= 0 ? green : _red),
        Divider(height: 18),
        Text('Tutup shift', style: TextStyle(fontWeight: FontWeight.w800)),
        SizedBox(height: 4),
        if (x.shifts.isEmpty)
          Text(noShift ? 'Ada penjualan tapi belum ada shift yang ditutup' : 'Tidak ada shift ditutup',
              style: TextStyle(fontSize: 12, color: noShift ? Colors.orange[800] : Colors.grey[600], fontWeight: noShift ? FontWeight.w700 : FontWeight.w500)),
        for (final s in x.shifts)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              Expanded(
                child: Text('${s.kasir.isEmpty ? '-' : s.kasir} • ${jam(s.openedAt)}–${jam(s.closedAt!)}', style: TextStyle(fontSize: 13)),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: (s.difference == 0 ? green : _red).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text(selisihText(s.difference), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: s.difference == 0 ? green : _red)),
              ),
            ]),
          ),
      ]),
    );
  }
}
