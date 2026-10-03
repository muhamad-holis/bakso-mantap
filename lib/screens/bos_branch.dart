import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud.dart';
import '../theme.dart';

/// Bos: buka cabang baru, atur jumlah meja, dan tetapkan akun kasir ke cabang.
class BosBranchPage extends StatefulWidget {
  BosBranchPage({super.key});
  @override
  State<BosBranchPage> createState() => _BosBranchPageState();
}

class _BosBranchPageState extends State<BosBranchPage> {
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> kasirs = [];
  Map<String, int> menuCount = {};
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _load() async {
    try {
      final b = await sb.from('branches').select().order('name');
      final p = await sb.from('profiles').select('id, name, role, branch');
      final m = await sb.from('menu_branch').select('branch');
      final cnt = <String, int>{};
      for (final e in m) {
        final k = (e['branch'] as String?) ?? '';
        cnt[k] = (cnt[k] ?? 0) + 1;
      }
      if (!mounted) return;
      setState(() {
        branches = [for (final e in b) Map<String, dynamic>.from(e as Map)];
        kasirs = [
          for (final e in p)
            if (e['role'] != 'bos') Map<String, dynamic>.from(e as Map),
        ]..sort((x, y) {
            final ux = ((x['branch'] as String?) ?? '').isEmpty ? 0 : 1;
            final uy = ((y['branch'] as String?) ?? '').isEmpty ? 0 : 1;
            return ux != uy ? ux.compareTo(uy) : ((x['name'] as String?) ?? '').compareTo((y['name'] as String?) ?? '');
          });
        menuCount = cnt;
        error = null;
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

  Future<void> _newBranch() async {
    final name = TextEditingController();
    final tables = TextEditingController(text: '20');
    var src = '';
    final existing = branches.map((b) => b['name'] as String).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) {
          final n = name.text.trim();
          final dup = existing.any((e) => e.toLowerCase() == n.toLowerCase());
          final t = int.tryParse(tables.text) ?? 0;
          final valid = n.isNotEmpty && !dup && t >= 1 && t <= 200;
          return AlertDialog(
            title: Text('Buka Cabang Baru'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: 'Nama cabang', hintText: 'Contoh: Cabang Sentul', errorText: dup ? 'Nama cabang sudah ada' : null),
                ),
                TextField(
                  controller: tables,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  onChanged: (_) => setS(() {}),
                  decoration: InputDecoration(labelText: 'Jumlah meja (1-200)'),
                ),
                if (existing.isNotEmpty) ...[
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: src,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: 'Salin menu & harga dari'),
                    items: [
                      DropdownMenuItem(value: '', child: Text('Tidak usah (menu kosong)')),
                      for (final e in existing) DropdownMenuItem(value: e, child: Text(e)),
                    ],
                    onChanged: (v) => setS(() => src = v ?? ''),
                  ),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
              FilledButton(onPressed: valid ? () => Navigator.pop(d, true) : null, child: Text('Buat Cabang')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final nm = name.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    setState(() => busy = true);
    try {
      await sb.from('branches').insert({'name': nm, 'table_count': int.tryParse(tables.text) ?? 20});
      var copied = 0;
      if (src.isNotEmpty) {
        final r = await sb.from('menu_branch').select().eq('branch', src);
        final add = [
          for (final e in r) {'menu_id': e['menu_id'], 'branch': nm, 'price': e['price'], 'image_url': e['image_url'] ?? ''},
        ];
        if (add.isNotEmpty) await sb.from('menu_branch').upsert(add);
        copied = add.length;
      }
      await _load();
      if (mounted) await _afterCreate(nm, copied);
    } catch (e) {
      if (mounted) _toast('Gagal membuat cabang: $e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _afterCreate(String nm, int copied) {
    return showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Cabang "$nm" dibuat'),
        content: SingleChildScrollView(
          child: Text(
            '${copied > 0 ? '$copied menu disalin. Atur harga dan foto di tab Menu & Harga (pilih cabang $nm).' : 'Menu masih kosong. Isi lewat tab Menu & Harga, atau salin dari cabang lain.'}\n\n'
            'Langkah berikutnya untuk kasir:\n'
            '1. Buat akun kasir di Supabase: Authentication > Users > Add user (centang Auto Confirm User).\n'
            '2. Kembali ke halaman ini. Di bagian Akun Kasir, ketuk Tetapkan pada akun itu lalu pilih $nm.\n'
            '3. Di HP kasir, pasang aplikasi dan login dengan akun tersebut.',
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(d), child: Text('Mengerti'))],
      ),
    );
  }

  Future<void> _editTables(Map<String, dynamic> b) async {
    final name = b['name'] as String;
    final c = TextEditingController(text: '${(b['table_count'] as num?)?.toInt() ?? 20}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) {
          final t = int.tryParse(c.text) ?? 0;
          return AlertDialog(
            title: Text('Jumlah meja • $name'),
            content: TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
              onChanged: (_) => setS(() {}),
              decoration: InputDecoration(labelText: 'Jumlah meja (1-200)'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
              FilledButton(onPressed: (t >= 1 && t <= 200) ? () => Navigator.pop(d, true) : null, child: Text('Simpan')),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('branches').update({'table_count': int.tryParse(c.text) ?? 20}).eq('name', name);
      await _load();
      if (mounted) _toast('Tersimpan. HP kasir ikut berubah dalam ±30 detik');
    } catch (e) {
      if (mounted) _toast('Gagal menyimpan: $e');
    }
  }

  Future<void> _deleteBranch(Map<String, dynamic> b, int kasirCount) async {
    final name = b['name'] as String;
    if (kasirCount > 0) {
      _toast('Pindahkan dulu akun kasir di cabang ini ke cabang lain');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus cabang $name?'),
        content: Text('Daftar menu & harga cabang ini ikut dihapus. Riwayat transaksi yang sudah ada tetap tersimpan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('menu_branch').delete().eq('branch', name);
      await sb.from('branches').delete().eq('name', name);
      await _load();
    } catch (e) {
      if (mounted) _toast('Gagal menghapus: $e');
    }
  }

  Future<void> _assign(Map<String, dynamic> k) async {
    final names = branches.map((b) => b['name'] as String).toList();
    final pick = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Tetapkan ${k['name']} ke cabang…'),
        children: [
          for (final n in names) SimpleDialogOption(onPressed: () => Navigator.pop(d, n), child: Text(n)),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, ''), child: Text('Tanpa cabang', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (pick == null) return;
    try {
      await sb.from('profiles').update({'branch': pick}).eq('id', k['id'] as String);
      await _load();
      if (mounted) _toast('Tersimpan. Berlaku saat kasir membuka ulang aplikasi (atau keluar lalu masuk lagi)');
    } catch (e) {
      if (mounted) _toast('Gagal menyimpan: $e');
    }
  }

  Widget _section(String t) => Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: navy)),
      );

  Widget _branchTile(Map<String, dynamic> b) {
    final name = b['name'] as String;
    final tables = (b['table_count'] as num?)?.toInt() ?? 20;
    final ks = kasirs.where((k) => k['branch'] == name).toList();
    final menus = menuCount[name] ?? 0;
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: cardDeco(),
      child: ListTile(
        title: Text(name, style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('$tables meja • ${menus == 0 ? 'belum ada menu' : '$menus menu'}\n${ks.isEmpty ? 'Belum ada kasir' : 'Kasir: ${ks.map((k) => k['name']).join(', ')}'}'),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'meja' ? _editTables(b) : _deleteBranch(b, ks.length),
          itemBuilder: (_) => [
            PopupMenuItem(value: 'meja', child: Text('Ubah jumlah meja')),
            PopupMenuItem(value: 'hapus', child: Text('Hapus cabang')),
          ],
        ),
      ),
    );
  }

  Widget _kasirTile(Map<String, dynamic> k) {
    final br = (k['branch'] as String?) ?? '';
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: cardDeco(),
      child: ListTile(
        title: Text((k['name'] as String?) ?? '-', style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: br.isEmpty
            ? Text('Belum ditetapkan ke cabang', style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600))
            : Text('Cabang: $br'),
        trailing: TextButton(onPressed: busy ? null : () => _assign(k), child: Text(br.isEmpty ? 'Tetapkan' : 'Pindah')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (loading) {
      body = Center(child: CircularProgressIndicator());
    } else if (error != null) {
      body = Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Gagal memuat data cabang.\nJalankan supabase_update_cabang.sql di Supabase, lalu coba lagi.\n\n$error', textAlign: TextAlign.center),
            SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() => loading = true);
                _load();
              },
              child: Text('Coba lagi'),
            ),
          ]),
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.fromLTRB(12, 4, 12, 90), children: [
          _section('Cabang'),
          if (branches.isEmpty) Text('Belum ada cabang. Ketuk "Buka Cabang Baru".', style: TextStyle(color: Colors.grey)),
          for (final b in branches) _branchTile(b),
          _section('Akun Kasir'),
          if (kasirs.isEmpty)
            Text('Belum ada akun kasir. Buat di Supabase: Authentication > Users > Add user.', style: TextStyle(color: Colors.grey)),
          for (final k in kasirs) _kasirTile(k),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Cabang & Akun Kasir'), backgroundColor: navy, foregroundColor: Colors.white),
      floatingActionButton: error != null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              onPressed: busy ? null : _newBranch,
              icon: Icon(Icons.add_business),
              label: Text('Buka Cabang Baru'),
            ),
      body: Stack(children: [body, if (busy) Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 3))]),
    );
  }
}
