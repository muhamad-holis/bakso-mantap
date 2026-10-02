import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud.dart';
import 'config.dart';
import 'models.dart';
import 'utils.dart';

class AppState extends ChangeNotifier {
  List<MenuItem> menus = [];
  final Map<String, CartLine> cart = {};
  List<Trx> transactions = [];
  String storeName = 'Bakso TITATI Wonogiri Opik Jon';
  String tagline = 'Fresh • Lezat • Selalu di Hati';
  String kasir = 'admin';
  String branch = '';
  int taxPercent = 11;
  int discount = 0;
  late SharedPreferences _p;

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    storeName = _p.getString('storeName') ?? storeName;
    kasir = _p.getString('kasir') ?? kasir;
    taxPercent = _p.getInt('tax') ?? taxPercent;
    final m = _p.getString('menus');
    menus = m == null
        ? _defaultMenus()
        : (jsonDecode(m) as List).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
    final t = _p.getString('trx');
    transactions =
        t == null ? [] : (jsonDecode(t) as List).map((e) => Trx.fromJson(e as Map<String, dynamic>)).toList();
  }

  List<MenuItem> _defaultMenus() => [
        MenuItem(id: 'bakso-urat', name: 'Bakso Urat', category: 'Bakso', price: 15000, emoji: '🍲'),
        MenuItem(id: 'bakso-halus', name: 'Bakso Halus', category: 'Bakso', price: 13000, emoji: '🍲'),
        MenuItem(id: 'bakso-jumbo', name: 'Bakso Jumbo', category: 'Bakso', price: 18000, emoji: '🍲'),
        MenuItem(id: 'mie-ayam-bakso', name: 'Mie Ayam Bakso', category: 'Mie', price: 15000, emoji: '🍜'),
        MenuItem(id: 'mie-ayam', name: 'Mie Ayam', category: 'Mie', price: 12000, emoji: '🍜'),
        MenuItem(id: 'es-teh-manis', name: 'Es Teh Manis', category: 'Minuman', price: 5000, emoji: '🧋'),
        MenuItem(id: 'es-jeruk', name: 'Es Jeruk', category: 'Minuman', price: 6000, emoji: '🍊'),
        MenuItem(id: 'es-nutrisari', name: 'Es Nutrisari', category: 'Minuman', price: 5000, emoji: '🥤'),
        MenuItem(id: 'paket-hemat', name: 'Paket Hemat', category: 'Paket', price: 18000, emoji: '🍱'),
      ];

  void _save() {
    _p.setString('menus', jsonEncode(menus.map((e) => e.toJson()).toList()));
    _p.setString('trx', jsonEncode(transactions.map((e) => e.toJson()).toList()));
    _p.setString('storeName', storeName);
    _p.setString('kasir', kasir);
    _p.setInt('tax', taxPercent);
  }

  List<String> get categories => ['Semua', ...{...menus.map((e) => e.category)}];

  // ---- keranjang ----
  void addToCart(MenuItem m) {
    final l = cart[m.id];
    if (l == null) {
      cart[m.id] = CartLine(m, 1);
    } else {
      l.qty++;
    }
    notifyListeners();
  }

  void inc(String id) {
    final l = cart[id];
    if (l != null) l.qty++;
    notifyListeners();
  }

  void dec(String id) {
    final l = cart[id];
    if (l == null) return;
    if (l.qty <= 1) {
      cart.remove(id);
    } else {
      l.qty--;
    }
    notifyListeners();
  }

  void remove(String id) {
    cart.remove(id);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    discount = 0;
    notifyListeners();
  }

  void setDiscount(int v) {
    discount = v < 0 ? 0 : (v > subtotal ? subtotal : v);
    notifyListeners();
  }

  int get itemCount => cart.values.fold(0, (a, l) => a + l.qty);
  int get subtotal => cart.values.fold(0, (a, l) => a + l.total);
  int get taxable => subtotal > discount ? subtotal - discount : 0;
  int get tax => (taxable * taxPercent / 100).round();
  int get total => taxable + tax;

  Trx checkout({required String method, required int paid, String note = ''}) {
    final now = DateTime.now();
    final seq = transactions.where((t) => t.date.year == now.year && t.date.month == now.month && t.date.day == now.day).length + 1;
    final rnd = (now.microsecondsSinceEpoch % 46656).toRadixString(36).toUpperCase().padLeft(3, '0');
    final id = 'TRX${now.year}${two(now.month)}${two(now.day)}${seq.toString().padLeft(4, '0')}-$rnd';
    final t = Trx(
      id: id,
      date: now,
      kasir: kasir,
      lines: cart.values.map((l) => TrxLine(l.item.name, l.item.price, l.qty)).toList(),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      change: paid > total ? paid - total : 0,
      method: method,
      note: note,
      branch: branch,
    );
    transactions.insert(0, t);
    cart.clear();
    discount = 0;
    _save();
    notifyListeners();
    syncPending();
    return t;
  }

  // ---- sinkron ke bos (Supabase) ----
  Timer? _timer;
  bool _syncing = false;

  int get pendingCount => transactions.where((t) => !t.synced).length;

  void setKasirQuiet(String name, [String br = '']) {
    kasir = name;
    branch = br;
  }

  void startSync() {
    if (!cloudEnabled) return;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      syncPending();
      pullConfig();
    });
    syncPending();
    pullConfig();
  }

  Future<void> syncPending() async {
    if (!cloudEnabled || _syncing || sb.auth.currentSession == null) return;
    _syncing = true;
    try {
      for (final t in transactions.where((t) => !t.synced).toList()) {
        try {
          await sb.from('transactions').upsert(t.toCloud(), onConflict: 'id', ignoreDuplicates: true);
          t.synced = true;
        } catch (_) {
          break; // kemungkinan offline, coba lagi nanti
        }
      }
      _save();
      notifyListeners();
    } finally {
      _syncing = false;
    }
  }

  /// Ambil menu, harga, nama toko & pajak yang diatur bos.
  Future<void> pullConfig() async {
    if (!cloudEnabled || sb.auth.currentSession == null) return;
    try {
      String sig() => '${jsonEncode(menus.map((e) => e.toJson()).toList())}|$taxPercent|$storeName';
      final before = sig();

      // menu, harga, dan foto khusus cabang HP ini
      final rows = await sb
          .from('menu_branch')
          .select('price, image_url, menus(id, name, category, emoji)')
          .eq('branch', branch);
      if (rows.isNotEmpty) {
        final list = rows.where((e) => e['menus'] != null).map((e) {
          final m = Map<String, dynamic>.from(e['menus'] as Map);
          return MenuItem(
            id: m['id'] as String,
            name: m['name'] as String,
            category: m['category'] as String,
            price: (e['price'] as num).toInt(),
            emoji: (m['emoji'] as String?) ?? '🍜',
            imageUrl: (e['image_url'] as String?) ?? '',
          );
        }).toList()
          ..sort((a, b) {
            final c = a.category.compareTo(b.category);
            return c != 0 ? c : a.name.compareTo(b.name);
          });
        menus = list;
        final byId = {for (final m in list) m.id: m};
        final old = Map<String, CartLine>.from(cart);
        cart.clear();
        for (final e in old.entries) {
          final m = byId[e.key];
          if (m != null) cart[e.key] = CartLine(m, e.value.qty);
        }
      }

      final st = await sb.from('app_settings').select();
      for (final r in st) {
        final k = r['key'] as String;
        final v = r['value'] as String;
        if (k == 'store_name' && v.isNotEmpty) storeName = v;
        if (k == 'tax_percent') taxPercent = int.tryParse(v) ?? taxPercent;
      }

      if (sig() != before) {
        _save();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> logout() async {
    _timer?.cancel();
    _timer = null;
    await sb.auth.signOut();
  }

  // ---- menu ----
  void saveMenu(MenuItem? m, String name, int price, String category, String emoji) {
    if (m != null) {
      m.name = name;
      m.price = price;
      m.category = category;
      m.emoji = emoji;
    } else {
      var id = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
      if (id.isEmpty || menus.any((e) => e.id == id)) id = '$id-${DateTime.now().millisecondsSinceEpoch}';
      menus.add(MenuItem(id: id, name: name, category: category, price: price, emoji: emoji));
    }
    _save();
    notifyListeners();
  }

  void deleteMenu(MenuItem m) {
    menus.remove(m);
    cart.remove(m.id);
    _save();
    notifyListeners();
  }

  // ---- pengaturan ----
  void saveSettings(String store, String kasirName, int tax) {
    storeName = store;
    kasir = kasirName;
    taxPercent = tax;
    _save();
    notifyListeners();
  }

  void clearTransactions() {
    transactions = [];
    _save();
    notifyListeners();
  }
}
