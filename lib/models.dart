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
  final MenuItem item;
  int qty;
  CartLine(this.item, this.qty);
  int get total => item.price * qty;
}

class TrxLine {
  final String name;
  final int price;
  final int qty;
  TrxLine(this.name, this.price, this.qty);
  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'qty': qty};
  factory TrxLine.fromJson(Map<String, dynamic> j) => TrxLine(j['name'] as String, j['price'] as int, j['qty'] as int);
}

class Trx {
  final String id;
  final DateTime date;
  final String kasir;
  final List<TrxLine> lines;
  final int subtotal, discount, tax, total, paid, change;
  final String method, note;
  final String branch;
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
  });

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
      );
}
