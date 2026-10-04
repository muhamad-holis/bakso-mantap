import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import '../cloud.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'bos_branch.dart';
import 'bos_expense.dart';
import 'bos_page.dart';

class BosShell extends StatefulWidget {
  BosShell({super.key});
  @override
  State<BosShell> createState() => _BosShellState();
}

class _BosShellState extends State<BosShell> {
  int idx = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: idx, children: [BosPage(), BosExpensePage(), BosMenuPage(), BosSettingsPage()]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) => setState(() => idx = i),
        destinations: [
          NavigationDestination(icon: Icon(Icons.insights), label: 'Pantau'),
          NavigationDestination(icon: Icon(Icons.shopping_basket_outlined), label: 'Pengeluaran'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Menu & Harga'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Pengaturan'),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  final String title;
  final String sub;
  _Head(this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Container(
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
                Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                Text(sub, style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
              ]),
            ),
            IconButton(tooltip: 'Keluar', icon: Icon(Icons.logout, color: Colors.white), onPressed: () => context.read<AppState>().logout()),
          ]),
        ),
      ),
    );
  }
}

// ================= MENU & HARGA (hanya bos) =================
// Bos memilih cabang dulu. Harga & foto yang diubah hanya berlaku di cabang itu.
class BosMenuPage extends StatefulWidget {
  BosMenuPage({super.key});
  @override
  State<BosMenuPage> createState() => _BosMenuPageState();
}

class _BosMenuPageState extends State<BosMenuPage> {
  final picker = ImagePicker();
  List<String> branches = [];
  String? branch;
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  bool saving = false;
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

  Future<void> _loadBranches() async {
    try {
      final list = await loadBranchNames();
      if (!mounted) return;
      setState(() {
        branches = list;
        if (branch == null || !list.contains(branch)) branch = list.isEmpty ? null : list.first;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> _load() async {
    final br = branch;
    if (br == null) {
      if (mounted) setState(() => loading = false);
      return;
    }
    if (mounted) setState(() => loading = true);
    try {
      final r = await sb.from('menu_branch').select('menu_id, price, image_url, menus(id, name, category, emoji)').eq('branch', br);
      final list = [
        for (final e in r)
          if (e['menus'] != null) Map<String, dynamic>.from(e),
      ]..sort((a, b) {
          final ma = a['menus'] as Map, mb = b['menus'] as Map;
          final x = (ma['category'] as String).compareTo(mb['category'] as String);
          return x != 0 ? x : (ma['name'] as String).compareTo(mb['name'] as String);
        });
      if (mounted) {
        setState(() {
          rows = list;
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

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  MenuItem _item(Map<String, dynamic> r) {
    final m = r['menus'] as Map;
    return MenuItem(
      id: m['id'] as String,
      name: m['name'] as String,
      category: m['category'] as String,
      price: (r['price'] as num).toInt(),
      emoji: (m['emoji'] as String?) ?? '🍜',
      imageUrl: (r['image_url'] as String?) ?? '',
    );
  }

  String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');

  String _newId(String n, List<String> existing) {
    var id = _slug(n);
    if (id.isEmpty || existing.contains(id)) id = '$id-${DateTime.now().millisecondsSinceEpoch}';
    return id;
  }

  /// Unggah foto ke Supabase Storage, folder per cabang. Mengembalikan URL publik.
  Future<String> _upload(XFile f, String menuId, String br) async {
    final bytes = await f.readAsBytes();
    final png = f.name.toLowerCase().endsWith('.png');
    final path = '${_slug(br)}/$menuId-${DateTime.now().millisecondsSinceEpoch}.${png ? 'png' : 'jpg'}';
    await sb.storage.from('menu-images').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: png ? 'image/png' : 'image/jpeg'),
        );
    return sb.storage.from('menu-images').getPublicUrl(path);
  }

  Future<void> _edit(Map<String, dynamic>? row) async {
    final br = branch;
    if (br == null) {
      _msg('Pilih cabang dulu');
      return;
    }
    final cur = row == null ? null : _item(row);
    final name = TextEditingController(text: cur?.name ?? '');
    final price = TextEditingController(text: cur == null ? '' : '${cur.price}');
    final cat = TextEditingController(text: cur?.category ?? 'Bakso');
    final emoji = TextEditingController(text: cur?.emoji ?? '🍜');
    final others = branches.where((b) => b != br).toList();
    final extra = <String>{};
    XFile? picked;
    Uint8List? preview;

    Future<void> pick(StateSetter setS, ImageSource src) async {
      try {
        final f = await picker.pickImage(source: src, maxWidth: 900, maxHeight: 900, imageQuality: 80);
        if (f == null) return;
        final b = await f.readAsBytes();
        setS(() {
          picked = f;
          preview = b;
        });
      } catch (e) {
        _msg('Gagal membuka foto: $e');
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setS) => AlertDialog(
          title: Text(cur == null ? 'Tambah Menu' : 'Edit Menu'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: Color(0xFFE6EEFB), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(Icons.store, size: 18, color: navy),
                  SizedBox(width: 6),
                  Expanded(child: Text('Cabang: $br', style: TextStyle(fontWeight: FontWeight.w800, color: navy))),
                ]),
              ),
              SizedBox(height: 12),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 120,
                    height: 120,
                    child: preview != null
                        ? Image.memory(preview!, fit: BoxFit.cover)
                        : (cur != null
                            ? MenuImage(cur, size: 120)
                            : Container(color: Color(0xFFE6EEFB), alignment: Alignment.center, child: Text(emoji.text, style: TextStyle(fontSize: 48)))),
                  ),
                ),
              ),
              SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(setS, ImageSource.gallery), icon: Icon(Icons.photo_library_outlined, size: 18), label: Text('Galeri'))),
                SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: () => pick(setS, ImageSource.camera), icon: Icon(Icons.photo_camera_outlined, size: 18), label: Text('Kamera'))),
              ]),
              Text('Foto hanya untuk cabang $br', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              TextField(controller: name, decoration: InputDecoration(labelText: 'Nama menu')),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Harga di $br (Rp)')),
              TextField(controller: cat, decoration: InputDecoration(labelText: 'Kategori')),
              SizedBox(height: 6),
              Wrap(spacing: 6, children: [
                for (final c in ['Bakso', 'Mie', 'Makanan', 'Minuman', 'Paket'])
                  ActionChip(label: Text(c), onPressed: () => setS(() => cat.text = c)),
              ]),
              TextField(controller: emoji, decoration: InputDecoration(labelText: 'Emoji (jika tanpa foto)')),
              if (cur != null)
                Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Nama, kategori, dan emoji berlaku di semua cabang. Harga & foto hanya di $br.', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                ),
              if (cur == null && others.isNotEmpty) ...[
                SizedBox(height: 12),
                Text('Tambahkan juga ke cabang lain (harga & foto sama)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                for (final b in others)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(b),
                    value: extra.contains(b),
                    onChanged: (v) => setS(() {
                      if (v == true) {
                        extra.add(b);
                      } else {
                        extra.remove(b);
                      }
                    }),
                  ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Simpan')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final p = int.tryParse(price.text.trim()) ?? 0;
    final n = name.text.trim();
    if (n.isEmpty || p <= 0) {
      _msg('Nama dan harga wajib diisi');
      return;
    }
    final c = cat.text.trim().isEmpty ? 'Bakso' : cat.text.trim();
    final e = emoji.text.trim().isEmpty ? '🍜' : emoji.text.trim();

    setState(() => saving = true);
    try {
      String id;
      var img = cur?.imageUrl ?? '';
      if (cur == null) {
        final ex = await sb.from('menus').select('id');
        id = _newId(n, [for (final x in ex) x['id'] as String]);
      } else {
        id = cur.id;
      }
      if (picked != null) img = await _upload(picked!, id, br);
      if (cur == null) {
        await sb.from('menus').upsert({'id': id, 'name': n, 'category': c, 'price': p, 'emoji': e});
      } else {
        await sb.from('menus').update({'name': n, 'category': c, 'emoji': e}).eq('id', id);
      }
      final targets = cur == null ? <String>{br, ...extra} : <String>{br};
      await sb.from('menu_branch').upsert([
        for (final b in targets) {'menu_id': id, 'branch': b, 'price': p, 'image_url': img},
      ]);
      if (mounted) _msg('Tersimpan untuk $br. HP kasir ikut berubah dalam ±30 detik');
      await _load();
    } catch (err) {
      if (mounted) _msg('Gagal menyimpan: $err');
    }
    if (mounted) setState(() => saving = false);
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final br = branch;
    if (br == null) return;
    final item = _item(row);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus dari $br?'),
        content: Text('${item.name}\nHanya dihapus dari cabang $br, cabang lain tidak terpengaruh.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('menu_branch').delete().eq('menu_id', item.id).eq('branch', br);
      final left = await sb.from('menu_branch').select('menu_id').eq('menu_id', item.id);
      if (left.isEmpty) await sb.from('menus').delete().eq('id', item.id);
      await _load();
    } catch (e) {
      if (mounted) _msg('Gagal menghapus: $e');
    }
  }

  /// Salin semua menu (harga & foto) dari cabang lain ke cabang yang sedang dipilih.
  Future<void> _copyFrom() async {
    final br = branch;
    if (br == null) return;
    final others = branches.where((b) => b != br).toList();
    final src = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: Text('Salin menu ke $br dari…'),
        children: [for (final b in others) SimpleDialogOption(onPressed: () => Navigator.pop(d, b), child: Text(b))],
      ),
    );
    if (src == null) return;
    try {
      final r = await sb.from('menu_branch').select().eq('branch', src);
      final have = {for (final x in rows) (x['menu_id'] as String)};
      final add = [
        for (final e in r)
          if (!have.contains(e['menu_id'] as String)) {'menu_id': e['menu_id'], 'branch': br, 'price': e['price'], 'image_url': e['image_url'] ?? ''},
      ];
      if (add.isEmpty) {
        _msg('Tidak ada menu baru untuk disalin');
        return;
      }
      await sb.from('menu_branch').upsert(add);
      _msg('${add.length} menu disalin ke $br. Atur harganya sesuai cabang ini');
      await _load();
    } catch (e) {
      if (mounted) _msg('Gagal menyalin: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (error != null && rows.isEmpty) {
      content = Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Gagal memuat menu.\n$error', textAlign: TextAlign.center)));
    } else if (branches.isEmpty && !loading) {
      content = Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Belum ada cabang. Isi kolom cabang pada akun kasir lebih dulu (lihat SETUP_BOS.md).', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
        ),
      );
    } else if (loading) {
      content = Center(child: CircularProgressIndicator());
    } else if (rows.isEmpty) {
      content = Center(child: Text('Belum ada menu di $branch.\nKetuk "Tambah Menu"${branches.length > 1 ? ' atau salin dari cabang lain' : ''}.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)));
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          physics: AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(12, 4, 12, 90),
          itemCount: rows.length,
          itemBuilder: (c, i) {
            final r = rows[i];
            final item = _item(r);
            return Container(
              margin: EdgeInsets.only(bottom: 8),
              decoration: cardDeco(),
              child: ListTile(
                leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: MenuImage(item, size: 56)),
                title: Text(item.name, style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.category),
                  Text(rp(item.price), style: TextStyle(fontWeight: FontWeight.w800, color: blue)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.edit_outlined), onPressed: () => _edit(r)),
                  IconButton(icon: Icon(Icons.delete_outline, color: Colors.red), onPressed: () => _delete(r)),
                ]),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      floatingActionButton: branch == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: blue,
              foregroundColor: Colors.white,
              onPressed: saving ? null : () => _edit(null),
              icon: Icon(Icons.add),
              label: Text('Tambah Menu'),
            ),
      body: Column(children: [
        _Head('Menu & Harga', branch == null ? 'Pilih cabang' : 'Cabang: $branch'),
        if (saving) LinearProgressIndicator(minHeight: 3),
        if (branches.isNotEmpty) ...[
          Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text('Pilih cabang dulu:', style: TextStyle(fontWeight: FontWeight.w700, color: navy)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final b in branches)
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
                      onSelected: (_) {
                        if (branch == b) return;
                        setState(() => branch = b);
                        _load();
                      },
                    ),
                  ),
              ]),
            ),
          ),
          if (branches.length > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 6),
                child: TextButton.icon(onPressed: saving ? null : _copyFrom, icon: Icon(Icons.copy_all, size: 18), label: Text('Salin menu dari cabang lain')),
              ),
            ),
        ],
        Expanded(child: content),
      ]),
    );
  }
}

// ================= PENGATURAN BOS =================
class BosSettingsPage extends StatefulWidget {
  BosSettingsPage({super.key});
  @override
  State<BosSettingsPage> createState() => _BosSettingsPageState();
}

class _BosSettingsPageState extends State<BosSettingsPage> {
  late final TextEditingController store;
  late final TextEditingController tax;
  late final TextEditingController bankName;
  late final TextEditingController bankAcc;
  late final TextEditingController bankHolder;
  String qrisUrl = ''; // QRIS cabang yang sedang dipilih
  Map<String, String> qrisMap = {}; // nama cabang -> URL QRIS (app_settings: qris_url@<cabang>)
  List<String> qrisBranches = [];
  String? qrisBranch;
  bool uploading = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    store = TextEditingController(text: s.storeName);
    tax = TextEditingController(text: '${s.taxPercent}');
    bankName = TextEditingController(text: s.bankName);
    bankAcc = TextEditingController(text: s.bankAccount);
    bankHolder = TextEditingController(text: s.bankHolder);
    _loadQris();
    s.pullConfig().then((_) {
      if (!mounted) return;
      store.text = s.storeName;
      tax.text = '${s.taxPercent}';
      bankName.text = s.bankName;
      bankAcc.text = s.bankAccount;
      bankHolder.text = s.bankHolder;
    });
  }

  @override
  void dispose() {
    store.dispose();
    tax.dispose();
    bankName.dispose();
    bankAcc.dispose();
    bankHolder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final name = store.text.trim().isEmpty ? 'Bakso TITATI Wonogiri Opik Jon' : store.text.trim();
    final t = (int.tryParse(tax.text) ?? 0).clamp(0, 100);
    setState(() => saving = true);
    try {
      await sb.from('app_settings').upsert([
        {'key': 'store_name', 'value': name},
        {'key': 'tax_percent', 'value': '$t'},
      ]);
      s.saveSettings(name, s.kasir, t);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tersimpan. HP kasir ikut berubah dalam ±30 detik')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
    }
    if (mounted) setState(() => saving = false);
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  /// Pilih gambar QRIS dari galeri dan unggah ke Supabase Storage (folder pembayaran/).
  Future<void> _pickQris() async {
    final b = qrisBranch;
    if (b == null) {
      _toast('Pilih cabang dulu');
      return;
    }
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (f == null) return;
      setState(() => uploading = true);
      final bytes = await f.readAsBytes();
      final png = f.name.toLowerCase().endsWith('.png');
      final path = 'pembayaran/qris-${DateTime.now().millisecondsSinceEpoch}.${png ? 'png' : 'jpg'}';
      await sb.storage.from('menu-images').uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: png ? 'image/png' : 'image/jpeg'),
          );
      final url = sb.storage.from('menu-images').getPublicUrl(path);
      await sb.from('app_settings').upsert({'key': 'qris_url@$b', 'value': url});
      if (mounted) {
        setState(() {
          qrisMap[b] = url;
          if (qrisBranch == b) qrisUrl = url;
        });
      }
      _toast('QRIS cabang $b tersimpan. HP kasir cabang itu ikut berubah dalam ±30 detik');
    } catch (e) {
      if (mounted) _toast('Gagal mengunggah gambar: $e');
    }
    if (mounted) setState(() => uploading = false);
  }

  Future<void> _loadQris() async {
    try {
      final names = await loadBranchNames();
      final rows = await sb.from('app_settings').select().like('key', 'qris_url@%');
      final map = <String, String>{};
      for (final r in rows) {
        final k = r['key'] as String;
        map[k.substring('qris_url@'.length)] = (r['value'] as String?) ?? '';
      }
      if (!mounted) return;
      setState(() {
        qrisBranches = names;
        qrisMap = map;
        if (qrisBranch == null || !names.contains(qrisBranch)) qrisBranch = names.isEmpty ? null : names.first;
        qrisUrl = qrisMap[qrisBranch ?? ''] ?? '';
      });
    } catch (_) {}
  }

  void _selectQrisBranch(String b) {
    setState(() {
      qrisBranch = b;
      qrisUrl = qrisMap[b] ?? '';
    });
  }

  Future<void> _deleteQris() async {
    final b = qrisBranch;
    if (b == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Hapus QRIS $b?'),
        content: Text('Kasir cabang ini tidak akan melihat QRIS sampai Anda mengunggah yang baru.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await sb.from('app_settings').delete().eq('key', 'qris_url@$b');
      if (mounted) {
        setState(() {
          qrisMap.remove(b);
          if (qrisBranch == b) qrisUrl = '';
        });
      }
      _toast('QRIS cabang $b dihapus');
    } catch (e) {
      if (mounted) _toast('Gagal menghapus: $e');
    }
  }

  Future<void> _savePay() async {
    final s = context.read<AppState>();
    final bn = bankName.text.trim(), ba = bankAcc.text.trim(), bh = bankHolder.text.trim();
    setState(() => saving = true);
    try {
      await sb.from('app_settings').upsert([
        {'key': 'bank_name', 'value': bn},
        {'key': 'bank_account', 'value': ba},
        {'key': 'bank_holder', 'value': bh},
      ]);
      s.savePayment(s.qrisUrl, bn, ba, bh);
      if (mounted) _toast('Tersimpan. HP kasir semua cabang ikut berubah dalam ±30 detik');
    } catch (e) {
      if (mounted) _toast('Gagal menyimpan: $e');
    }
    if (mounted) setState(() => saving = false);
  }

  Widget _payCard() {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: cardDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pembayaran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        SizedBox(height: 2),
        Text('QRIS diatur per cabang. Transfer bank berlaku di semua cabang.', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
        SizedBox(height: 14),
        Text('Gambar QRIS per cabang', style: TextStyle(fontWeight: FontWeight.w700)),
        SizedBox(height: 8),
        if (qrisBranches.isEmpty)
          Text('Belum ada cabang. Buat cabang dulu di Kelola Cabang.', style: TextStyle(color: Colors.grey[700], fontSize: 12))
        else
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final b in qrisBranches)
              ChoiceChip(
                label: Text((qrisMap[b] ?? '').isNotEmpty ? '$b  ✓' : b),
                selected: qrisBranch == b,
                onSelected: uploading ? null : (_) => _selectQrisBranch(b),
              ),
          ]),
        SizedBox(height: 4),
        Text('Pilih cabang, lalu unggah gambar QRIS-nya. Tanda ✓ = sudah ada QRIS.', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
        SizedBox(height: 8),
        if (qrisUrl.isNotEmpty)
          Center(
            child: Container(
              color: Colors.white,
              constraints: BoxConstraints(maxHeight: 260),
              child: CachedNetworkImage(
                imageUrl: qrisUrl,
                fit: BoxFit.contain,
                placeholder: (_, __) => Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()),
                errorWidget: (_, __, ___) => Padding(padding: EdgeInsets.all(20), child: Text('Gambar tidak dapat dimuat')),
              ),
            ),
          )
        else
          Container(
            height: 90,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: lineColor)),
            child: Text('Belum ada gambar QRIS', style: TextStyle(color: Colors.grey[600])),
          ),
        SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: (uploading || qrisBranch == null) ? null : _pickQris,
              icon: Icon(Icons.qr_code_2),
              label: Text(qrisUrl.isEmpty ? 'Pilih Gambar QRIS' : 'Ganti Gambar'),
            ),
          ),
          if (qrisUrl.isNotEmpty) ...[
            SizedBox(width: 8),
            OutlinedButton(
              onPressed: uploading ? null : _deleteQris,
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              child: Icon(Icons.delete_outline),
            ),
          ],
        ]),
        if (uploading) Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
        SizedBox(height: 16),
        Text('Transfer Bank', style: TextStyle(fontWeight: FontWeight.w700)),
        TextField(controller: bankName, textCapitalization: TextCapitalization.characters, decoration: InputDecoration(labelText: 'Nama bank / e-wallet (mis. BCA)')),
        TextField(
          controller: bankAcc,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Nomor rekening'),
        ),
        TextField(controller: bankHolder, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: 'Atas nama')),
        SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: Size.fromHeight(48)),
            onPressed: (saving || uploading) ? null : _savePay,
            child: Text('Simpan Transfer Bank untuk Semua Cabang'),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        _Head('Pengaturan', sb.auth.currentUser?.email ?? 'Bos'),
        Expanded(
          child: ListView(padding: EdgeInsets.all(12), children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: cardDeco(),
              child: Column(children: [
                TextField(controller: store, decoration: InputDecoration(labelText: 'Nama toko')),
                TextField(controller: tax, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Pajak PPN (%) — isi 0 jika tanpa pajak')),
                SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: Size.fromHeight(48)),
                    onPressed: saving ? null : _save,
                    child: Text('Simpan untuk Semua Cabang'),
                  ),
                ),
              ]),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(14),
              decoration: cardDeco(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Cabang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                SizedBox(height: 2),
                Text('Buka cabang baru, atur jumlah meja, dan tetapkan akun kasir ke cabang.', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(46)),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BosBranchPage())),
                  icon: Icon(Icons.storefront),
                  label: Text('Kelola Cabang & Akun Kasir'),
                ),
              ]),
            ),
            SizedBox(height: 12),
            _payCard(),
            SizedBox(height: 24),
          ]),
        ),
      ]),
    );
  }
}
