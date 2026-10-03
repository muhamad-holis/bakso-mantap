import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../cloud.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

/// Bos mencatat pengeluaran (belanja bahan, gas, gaji, dll) supaya laporan bisa menampilkan laba.
class BosExpensePage extends StatefulWidget {
  BosExpensePage({super.key});
  @override
  State<BosExpensePage> createState() => _BosExpensePageState();
}

class _BosExpensePageState extends State<BosExpensePage> {
  String period = 'Hari ini';
  String branch = 'Semua Cabang';
  final periods = ['Hari ini', 'Kemarin', '7 Hari', '30 Hari'];
  List<String> branches = [];
  List<Expense> all = [];
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadBranches();
    await _load();
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _loadBranches() async {
    try {
      final list = await loadBranchNames();
      if (mounted) setState(() => branches = list);
    } catch (_) {}
  }

  Future<void> _load() async {
    try {
      final from = DateTime.now().subtract(Duration(days: 40));
      final r = await sb
          .from('expenses')
          .select()
          .gte('date', dbDate(from))
          .order('date', ascending: false)
          .order('created_at', ascending: false)
          .limit(1000);
      final list = [for (final e in r) Expense.fromCloud(Map<String, dynamic>.from(e as Map))];
      if (mounted) {
        setState(() {
          all = list;
          error = null;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  List<Expense> get _list {
    final t = _today;
    DateTime from;
    DateTime? to;
    switch (period) {
      case 'Kemarin':
        from = t.subtract(Duration(days: 1));
        to = t;
        break;
      case '7 Hari':
        from = t.subtract(Duration(days: 6));
        break;
      case '30 Hari':
        from = t.subtract(Duration(days: 29));
        break;
      default:
        from = t;
    }
    return all
        .where((e) => !e.date.isBefore(from) && (to == null || e.date.isBefore(to)) && (branch == 'Semua Cabang' || e.branch == branch))
        .toList();
  }

  String _newId() {
    final now = DateTime.now();
    final rnd = (now.microsecondsSinceEpoch % 46656).toRadixString(36).toUpperCase().padLeft(3, '0');
    return 'EXP${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}-$rnd';
  }

  Future<void> _edit(Expense? e) async {
    final name = TextEditingController(text: e?.name ?? '');
    final amount = TextEditingController(text: e == null ? '' : '${e.amount}');
    final note = TextEditingController(text: e?.note ?? '');
    var cat = e != null && expenseCategories.contains(e.category) ? e.category : expenseCategories.first;
    var date = e?.date ?? _today;
    var br = e?.branch ?? (branch == 'Semua Cabang' ? '' : branch);
    final brOptions = <String>['', ...branches, if (br.isNotEmpty && !branches.contains(br)) br];
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) {
          final valid = name.text.trim().isNotEmpty && (int.tryParse(amount.text) ?? 0) > 0;
          return AlertDialog(
            title: Text(e == null ? 'Catat Pengeluaran' : 'Ubah Pengeluaran'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: name,
                  autofocus: e == null,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: 'Belanja apa?', hintText: 'Contoh: Daging sapi 5 kg'),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(9)],
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: 'Jumlah (Rp)', prefixText: 'Rp '),
                ),
                SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: cat,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Kategori'),
                  items: [for (final c in expenseCategories) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setS(() => cat = v ?? cat),
                ),
                SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: br,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Cabang'),
                  items: [for (final b in brOptions) DropdownMenuItem(value: b, child: Text(b.isEmpty ? 'Umum (semua cabang)' : b))],
                  onChanged: (v) => setS(() => br = v ?? ''),
                ),
                SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await showDatePicker(
                      context: d,
                      initialDate: date,
                      firstDate: DateTime(_today.year - 1, 1, 1),
                      lastDate: _today.isAfter(date) ? _today : date,
                    );
                    if (p != null) setS(() => date = DateTime(p.year, p.month, p.day));
                  },
                  icon: Icon(Icons.event),
                  label: Text('Tanggal: ${tgl(date)}'),
                ),
                SizedBox(height: 8),
                TextField(controller: note, decoration: InputDecoration(labelText: 'Catatan (opsional)')),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
              FilledButton(onPressed: valid ? () => Navigator.pop(d, true) : null, child: Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final row = Expense(
      id: e?.id ?? _newId(),
      date: DateTime(date.year, date.month, date.day),
      branch: br,
      category: cat,
      name: name.text.trim(),
      amount: int.tryParse(amount.text) ?? 0,
      note: note.text.trim(),
    );
    try {
      if (e == null) {
        await sb.from('expenses').insert(row.toCloud());
      } else {
        await sb.from('expenses').update(row.toCloud()).eq('id', e.id);
      }
      expenseChanged.value++;
      await _load();
      if (mounted) _msg('Pengeluaran tersimpan');
    } catch (err) {
      if (mounted) _msg('Gagal menyimpan: $err');
    }
  }

  Future<void> _delete(Expense e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus pengeluaran?'),
        content: Text('${e.name}\n${rp(e.amount)}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('expenses').delete().eq('id', e.id);
      expenseChanged.value++;
      await _load();
    } catch (err) {
      if (mounted) _msg('Gagal menghapus: $err');
    }
  }

  Widget _chips(List<String> items, String selected, Color selColor, void Function(String) onPick) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final p in items)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(p),
                selected: selected == p,
                showCheckmark: false,
                selectedColor: selColor,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(color: selected == p ? Colors.white : navy, fontWeight: FontWeight.w600),
                shape: StadiumBorder(side: BorderSide(color: lineColor)),
                onSelected: (_) => onPick(p),
              ),
            ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppState>().storeName;
    final list = _list;
    final total = list.fold<int>(0, (a, e) => a + e.amount);
    final byCat = <String, int>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }

    final children = <Widget>[];
    DateTime? last;
    for (final e in list) {
      if (last == null || !_same(last, e.date)) {
        final day = e.date;
        final dayTotal = list.where((x) => _same(x.date, day)).fold<int>(0, (a, x) => a + x.amount);
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(children: [
            Expanded(child: Text('${tgl(day)}${_same(day, _today) ? ' (hari ini)' : ''}', style: TextStyle(fontWeight: FontWeight.w800))),
            Text(rp(dayTotal), style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFC62828))),
          ]),
        ));
        last = e.date;
      }
      children.add(Container(
        margin: EdgeInsets.only(bottom: 6),
        decoration: cardDeco(),
        child: ListTile(
          onTap: () => _edit(e),
          title: Text(e.name, style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${e.category} • ${e.branch.isEmpty ? 'Umum' : e.branch}${e.note.isEmpty ? '' : '\n${e.note}'}'),
          isThreeLine: e.note.isNotEmpty,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(rp(e.amount), style: TextStyle(fontWeight: FontWeight.w800)),
            IconButton(icon: Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delete(e)),
          ]),
        ),
      ));
    }

    Widget body;
    if (loading) {
      body = Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Gagal memuat pengeluaran.\nJalankan supabase_update_pengeluaran.sql di Supabase, lalu coba lagi.\n\n$error', textAlign: TextAlign.center),
            SizedBox(height: 12),
            FilledButton(onPressed: _load, child: Text('Coba lagi')),
          ]),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(12, 12, 12, 90), children: [
          _chips(periods, period, blue, (p) => setState(() => period = p)),
          if (branches.isNotEmpty) ...[
            SizedBox(height: 8),
            _chips(['Semua Cabang', ...branches], branch, navy2, (b) => setState(() => branch = b)),
          ],
          SizedBox(height: 10),
          Container(
            padding: EdgeInsets.all(18),
            decoration: BoxDecoration(color: navy2, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total pengeluaran $period', style: TextStyle(color: Color(0xFFB8C7DE))),
              SizedBox(height: 4),
              Text(rp(total), style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
              if (byCat.isNotEmpty) ...[
                SizedBox(height: 6),
                Text(
                  byCat.entries.map((e) => '${e.key} ${rp(e.value)}').join(' • '),
                  style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12),
                ),
              ],
            ]),
          ),
          if (children.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Belum ada pengeluaran di periode ini.\nKetuk "Catat" untuk menambah.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
            )
          else
            ...children,
        ]),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: blue,
        foregroundColor: Colors.white,
        onPressed: () => _edit(null),
        icon: Icon(Icons.add),
        label: Text('Catat'),
      ),
      body: Column(children: [
        Container(
          color: navy,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 6, 10),
              child: Row(children: [
                Icon(Icons.shopping_basket_outlined, color: Colors.white, size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(store, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                    Text('Pengeluaran & belanja bahan', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                  ]),
                ),
                IconButton(tooltip: 'Keluar', icon: Icon(Icons.logout, color: Colors.white), onPressed: () => context.read<AppState>().logout()),
              ]),
            ),
          ),
        ),
        Expanded(child: body),
      ]),
    );
  }
}
