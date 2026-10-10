import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'cloud.dart';
import 'config.dart';
import 'models.dart';
import 'utils.dart';

/// Hasil menyimpan pesanan terbuka.
class SaveResult {
  final String? error;
  final OpenOrder? order;
  final List<OpenLine> added; // item baru pada penyimpanan ini (untuk bon dapur)
  final bool merged; // true = digabung ke pesanan meja yang sudah ada
  SaveResult({this.error, this.order, this.added = const [], this.merged = false});
}

class AppState extends ChangeNotifier {
  List<MenuItem> menus = [];
  final Map<String, CartLine> cart = {};
  List<Trx> transactions = [];
  String storeName = 'Bakso TITATI Wonogiri Opik Jon';
  String tagline = 'Fresh • Lezat • Selalu di Hati';
  String kasir = 'admin';
  String branch = '';
  int taxPercent = 11;
  int tableCount = defaultTableCount; // jumlah meja cabang ini (diatur bos)
  // pengaturan pembayaran dari bos (sinkron ke semua cabang)
  String qrisUrl = '';
  String bankName = '';
  String bankAccount = '';
  String bankHolder = '';
  String bosWa = ''; // nomor WhatsApp bos: tujuan ringkasan tutup shift (diatur bos)
  int discount = 0;
  // info pesanan yang sedang dibuat di kasir
  String orderType = orderDineIn;
  String tableNo = '';
  String customerName = '';
  late SharedPreferences _p;
  int _lineSeq = 0;
  List<Shift> shifts = []; // terbaru di atas

  // ---- pesanan terbuka (makan dulu, bayar belakangan) ----
  OpenOrder? activeOrder; // pesanan terbuka yang sedang dimuat di keranjang
  List<OpenOrder> openOrders = []; // meja belum bayar di cabang ini
  String? openOrdersError;
  final ValueNotifier<int> tabRequest = ValueNotifier<int>(-1); // minta HomeShell pindah tab
  List<Map<String, String>> _pendingClose = []; // sudah dibayar, tapi status di server belum diperbarui

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    storeName = _p.getString('storeName') ?? storeName;
    kasir = _p.getString('kasir') ?? kasir;
    taxPercent = _p.getInt('tax') ?? taxPercent;
    tableCount = _p.getInt('tableCount') ?? defaultTableCount;
    qrisUrl = _p.getString('qrisUrl') ?? '';
    bankName = _p.getString('bankName') ?? '';
    bankAccount = _p.getString('bankAccount') ?? '';
    bankHolder = _p.getString('bankHolder') ?? '';
    bosWa = _p.getString('bosWa') ?? '';
    final m = _p.getString('menus');
    menus = m == null
        ? _defaultMenus()
        : (jsonDecode(m) as List).map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
    final t = _p.getString('trx');
    transactions =
        t == null ? [] : (jsonDecode(t) as List).map((e) => Trx.fromJson(e as Map<String, dynamic>)).toList();
    try {
      final sh = _p.getString('shifts');
      shifts = sh == null ? [] : (jsonDecode(sh) as List).map((e) => Shift.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      shifts = [];
    }
    try {
      final pc = _p.getString('pendingClose');
      _pendingClose = pc == null ? [] : (jsonDecode(pc) as List).map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      _pendingClose = [];
    }
    pruneShifts();
  }

  /// Riwayat shift di HP kasir yang sudah terkirim ke bos dan lebih dari 30 hari dibuang otomatis
  /// supaya tidak menumpuk. Shift yang belum terkirim tidak pernah dihapus.
  bool pruneShifts() {
    final cut = DateTime.now().subtract(const Duration(days: 30));
    final before = shifts.length;
    shifts.removeWhere((x) => !x.isOpen && x.synced && x.closedAt!.isBefore(cut));
    return shifts.length != before;
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
    _p.setString('shifts', jsonEncode(shifts.take(100).map((e) => e.toJson()).toList()));
    _p.setString('pendingClose', jsonEncode(_pendingClose));
    _p.setString('storeName', storeName);
    _p.setString('kasir', kasir);
    _p.setInt('tax', taxPercent);
    _p.setInt('tableCount', tableCount);
    _p.setString('qrisUrl', qrisUrl);
    _p.setString('bankName', bankName);
    _p.setString('bankAccount', bankAccount);
    _p.setString('bankHolder', bankHolder);
    _p.setString('bosWa', bosWa);
  }

  List<String> get categories => ['Semua', ...{...menus.map((e) => e.category)}];

  // ---- keranjang ----
  // Satu baris keranjang = satu menu + satu catatan. Menu yang sama dengan catatan berbeda jadi baris terpisah.
  String _newKey(String menuId) => '$menuId#${++_lineSeq}';

  int qtyOf(String menuId) => cart.values.where((l) => l.item.id == menuId).fold(0, (a, l) => a + l.qty);

  void addToCart(MenuItem m) {
    CartLine? l;
    for (final x in cart.values) {
      if (x.item.id == m.id && x.note.isEmpty) {
        l = x;
        break;
      }
    }
    if (l == null) {
      final k = _newKey(m.id);
      cart[k] = CartLine(k, m, 1);
    } else {
      l.qty++;
    }
    notifyListeners();
  }

  void inc(String key) {
    final l = cart[key];
    if (l != null) l.qty++;
    notifyListeners();
  }

  void dec(String key) {
    final l = cart[key];
    if (l == null) return;
    if (l.qty <= l.savedQty) return; // item yang sudah tersimpan hanya bisa dibatalkan oleh bos
    if (l.qty <= 1) {
      cart.remove(key);
    } else {
      l.qty--;
    }
    notifyListeners();
  }

  void remove(String key) {
    final l = cart[key];
    if (l != null && l.savedQty > 0) {
      l.qty = l.savedQty; // hanya porsi tambahan yang dibatalkan
    } else {
      cart.remove(key);
    }
    notifyListeners();
  }

  /// Isi/ubah/hapus catatan satu baris. [forQty] = berapa porsi yang memakai catatan ini;
  /// jika lebih sedikit dari jumlah baris, baris dipecah (sisanya tetap dengan catatan lama).
  void setLineNote(String key, String note, [int? forQty]) {
    final l = cart[key];
    if (l == null) return;
    if (l.savedQty > 0) return; // catatan item tersimpan tidak diubah kasir
    note = note.trim();
    final n = (forQty == null || forQty >= l.qty) ? l.qty : (forQty < 1 ? 1 : forQty);
    if (n >= l.qty) {
      l.note = note;
      _mergeLine(l);
    } else {
      l.qty -= n;
      CartLine? same;
      for (final o in cart.values) {
        if (o.item.id == l.item.id && o.note == note) {
          same = o;
          break;
        }
      }
      if (same != null) {
        same.qty += n;
      } else {
        final k = _newKey(l.item.id);
        cart[k] = CartLine(k, l.item, n, note: note);
      }
    }
    notifyListeners();
  }

  /// Gabungkan dengan baris lain yang menunya & catatannya sama.
  void _mergeLine(CartLine l) {
    CartLine? other;
    for (final o in cart.values) {
      if (o.key != l.key && o.item.id == l.item.id && o.note == l.note) {
        other = o;
        break;
      }
    }
    if (other != null) {
      other.qty += l.qty;
      cart.remove(l.key);
    }
  }

  void clearCart() {
    cart.clear();
    discount = 0;
    activeOrder = null;
    _resetOrder();
    notifyListeners();
  }

  // ---- info pesanan (meja & pelanggan) ----
  void _resetOrder() {
    orderType = orderDineIn;
    tableNo = '';
    customerName = '';
  }

  /// Bawa pulang tidak memakai nomor meja & nama pelanggan.
  void setOrderType(String t) {
    orderType = t;
    if (t == orderTakeaway) {
      tableNo = '';
      customerName = '';
    }
    notifyListeners();
  }

  void setTableNo(String v) {
    tableNo = v;
    notifyListeners();
  }

  /// Tanpa notifyListeners agar tidak rebuild tiap ketukan huruf.
  void setCustomerName(String v) => customerName = v;

  /// Makan di tempat wajib pilih nomor meja; bawa pulang langsung siap.
  bool get orderReady => orderType == orderTakeaway || tableNo.isNotEmpty;

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
      lines: cart.values.map((l) => TrxLine(l.item.name, l.item.price, l.qty, l.note)).toList(),
      subtotal: subtotal,
      discount: discount,
      tax: tax,
      total: total,
      paid: paid,
      change: paid > total ? paid - total : 0,
      method: method,
      note: note,
      branch: branch,
      orderType: orderType,
      tableNo: orderType == orderTakeaway ? '' : tableNo,
      customerName: orderType == orderTakeaway ? '' : customerName.trim(),
    );
    transactions.insert(0, t);
    final oid = activeOrder?.id;
    cart.clear();
    discount = 0;
    _resetOrder();
    if (oid != null) {
      // pesanan terbuka ini sekarang lunas; statusnya dikirim ke server saat sinkron
      _pendingClose.add({'order': oid, 'trx': id});
      openOrders.removeWhere((o) => o.id == oid);
      activeOrder = null;
    }
    _save();
    notifyListeners();
    syncPending();
    return t;
  }

  // ---- pesanan terbuka ----
  bool get hasNewItems => cart.values.any((l) => l.qty > l.savedQty);

  /// Simpan pesanan (bayar nanti): hanya makan di tempat, wajib pilih meja, dan ada item baru.
  bool get canSaveOrder => cloudEnabled && orderType == orderDineIn && tableNo.isNotEmpty && hasNewItems && !newOrderOnTakenTable;

  /// Meja [no] sudah punya pesanan terbuka di cabang ini (data di HP, diperbarui tiap 30 detik).
  bool tableTaken(String no) => no.isNotEmpty && openOrders.any((o) => o.tableNo == no);

  /// Pesanan BARU diarahkan ke meja yang sudah terisi. Dilarang: tidak boleh ada dua pesanan di satu meja.
  /// (Menambah menu ke pesanan yang sudah ada tetap boleh: lewat tab Meja.)
  bool get newOrderOnTakenTable => cloudEnabled && activeOrder == null && orderType == orderDineIn && tableTaken(tableNo);

  /// Cek ke server (data paling baru) apakah meja [no] sudah terisi.
  Future<bool> tableTakenOnServer(String no) async {
    if (!cloudEnabled || sb.auth.currentSession == null || branch.isEmpty || no.isEmpty) return false;
    try {
      await _flushClose();
      final r = await sb.from('open_orders').select('id').eq('branch', branch).eq('status', 'open').eq('table_no', no).limit(1);
      final skip = {for (final c in _pendingClose) c['order']};
      return r.any((e) => !skip.contains((e as Map)['id']));
    } catch (_) {
      return tableTaken(no);
    }
  }

  int orderTotal(OpenOrder o) => o.subtotal + (o.subtotal * taxPercent / 100).round();

  String _orderError(Object e) {
    if (e is PostgrestException) {
      final m = e.message;
      if (e.code == '23505') {
        refreshOpenOrders();
        return 'Meja ini baru saja diisi pesanan lain (mungkin dari HP lain). Buka pesanannya dari tab Meja untuk menambah menu.';
      }
      if (e.code == '42P01' || e.code == 'PGRST205' || m.contains('open_orders')) {
        return 'Tabel pesanan terbuka belum dibuat. Minta bos menjalankan SQL supabase_update_pesanan_terbuka.sql.';
      }
      return m;
    }
    return 'Gagal menyimpan (periksa internet): $e';
  }

  Future<void> refreshOpenOrders() async {
    if (!cloudEnabled || sb.auth.currentSession == null || branch.isEmpty) return;
    try {
      final r = await sb.from('open_orders').select().eq('branch', branch).eq('status', 'open').order('created_at');
      final skip = {for (final c in _pendingClose) c['order']};
      final list = [for (final e in r) OpenOrder.fromCloud(Map<String, dynamic>.from(e as Map))]..removeWhere((o) => skip.contains(o.id));
      list.sort((a, b) => (int.tryParse(a.tableNo) ?? 999).compareTo(int.tryParse(b.tableNo) ?? 999));
      openOrders = list;
      openOrdersError = null;
      notifyListeners();
    } catch (e) {
      openOrdersError = _orderError(e);
      notifyListeners();
    }
  }

  /// Simpan isi keranjang sebagai pesanan terbuka di meja yang dipilih.
  /// Item baru ditambahkan ke data terbaru di server, jadi tidak menimpa tambahan dari HP lain.
  Future<SaveResult> saveOpenOrder() async {
    if (!cloudEnabled || sb.auth.currentSession == null) {
      return SaveResult(error: 'Pesanan terbuka butuh login dan internet.');
    }
    if (branch.isEmpty) return SaveResult(error: 'Akun ini belum punya cabang.');
    final now = DateTime.now();
    final added = <OpenLine>[
      for (final l in cart.values)
        if (l.qty > l.savedQty)
          OpenLine(menuId: l.item.id, name: l.item.name, price: l.item.price, qty: l.qty - l.savedQty, note: l.note, addedBy: kasir, addedAt: now),
    ];
    if (added.isEmpty) return SaveResult(error: 'Belum ada item baru untuk disimpan.');
    try {
      await _flushClose();
      final q = sb.from('open_orders').select().eq('branch', branch).eq('status', 'open');
      final rows = activeOrder != null ? await q.eq('id', activeOrder!.id).limit(1) : await q.eq('table_no', tableNo).limit(1);
      final existing = rows.isEmpty ? null : OpenOrder.fromCloud(Map<String, dynamic>.from(rows.first as Map));
      if (activeOrder != null && existing == null) {
        return SaveResult(error: 'Pesanan ini sudah dibayar atau dibatalkan. Lepas pesanan lalu muat ulang daftar meja.');
      }
      if (activeOrder == null && existing != null) {
        // pesanan baru ke meja yang sudah terisi: ditolak (tidak boleh ada dua pesanan di satu meja)
        refreshOpenOrders();
        return SaveResult(error: 'Meja $tableNo sudah terisi. Buka pesanannya dari tab Meja untuk menambah menu.');
      }
      final lines = <OpenLine>[...?existing?.lines, ...added];
      final name = (existing != null && existing.customerName.isNotEmpty) ? existing.customerName : customerName.trim();
      final rnd = (now.microsecondsSinceEpoch % 46656).toRadixString(36).toUpperCase().padLeft(3, '0');
      final id = existing?.id ?? 'ORD${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second)}-$rnd';
      final payload = {
        'lines': lines.map((e) => e.toJson()).toList(),
        'customer_name': name,
        'updated_at': now.toUtc().toIso8601String(),
      };
      if (existing == null) {
        await sb.from('open_orders').insert({
          'id': id,
          'branch': branch,
          'table_no': tableNo,
          'kasir': kasir,
          'kasir_id': sb.auth.currentUser?.id,
          'status': 'open',
          ...payload,
        });
      } else {
        await sb.from('open_orders').update(payload).eq('id', id);
      }
      final saved = OpenOrder(
        id: id,
        branch: branch,
        tableNo: existing?.tableNo ?? tableNo,
        customerName: name,
        kasir: existing?.kasir ?? kasir,
        createdAt: existing?.createdAt ?? now,
        lines: lines,
      );
      final merged = existing != null && activeOrder == null;
      cart.clear();
      discount = 0;
      activeOrder = null;
      _resetOrder();
      notifyListeners();
      refreshOpenOrders();
      return SaveResult(order: saved, added: added, merged: merged);
    } catch (e) {
      return SaveResult(error: _orderError(e));
    }
  }

  /// Muat pesanan terbuka ke keranjang (untuk menambah item atau membayar).
  /// Item yang sudah tersimpan ditandai (savedQty) dan tidak bisa dikurangi kasir.
  void loadOrderToCart(OpenOrder o) {
    cart.clear();
    discount = 0;
    orderType = orderDineIn;
    tableNo = o.tableNo;
    customerName = o.customerName;
    for (final l in o.lines) {
      CartLine? ex;
      for (final x in cart.values) {
        if (x.item.id == l.menuId && x.note == l.note && x.item.price == l.price) {
          ex = x;
          break;
        }
      }
      if (ex != null) {
        ex.qty += l.qty;
        ex.savedQty += l.qty;
      } else {
        final k = _newKey(l.menuId);
        MenuItem? base;
        for (final m in menus) {
          if (m.id == l.menuId) base = m;
        }
        final item = MenuItem(
          id: l.menuId,
          name: l.name,
          category: base?.category ?? '',
          price: l.price,
          emoji: base?.emoji ?? '🍜',
          imageUrl: base?.imageUrl ?? '',
        );
        final line = CartLine(k, item, l.qty, note: l.note);
        line.savedQty = l.qty;
        cart[k] = line;
      }
    }
    activeOrder = o;
    notifyListeners();
  }

  /// Lepas pesanan dari keranjang (pesanan tetap tersimpan di meja).
  void cancelActiveOrder() {
    cart.clear();
    discount = 0;
    activeOrder = null;
    _resetOrder();
    notifyListeners();
  }

  Future<void> _flushClose() async {
    for (final c in List<Map<String, String>>.from(_pendingClose)) {
      try {
        final now = DateTime.now().toUtc().toIso8601String();
        await sb.from('open_orders').update({'status': 'paid', 'trx_id': c['trx'], 'closed_at': now, 'updated_at': now}).eq('id', c['order']!);
        _pendingClose.remove(c);
      } catch (_) {
        break; // offline: coba lagi nanti
      }
    }
  }

  // ---- sinkron ke bos (Supabase) ----
  Timer? _timer;
  bool _syncing = false;

  /// Riwayat yang boleh dilihat akun ini. Mode login: hanya transaksi cabang sendiri
  /// (riwayat di HP disimpan per perangkat, jadi harus disaring per cabang).
  List<Trx> get myTransactions => cloudEnabled ? transactions.where((t) => t.branch == branch).toList() : transactions;

  int get pendingCount => myTransactions.where((t) => !t.synced).length;

  void setKasirQuiet(String name, [String br = '']) {
    if (br != branch) {
      activeOrder = null;
      openOrders = [];
    }
    kasir = name;
    branch = br;
  }

  void startSync() {
    if (!cloudEnabled) return;
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      syncPending();
      syncShifts();
      pullConfig();
      refreshOpenOrders();
    });
    syncPending();
    syncShifts();
    pullConfig();
    refreshOpenOrders();
  }

  String? syncError; // pesan error terakhir saat mengirim transaksi (null = lancar)
  bool schemaWarning = false; // true = kolom meja/pelanggan belum ada di Supabase (data dikirim lewat catatan)

  /// Kolom belum ada di tabel Supabase (SQL tahap 5 belum dijalankan / schema cache belum dimuat ulang).
  bool _isMissingColumn(Object e) =>
      e is PostgrestException &&
      (e.code == 'PGRST204' || e.code == '42703' || (e.message.contains('column') && e.message.contains('schema cache')));

  Future<void> _upsertTrx(Map<String, dynamic> row) =>
      sb.from('transactions').upsert(row, onConflict: 'id', ignoreDuplicates: true);

  Future<String?> syncPending() async {
    if (!cloudEnabled || _syncing || sb.auth.currentSession == null) return syncError;
    _syncing = true;
    try {
      syncError = null;
      for (final t in myTransactions.where((t) => !t.synced).toList()) {
        try {
          final row = {...t.toCloud(), 'kasir_id': sb.auth.currentUser?.id};
          try {
            await _upsertTrx(row);
            schemaWarning = false;
          } catch (e) {
            if (!_isMissingColumn(e)) rethrow;
            // Database belum punya kolom order_type/table_no/customer_name:
            // tetap kirim transaksinya, info meja & pelanggan dititipkan di catatan.
            final fb = Map<String, dynamic>.from(row)
              ..remove('order_type')
              ..remove('table_no')
              ..remove('customer_name');
            final info = t.orderLabel;
            if (info.isNotEmpty) fb['note'] = [if (t.note.isNotEmpty) t.note, '[$info]'].join(' ');
            await _upsertTrx(fb);
            schemaWarning = true;
          }
          t.synced = true;
        } on PostgrestException catch (e) {
          syncError = e.message; // ditolak server: lanjut ke transaksi berikutnya, jangan macet
        } catch (e) {
          syncError = '$e'; // offline: berhenti, coba lagi nanti
          break;
        }
      }
      await _flushClose();
      _save();
      notifyListeners();
    } finally {
      _syncing = false;
    }
    return syncError;
  }

  /// Ambil menu, harga, nama toko & pajak yang diatur bos.
  Future<void> pullConfig() async {
    if (!cloudEnabled || sb.auth.currentSession == null) return;
    try {
      String sig() => '${jsonEncode(menus.map((e) => e.toJson()).toList())}|$taxPercent|$tableCount|$storeName|$qrisUrl|$bankName|$bankAccount|$bankHolder|$bosWa';
      final before = sig();

      // jumlah meja khusus cabang HP ini (diatur bos)
      if (branch.isNotEmpty) {
        try {
          final b = await sb.from('branches').select('table_count').eq('name', branch).maybeSingle();
          if (b != null) tableCount = (b['table_count'] as num).toInt();
        } catch (_) {}
      }

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
        if (activeOrder == null) {
          final old = Map<String, CartLine>.from(cart);
          cart.clear();
          for (final e in old.entries) {
            final m = byId[e.value.item.id];
            if (m != null) cart[e.key] = CartLine(e.key, m, e.value.qty, note: e.value.note);
          }
        }
      }

      final st = await sb.from('app_settings').select();
      var qrisBranch = ''; // QRIS khusus cabang HP ini (key: qris_url@<nama cabang>)
      for (final r in st) {
        final k = r['key'] as String;
        final v = r['value'] as String;
        if (k == 'store_name' && v.isNotEmpty) storeName = v;
        if (k == 'tax_percent') taxPercent = int.tryParse(v) ?? taxPercent;
        if (branch.isNotEmpty && k == 'qris_url@$branch') qrisBranch = v;
        if (k == 'bank_name') bankName = v;
        if (k == 'bank_account') bankAccount = v;
        if (k == 'bank_holder') bankHolder = v;
        if (k == 'bos_wa') bosWa = v;
      }
      qrisUrl = qrisBranch;

      if (sig() != before) {
        _save();
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---- shift kasir ----
  Shift? get activeShift {
    for (final x in shifts) {
      if (x.isOpen) return x;
    }
    return null;
  }

  /// Total transaksi Tunai (menurut sistem) sejak [from]. Uang yang masuk laci = total tagihan (kembalian sudah dikurangi).
  int cashSalesSince(DateTime from) =>
      myTransactions.where((t) => t.method == 'Tunai' && !t.date.isBefore(from)).fold<int>(0, (a, t) => a + t.total);

  /// Penjualan non-tunai (Transfer, QRIS, Non Tunai) sejak [from], per metode. Hanya info: tidak masuk laci.
  Map<String, int> nonCashSince(DateTime from) {
    final m = <String, int>{};
    for (final t in myTransactions) {
      if (t.method == 'Tunai' || t.date.isBefore(from)) continue;
      m[t.method] = (m[t.method] ?? 0) + t.total;
    }
    return m;
  }

  /// Catat uang keluar dari laci pada shift yang sedang berjalan.
  bool addCashOut(String label, int amount) {
    final x = activeShift;
    if (x == null || amount <= 0) return false;
    x.cashOuts.add(CashOut(label.trim().isEmpty ? 'Lainnya' : label.trim(), amount, DateTime.now()));
    _save();
    notifyListeners();
    return true;
  }

  void removeCashOut(int index) {
    final x = activeShift;
    if (x == null || index < 0 || index >= x.cashOuts.length) return;
    x.cashOuts.removeAt(index);
    _save();
    notifyListeners();
  }

  void startShift(int openingCash) {
    if (activeShift != null) return;
    final now = DateTime.now();
    final rnd = (now.microsecondsSinceEpoch % 46656).toRadixString(36).toUpperCase().padLeft(3, '0');
    shifts.insert(
      0,
      Shift(
        id: 'SHF${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}-$rnd',
        kasir: kasir,
        branch: branch,
        openedAt: now,
        openingCash: openingCash < 0 ? 0 : openingCash,
      ),
    );
    _save();
    notifyListeners();
  }

  /// Tutup shift: [closingCash] = uang tunai hasil hitung di laci. Mengembalikan shift yang ditutup.
  Shift? endShift(int closingCash, String note) {
    final x = activeShift;
    if (x == null) return null;
    x.closedAt = DateTime.now();
    x.cashSales = cashSalesSince(x.openedAt);
    x.nonCash = nonCashSince(x.openedAt);
    x.expectedCash = x.openingCash + x.cashSales - x.cashOutTotal;
    x.closingCash = closingCash < 0 ? 0 : closingCash;
    x.note = note.trim();
    x.synced = false;
    _save();
    notifyListeners();
    syncShifts();
    return x;
  }

  bool _syncingShift = false;
  String? shiftSyncError;

  /// Kirim shift yang sudah ditutup ke Supabase (tabel `shifts`). Gagal = coba lagi nanti, data tetap aman di HP.
  Future<void> syncShifts() async {
    if (!cloudEnabled || _syncingShift || sb.auth.currentSession == null) return;
    _syncingShift = true;
    try {
      shiftSyncError = null;
      for (final x in shifts.where((x) => !x.isOpen && !x.synced).toList()) {
        try {
          try {
            await sb.from('shifts').upsert({...x.toCloud(), 'kasir_id': sb.auth.currentUser?.id}, onConflict: 'id', ignoreDuplicates: true);
          } on PostgrestException catch (e) {
            // SQL terbaru belum dijalankan di Supabase: kirim dengan kolom lama (uang keluar dicatat di Catatan).
            final colMissing = e.code == 'PGRST204' || e.code == '42703' || (e.message.contains('column') && e.message.contains('schema cache'));
            if (!colMissing) rethrow;
            await sb.from('shifts').upsert({...x.toCloudLegacy(), 'kasir_id': sb.auth.currentUser?.id}, onConflict: 'id', ignoreDuplicates: true);
          }
          x.synced = true;
        } catch (e) {
          shiftSyncError = '$e';
          break;
        }
      }
      pruneShifts();
      _save();
      notifyListeners();
    } finally {
      _syncingShift = false;
    }
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
    cart.removeWhere((k, l) => l.item.id == m.id);
    _save();
    notifyListeners();
  }

  // ---- pengaturan ----
  void savePayment(String qris, String bank, String account, String holder) {
    qrisUrl = qris;
    bankName = bank;
    bankAccount = account;
    bankHolder = holder;
    _save();
    notifyListeners();
  }

  void setBosWa(String v) {
    bosWa = v;
    _save();
    notifyListeners();
  }

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
