import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cloud.dart';
import '../models.dart';
import '../shift_report.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';

class _Sold {
  int qty = 0;
  int value = 0;
}

/// Hasil hitung penjualan: berapa porsi tiap menu terjual dalam satu rentang waktu.
class _Agg {
  final items = <String, _Sold>{};
  int trxCount = 0;

  int get qty => items.values.fold(0, (a, x) => a + x.qty);
  int get value => items.values.fold(0, (a, x) => a + x.value);
  List<MapEntry<String, _Sold>> get sorted => items.entries.toList()..sort((a, b) => b.value.qty.compareTo(a.value.qty));

  void add(Trx t) {
    trxCount += 1;
    for (final l in t.lines) {
      final x = items.putIfAbsent(l.name, () => _Sold());
      x.qty += l.qty;
      x.value += l.price * l.qty;
    }
  }
}

const _hari = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
const _bulanPanjang = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'];

/// Rekap penjualan per menu.
/// - Harian: apa saja yang terjual pada satu hari.
/// - Mingguan / Bulanan: gabungan (global) hasil penjualan harian, plus rincian tiap harinya.
/// Akun bos: data dari Supabase (bisa pilih cabang). Akun kasir (localOnly): data transaksi di HP, jadi tetap jalan saat offline.
class RekapMenuPage extends StatefulWidget {
  final bool localOnly;
  RekapMenuPage({super.key, this.localOnly = false});
  @override
  State<RekapMenuPage> createState() => _RekapMenuPageState();
}

class _RekapMenuPageState extends State<RekapMenuPage> {
  static const _semua = 'Semua Cabang';
  final modes = ['Harian', 'Mingguan', 'Bulanan'];
  String mode = 'Harian';
  late DateTime anchor;
  String branch = _semua;
  bool loading = false;
  String? error;
  List<Trx> remote = [];
  List<String> branchNames = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    anchor = DateTime(n.year, n.month, n.day);
    if (!widget.localOnly) {
      _loadBranches();
      _load();
    }
  }

  // ---------- rentang waktu ----------
  DateTime get _start {
    switch (mode) {
      case 'Mingguan':
        return DateTime(anchor.year, anchor.month, anchor.day - (anchor.weekday - 1));
      case 'Bulanan':
        return DateTime(anchor.year, anchor.month, 1);
      default:
        return DateTime(anchor.year, anchor.month, anchor.day);
    }
  }

  DateTime get _end {
    final s = _start;
    switch (mode) {
      case 'Mingguan':
        return DateTime(s.year, s.month, s.day + 7);
      case 'Bulanan':
        return DateTime(s.year, s.month + 1, 1);
      default:
        return DateTime(s.year, s.month, s.day + 1);
    }
  }

  String get _label {
    final s = _start;
    final e = DateTime(_end.year, _end.month, _end.day - 1);
    switch (mode) {
      case 'Mingguan':
        return '${tgl(s)} – ${tgl(e)}';
      case 'Bulanan':
        return '${_bulanPanjang[s.month - 1]} ${s.year}';
      default:
        return '${_hari[s.weekday - 1]}, ${tgl(s)}';
    }
  }

  bool get _isCurrent {
    final n = DateTime.now();
    return !n.isBefore(_start) && n.isBefore(_end);
  }

  void _move(int delta) {
    DateTime nd;
    switch (mode) {
      case 'Mingguan':
        nd = DateTime(anchor.year, anchor.month, anchor.day + 7 * delta);
        break;
      case 'Bulanan':
        nd = DateTime(anchor.year, anchor.month + delta, 1);
        break;
      default:
        nd = DateTime(anchor.year, anchor.month, anchor.day + delta);
    }
    if (nd.isAfter(DateTime.now())) return;
    setState(() => anchor = nd);
    _load();
  }

  Future<void> _pick() async {
    final d = await showDatePicker(context: context, initialDate: anchor, firstDate: DateTime(2024), lastDate: DateTime.now());
    if (d == null) return;
    setState(() => anchor = DateTime(d.year, d.month, d.day));
    _load();
  }

  // ---------- data ----------
  Future<void> _loadBranches() async {
    final names = await loadBranchNames();
    if (mounted) setState(() => branchNames = names);
  }

  Future<void> _load() async {
    if (widget.localOnly) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final from = _start.toUtc().toIso8601String();
      final to = _end.toUtc().toIso8601String();
      final all = <Trx>[];
      var offset = 0;
      // ambil per 1000 baris supaya rekap sebulan penuh tidak terpotong
      while (true) {
        final r = await sb
            .from('transactions')
            .select()
            .gte('created_at', from)
            .lt('created_at', to)
            .order('created_at', ascending: false)
            .range(offset, offset + 999);
        all.addAll([for (final e in r) Trx.fromCloud(Map<String, dynamic>.from(e as Map))]);
        if (r.length < 1000 || offset >= 29000) break;
        offset += 1000;
      }
      if (!mounted) return;
      setState(() {
        remote = all;
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

  List<Trx> _trxInRange(BuildContext context) {
    final src = widget.localOnly ? context.watch<AppState>().myTransactions : remote;
    final s = _start, e = _end;
    return src.where((t) {
      if (t.date.isBefore(s) || !t.date.isBefore(e)) return false;
      if (!widget.localOnly && branch != _semua && t.branch != branch) return false;
      return true;
    }).toList();
  }

  // ---------- teks WhatsApp ----------
  String _shareText(_Agg total, Map<DateTime, _Agg> perDay) {
    final store = context.read<AppState>().storeName;
    final b = StringBuffer();
    b.writeln('*REKAP PENJUALAN MENU ($mode)*');
    b.writeln(store);
    if (!widget.localOnly && branch != _semua) b.writeln('Cabang: $branch');
    if (widget.localOnly && context.read<AppState>().branch.isNotEmpty) b.writeln('Cabang: ${context.read<AppState>().branch}');
    b.writeln(_label);
    b.writeln('');
    b.writeln('Total: ${total.qty} porsi • ${total.trxCount} transaksi • ${rp(total.value)}');
    b.writeln('');
    var i = 1;
    for (final e in total.sorted) {
      b.writeln('${i++}. ${e.key}: ${e.value.qty} porsi (${rp(e.value.value)})');
    }
    if (mode != 'Harian' && perDay.isNotEmpty) {
      b.writeln('');
      b.writeln('*Per hari*');
      final days = perDay.keys.toList()..sort();
      for (final d in days) {
        final a = perDay[d]!;
        b.writeln('${_hari[d.weekday - 1]}, ${tgl(d)}: ${a.qty} porsi • ${rp(a.value)}');
      }
    }
    return b.toString().trimRight();
  }

  // ---------- tampilan ----------
  Widget _title(String t) => Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _itemRow(int rank, String name, _Sold x, int maxQty, {bool card = true}) {
    final row = Padding(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 26, child: Text('$rank', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.grey[600]))),
          Expanded(child: Text(name, style: TextStyle(fontWeight: FontWeight.w600))),
          Text('${x.qty} porsi', style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
        ]),
        SizedBox(height: 6),
        Row(children: [
          SizedBox(width: 26),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: maxQty == 0 ? 0 : x.qty / maxQty, minHeight: 5, backgroundColor: Color(0xFFE6EEFB), color: blue),
            ),
          ),
          SizedBox(width: 10),
          Text(rp(x.value), style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        ]),
      ]),
    );
    if (!card) return row;
    return Container(margin: EdgeInsets.only(bottom: 6), decoration: cardDeco(), child: row);
  }

  Widget _dayTile(DateTime d, _Agg a) {
    final list = a.sorted;
    final maxQty = list.isEmpty ? 0 : list.first.value.qty;
    return Container(
      margin: EdgeInsets.only(bottom: 6),
      decoration: cardDeco(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.symmetric(horizontal: 14),
          title: Text('${_hari[d.weekday - 1]}, ${tgl(d)}', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${a.qty} porsi • ${a.trxCount} transaksi', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          trailing: Text(rp(a.value), style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
          children: [
            for (var i = 0; i < list.length; i++) _itemRow(i + 1, list[i].key, list[i].value, maxQty, card: false),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _trxInRange(context);
    final total = _Agg();
    final perDay = <DateTime, _Agg>{};
    for (final t in list) {
      total.add(t);
      final k = DateTime(t.date.year, t.date.month, t.date.day);
      perDay.putIfAbsent(k, () => _Agg()).add(t);
    }
    final sorted = total.sorted;
    final maxQty = sorted.isEmpty ? 0 : sorted.first.value.qty;
    final days = perDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final st = context.watch<AppState>();
    final branchLabel = widget.localOnly ? st.branch : (branch == _semua ? 'Semua cabang' : branch);

    return Scaffold(
      appBar: AppBar(title: Text('Rekap Penjualan Menu'), backgroundColor: navy, foregroundColor: Colors.white),
      body: Column(children: [
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Column(children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final m in modes)
                  Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(m),
                      selected: mode == m,
                      showCheckmark: false,
                      selectedColor: blue,
                      backgroundColor: Colors.white,
                      labelStyle: TextStyle(color: mode == m ? Colors.white : navy, fontWeight: FontWeight.w600),
                      shape: StadiumBorder(side: BorderSide(color: lineColor)),
                      onSelected: (_) {
                        setState(() => mode = m);
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
            if (!widget.localOnly && branchNames.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final b in [_semua, ...branchNames])
                    Padding(
                      padding: EdgeInsets.only(right: 8, top: 6),
                      child: ChoiceChip(
                        label: Text(b),
                        selected: branch == b,
                        showCheckmark: false,
                        selectedColor: navy2,
                        backgroundColor: Colors.white,
                        labelStyle: TextStyle(color: branch == b ? Colors.white : navy, fontWeight: FontWeight.w600, fontSize: 12),
                        shape: StadiumBorder(side: BorderSide(color: lineColor)),
                        onSelected: (_) => setState(() => branch = b),
                      ),
                    ),
                ]),
              ),
            Row(children: [
              IconButton(onPressed: () => _move(-1), icon: Icon(Icons.chevron_left)),
              Expanded(
                child: InkWell(
                  onTap: _pick,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.calendar_today, size: 16, color: blue),
                      SizedBox(width: 8),
                      Flexible(child: Text('$_label${_isCurrent ? ' (sekarang)' : ''}', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                    ]),
                  ),
                ),
              ),
              IconButton(onPressed: _isCurrent ? null : () => _move(1), icon: Icon(Icons.chevron_right)),
            ]),
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
                            Text(mode == 'Harian' ? 'Terjual • $branchLabel' : 'Total terjual ${mode.toLowerCase()} • $branchLabel',
                                style: TextStyle(color: Color(0xFFB8C7DE))),
                            SizedBox(height: 4),
                            Text('${total.qty} porsi', style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                            SizedBox(height: 4),
                            Text('${total.trxCount} transaksi • ${sorted.length} jenis menu • ${rp(total.value)}', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                            if (mode != 'Harian') Text('Ada penjualan di ${days.length} hari', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
                            SizedBox(height: 2),
                            Text('Nilai dihitung dari harga menu x porsi (sebelum diskon & pajak)', style: TextStyle(color: Color(0xFF8FA6C6), fontSize: 11)),
                          ]),
                        ),
                        _title(mode == 'Harian' ? 'Menu terjual' : 'Menu terjual (gabungan semua hari)'),
                        if (sorted.isEmpty) Padding(padding: EdgeInsets.all(20), child: Center(child: Text('Belum ada penjualan di periode ini', style: TextStyle(color: Colors.grey)))),
                        for (var i = 0; i < sorted.length; i++) _itemRow(i + 1, sorted[i].key, sorted[i].value, maxQty),
                        if (mode != 'Harian' && days.isNotEmpty) ...[
                          _title('Rekap per hari'),
                          for (final d in days) _dayTile(d, perDay[d]!),
                        ],
                        if (sorted.isNotEmpty) ...[
                          SizedBox(height: 8),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                            onPressed: () => sendWhatsApp(context, _shareText(total, perDay), chooseContact: true),
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
}
