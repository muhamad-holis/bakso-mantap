import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models.dart';
import '../printer.dart';
import '../theme.dart';

/// Cetak struk ke printer Bluetooth. Jika printer belum dipilih, buka halaman pengaturan dulu.
Future<void> printReceiptFlow(BuildContext context, Trx t, String store, String tagline) async {
  final cfg = await PrinterConfig.load();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!cfg.hasPrinter) {
    messenger.showSnackBar(SnackBar(content: Text('Pilih printer Bluetooth dulu')));
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PrinterPage()));
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text('Mencetak struk...'), duration: Duration(seconds: 2)));
  final err = await ThermalPrinter.send(
    cfg.mac,
    buildReceiptBytes(t: t, store: store, tagline: tagline, paperMm: cfg.paperMm),
  );
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(err ?? 'Struk dikirim ke printer')));
}

/// Cetak bon dapur ke printer Bluetooth. Jika printer belum dipilih, buka halaman pengaturan dulu.
Future<void> printKitchenFlow(BuildContext context, OpenOrder o, List<OpenLine> lines, {required String title}) async {
  final cfg = await PrinterConfig.load();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  if (!cfg.hasPrinter) {
    messenger.showSnackBar(SnackBar(content: Text('Pilih printer Bluetooth dulu')));
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PrinterPage()));
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text('Mencetak bon dapur...'), duration: Duration(seconds: 2)));
  final err = await ThermalPrinter.send(
    cfg.mac,
    buildKitchenBytes(title: title, tableNo: o.tableNo, customer: o.customerName, kasir: o.kasir, lines: lines, paperMm: cfg.paperMm),
  );
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(content: Text(err ?? 'Bon dapur dikirim ke printer')));
}

/// Setelah pesanan disimpan: tawarkan cetak bon dapur (hanya item baru).
Future<void> offerKitchenPrint(BuildContext context, OpenOrder o, List<OpenLine> added, {required bool addition}) async {
  final n = added.fold<int>(0, (a, l) => a + l.qty);
  final yes = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(addition ? 'Tambahan Meja ${o.tableNo} tersimpan' : 'Pesanan Meja ${o.tableNo} tersimpan'),
      content: Text('Cetak bon dapur untuk $n item baru?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Nanti')),
        FilledButton.icon(onPressed: () => Navigator.pop(d, true), icon: Icon(Icons.print), label: Text('Cetak Bon')),
      ],
    ),
  );
  if (yes != true || !context.mounted) return;
  await printKitchenFlow(context, o, added, title: addition ? 'TAMBAHAN PESANAN' : 'PESANAN BARU');
}

class PrinterPage extends StatefulWidget {
  PrinterPage({super.key});
  @override
  State<PrinterPage> createState() => _PrinterPageState();
}

class _PrinterPageState extends State<PrinterPage> {
  PrinterConfig cfg = PrinterConfig();
  List<BluetoothInfo> devices = [];
  bool loading = true;
  bool testing = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    cfg = await PrinterConfig.load();
    if (mounted) setState(() {});
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    var list = <BluetoothInfo>[];
    String? err = await ThermalPrinter.ensureReady();
    if (err == null) {
      try {
        list = await ThermalPrinter.paired();
      } catch (e) {
        err = 'Gagal membaca daftar Bluetooth: $e';
      }
    }
    if (!mounted) return;
    setState(() {
      devices = list;
      error = err;
      loading = false;
    });
  }

  Future<void> _setPaper(int mm) async {
    cfg = cfg.copyWith(paperMm: mm);
    await cfg.save();
    if (mounted) setState(() {});
  }

  Future<void> _pick(BluetoothInfo d) async {
    cfg = cfg.copyWith(mac: d.macAdress, name: d.name);
    await cfg.save();
    if (mounted) setState(() {});
  }

  Future<void> _test() async {
    setState(() => testing = true);
    final err = await ThermalPrinter.send(
      cfg.mac,
      buildTestBytes(printerName: cfg.name.isEmpty ? cfg.mac : cfg.name, paperMm: cfg.paperMm),
    );
    if (!mounted) return;
    setState(() => testing = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Tes cetak dikirim ke printer')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Printer Struk'), backgroundColor: navy, foregroundColor: Colors.white),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 520),
          child: ListView(padding: EdgeInsets.all(12), children: [
            Container(
              padding: EdgeInsets.all(14),
              decoration: cardDeco(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Ukuran kertas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment<int>(value: 55, label: Text('55 mm')),
                      ButtonSegment<int>(value: 80, label: Text('80 mm')),
                    ],
                    selected: {cfg.paperMm},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setPaper(s.first),
                  ),
                ),
                SizedBox(height: 6),
                Text('Pengaturan ini tersimpan di HP ini saja.', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ]),
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(14),
              decoration: cardDeco(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Printer Bluetooth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Muat ulang', onPressed: loading ? null : _refresh, icon: Icon(Icons.refresh)),
                ]),
                Text(
                  cfg.hasPrinter ? 'Dipilih: ${cfg.name.isEmpty ? cfg.mac : cfg.name}' : 'Belum ada printer dipilih',
                  style: TextStyle(color: cfg.hasPrinter ? green : Colors.grey[700], fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                if (loading)
                  Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                else if (error != null)
                  Text(error!, style: TextStyle(color: Colors.red))
                else if (devices.isEmpty)
                  Text(
                    'Belum ada perangkat Bluetooth yang dipasangkan. Nyalakan printer, lalu pasangkan (pair) di Pengaturan > Bluetooth HP, kemudian tekan muat ulang.',
                    style: TextStyle(color: Colors.grey[700]),
                  )
                else
                  for (final d in devices)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.print_outlined, color: navy),
                      title: Text(d.name.isEmpty ? '(tanpa nama)' : d.name, style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(d.macAdress),
                      trailing: d.macAdress == cfg.mac ? Icon(Icons.check_circle, color: green) : null,
                      onTap: () => _pick(d),
                    ),
              ]),
            ),
            SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50), backgroundColor: blue),
              onPressed: cfg.hasPrinter && !testing ? _test : null,
              icon: testing
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.print),
              label: Text('Tes Cetak'),
            ),
          ]),
        ),
      ),
    );
  }
}
