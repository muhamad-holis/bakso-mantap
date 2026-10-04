/// Jenis pesanan.
const orderDineIn = 'Makan di Tempat';
const orderTakeaway = 'Bawa Pulang';

class MenuItem {
  String id;
  String name;
  String category;
  int price;
  String emoji;
  String imageUrl; // foto menu dari bos (khusus cabang ini); kosong = pakai emoji
  MenuItem({required this.id, required this.name, required this.category, required this.price, this.emoji = '🍜', this.imageUrl = ''});

  /// Foto menu (opsional): taruh file di assets/images/<id>.jpg
  String get asset => 'assets/images/$id.jpg';

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'category': category, 'price': price, 'emoji': emoji, 'image_url': imageUrl};
  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        price: j['price'] as int,
        emoji: (j['emoji'] as String?) ?? '🍜',
        imageUrl: (j['image_url'] as String?) ?? '',
      );
}

class CartLine {
  final String key; // unik per baris keranjang (menu yang sama bisa punya beberapa baris dengan catatan berbeda)
  final MenuItem item;
  int qty;
  String note; // catatan khusus item ini, mis. 'tanpa sambal'
  int savedQty; // porsi yang sudah tersimpan di pesanan terbuka (kasir tidak bisa mengurangi)
  CartLine(this.key, this.item, this.qty, {this.note = '', this.savedQty = 0});
  int get total => item.price * qty;
}

/// Satu batch item dalam pesanan terbuka. Dicatat siapa & kapan menambahkan.
class OpenLine {
  final String menuId;
  final String name;
  final String note;
  final String addedBy;
  final int price;
  final int qty;
  final DateTime? addedAt;
  OpenLine({
    required this.menuId,
    required this.name,
    required this.price,
    required this.qty,
    this.note = '',
    this.addedBy = '',
    this.addedAt,
  });

  Map<String, dynamic> toJson() => {
        'menu_id': menuId,
        'name': name,
        'price': price,
        'qty': qty,
        'note': note,
        'added_by': addedBy,
        'added_at': addedAt?.toUtc().toIso8601String(),
      };

  factory OpenLine.fromJson(Map<String, dynamic> j) => OpenLine(
        menuId: (j['menu_id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        price: ((j['price'] as num?) ?? 0).toInt(),
        qty: ((j['qty'] as num?) ?? 0).toInt(),
        note: (j['note'] as String?) ?? '',
        addedBy: (j['added_by'] as String?) ?? '',
        addedAt: j['added_at'] == null ? null : DateTime.tryParse(j['added_at'] as String)?.toLocal(),
      );
}

/// Pesanan yang belum dibayar (pelanggan masih makan). Dibayar belakangan lewat Checkout biasa.
class OpenOrder {
  final String id;
  final String branch;
  final String tableNo;
  final String customerName;
  final String kasir;
  final DateTime createdAt;
  final List<OpenLine> lines;
  OpenOrder({
    required this.id,
    required this.branch,
    required this.tableNo,
    required this.customerName,
    required this.kasir,
    required this.createdAt,
    required this.lines,
  });

  int get itemCount => lines.fold(0, (a, l) => a + l.qty);
  int get subtotal => lines.fold(0, (a, l) => a + l.price * l.qty);

  /// Item yang ditambahkan belakangan (lebih dari 2 menit setelah pesanan dibuat).
  bool isExtra(OpenLine l) => l.addedAt != null && l.addedAt!.difference(createdAt).inMinutes >= 2;

  factory OpenOrder.fromCloud(Map<String, dynamic> j) => OpenOrder(
        id: j['id'] as String,
        branch: (j['branch'] as String?) ?? '',
        tableNo: (j['table_no'] as String?) ?? '',
        customerName: (j['customer_name'] as String?) ?? '',
        kasir: (j['kasir'] as String?) ?? '',
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        lines: ((j['lines'] as List?) ?? const [])
            .map((e) => OpenLine.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class TrxLine {
  final String name;
  final int price;
  final int qty;
  final String note; // catatan per item ('' = tidak ada)
  TrxLine(this.name, this.price, this.qty, [this.note = '']);
  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'qty': qty, if (note.isNotEmpty) 'note': note};
  factory TrxLine.fromJson(Map<String, dynamic> j) =>
      TrxLine(j['name'] as String, (j['price'] as num).toInt(), (j['qty'] as num).toInt(), (j['note'] as String?) ?? '');
}

/// Shift kasir: kas awal, kas akhir (hasil hitung uang), dan selisih terhadap tunai di sistem.
class Shift {
  final String id;
  final String kasir;
  final String branch;
  final DateTime openedAt;
  final int openingCash;
  DateTime? closedAt;
  int closingCash; // uang tunai hasil hitung kasir saat tutup
  int cashSales; // total transaksi Tunai selama shift (menurut sistem)
  int expectedCash; // kas awal + cashSales
  String note;
  bool synced;
  Shift({
    required this.id,
    required this.kasir,
    required this.branch,
    required this.openedAt,
    required this.openingCash,
    this.closedAt,
    this.closingCash = 0,
    this.cashSales = 0,
    this.expectedCash = 0,
    this.note = '',
    this.synced = false,
  });

  bool get isOpen => closedAt == null;

  /// Positif = uang lebih, negatif = uang kurang.
  int get difference => closingCash - expectedCash;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kasir': kasir,
        'branch': branch,
        'openedAt': openedAt.toIso8601String(),
        'openingCash': openingCash,
        'closedAt': closedAt?.toIso8601String(),
        'closingCash': closingCash,
        'cashSales': cashSales,
        'expectedCash': expectedCash,
        'note': note,
        'synced': synced,
      };

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        id: j['id'] as String,
        kasir: (j['kasir'] as String?) ?? '',
        branch: (j['branch'] as String?) ?? '',
        openedAt: DateTime.parse(j['openedAt'] as String),
        openingCash: (j['openingCash'] as num).toInt(),
        closedAt: j['closedAt'] == null ? null : DateTime.parse(j['closedAt'] as String),
        closingCash: ((j['closingCash'] as num?) ?? 0).toInt(),
        cashSales: ((j['cashSales'] as num?) ?? 0).toInt(),
        expectedCash: ((j['expectedCash'] as num?) ?? 0).toInt(),
        note: (j['note'] as String?) ?? '',
        synced: (j['synced'] as bool?) ?? false,
      );

  Map<String, dynamic> toCloud() => {
        'id': id,
        'kasir': kasir,
        'branch': branch,
        'opened_at': openedAt.toUtc().toIso8601String(),
        'closed_at': closedAt?.toUtc().toIso8601String(),
        'opening_cash': openingCash,
        'closing_cash': closingCash,
        'cash_sales': cashSales,
        'expected_cash': expectedCash,
        'difference': difference,
        'note': note,
      };

  factory Shift.fromCloud(Map<String, dynamic> j) => Shift(
        id: j['id'] as String,
        kasir: (j['kasir'] as String?) ?? '',
        branch: (j['branch'] as String?) ?? '',
        openedAt: DateTime.parse(j['opened_at'] as String).toLocal(),
        openingCash: (j['opening_cash'] as num).toInt(),
        closedAt: DateTime.parse(j['closed_at'] as String).toLocal(),
        closingCash: (j['closing_cash'] as num).toInt(),
        cashSales: (j['cash_sales'] as num).toInt(),
        expectedCash: (j['expected_cash'] as num).toInt(),
        note: (j['note'] as String?) ?? '',
        synced: true,
      );
}

class Trx {
  final String id;
  final DateTime date;
  final String kasir;
  final List<TrxLine> lines;
  final int subtotal, discount, tax, total, paid, change;
  final String method, note;
  final String branch;
  final String orderType; // 'Makan di Tempat' / 'Bawa Pulang' ('' = transaksi lama)
  final String tableNo; // kosong jika bawa pulang
  final String customerName; // kosong jika bawa pulang / tidak diisi
  bool synced;
  Trx({
    required this.id,
    required this.date,
    required this.kasir,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.paid,
    required this.change,
    required this.method,
    required this.note,
    this.synced = false,
    this.branch = '',
    this.orderType = '',
    this.tableNo = '',
    this.customerName = '',
  });

  bool get isTakeaway => orderType == orderTakeaway;

  /// Ringkasan untuk daftar & struk, mis. 'Meja 5 • Budi' atau 'Bawa Pulang'. Kosong untuk transaksi lama.
  String get orderLabel {
    if (orderType.isEmpty) return '';
    if (isTakeaway) return orderTakeaway;
    final parts = <String>[if (tableNo.isNotEmpty) 'Meja $tableNo' else orderDineIn, if (customerName.isNotEmpty) customerName];
    return parts.join(' • ');
  }

  int get itemCount => lines.fold(0, (a, l) => a + l.qty);

  Map<String, dynamic> toCloud() => {
        'id': id,
        'created_at': date.toUtc().toIso8601String(),
        'kasir': kasir,
        'branch': branch,
        'item_count': itemCount,
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paid': paid,
        'change': change,
        'method': method,
        'note': note,
        'order_type': orderType,
        'table_no': tableNo,
        'customer_name': customerName,
        'lines': lines.map((e) => e.toJson()).toList(),
      };

  factory Trx.fromCloud(Map<String, dynamic> j) => Trx(
        id: j['id'] as String,
        date: DateTime.parse(j['created_at'] as String).toLocal(),
        kasir: (j['kasir'] as String?) ?? '-',
        branch: (j['branch'] as String?) ?? '',
        lines: (j['lines'] as List).map((e) => TrxLine.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
        subtotal: (j['subtotal'] as num).toInt(),
        discount: (j['discount'] as num).toInt(),
        tax: (j['tax'] as num).toInt(),
        total: (j['total'] as num).toInt(),
        paid: (j['paid'] as num).toInt(),
        change: (j['change'] as num).toInt(),
        method: j['method'] as String,
        note: (j['note'] as String?) ?? '',
        orderType: (j['order_type'] as String?) ?? '',
        tableNo: (j['table_no'] as String?) ?? '',
        customerName: (j['customer_name'] as String?) ?? '',
        synced: true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'kasir': kasir,
        'lines': lines.map((e) => e.toJson()).toList(),
        'subtotal': subtotal,
        'discount': discount,
        'tax': tax,
        'total': total,
        'paid': paid,
        'change': change,
        'method': method,
        'note': note,
        'synced': synced,
        'branch': branch,
        'orderType': orderType,
        'tableNo': tableNo,
        'customerName': customerName,
      };

  factory Trx.fromJson(Map<String, dynamic> j) => Trx(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        kasir: j['kasir'] as String,
        lines: (j['lines'] as List).map((e) => TrxLine.fromJson(e as Map<String, dynamic>)).toList(),
        subtotal: j['subtotal'] as int,
        discount: j['discount'] as int,
        tax: j['tax'] as int,
        total: j['total'] as int,
        paid: j['paid'] as int,
        change: j['change'] as int,
        method: j['method'] as String,
        note: j['note'] as String,
        synced: (j['synced'] as bool?) ?? false,
        branch: (j['branch'] as String?) ?? '',
        orderType: (j['orderType'] as String?) ?? '',
        tableNo: (j['tableNo'] as String?) ?? '',
        customerName: (j['customerName'] as String?) ?? '',
      );
}

/// Format tanggal untuk kolom `date` di Supabase: yyyy-MM-dd.
String dbDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const expenseCategories = ['Bahan baku', 'Gas & listrik', 'Gaji', 'Sewa', 'Lainnya'];

/// Pengeluaran yang dicatat bos (mis. belanja bahan). branch kosong = umum (semua cabang).
class Expense {
  final String id;
  final DateTime date; // hanya tanggal (jam 00:00)
  final String branch;
  final String category;
  final String name;
  final int amount;
  final String note;
  Expense({
    required this.id,
    required this.date,
    required this.branch,
    required this.category,
    required this.name,
    required this.amount,
    this.note = '',
  });

  Map<String, dynamic> toCloud() => {
        'id': id,
        'date': dbDate(date),
        'branch': branch,
        'category': category,
        'name': name,
        'amount': amount,
        'note': note,
      };

  factory Expense.fromCloud(Map<String, dynamic> j) => Expense(
        id: j['id'] as String,
        date: DateTime.parse(j['date'] as String),
        branch: (j['branch'] as String?) ?? '',
        category: (j['category'] as String?) ?? 'Lainnya',
        name: (j['name'] as String?) ?? '',
        amount: (j['amount'] as num).toInt(),
        note: (j['note'] as String?) ?? '',
      );
}
