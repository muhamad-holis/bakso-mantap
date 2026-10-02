import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../state.dart';
import '../theme.dart';
import '../utils.dart';
import 'kasir_page.dart';
import 'other_pages.dart';

class HomeShell extends StatefulWidget {
  HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int idx = 0;

  @override
  void initState() {
    super.initState();
    if (cloudEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().startSync());
    }
  }

  final items = cloudEnabled
      ? [
          [Icons.home_rounded, 'Kasir'],
          [Icons.receipt_long_outlined, 'Transaksi'],
          [Icons.person_outline, 'Akun'],
        ]
      : [
    [Icons.home_rounded, 'Kasir'],
    [Icons.receipt_long_outlined, 'Transaksi'],
    [Icons.restaurant_menu, 'Menu'],
    [Icons.bar_chart_rounded, 'Laporan'],
    [Icons.settings, 'Pengaturan'],
      ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 700;
    final body = IndexedStack(
      index: idx,
      children: cloudEnabled
          ? [KasirPage(), TransaksiPage(), AkunPage()]
          : [KasirPage(), TransaksiPage(), MenuPage(), LaporanPage(), PengaturanPage()],
    );
    return Scaffold(
      body: Column(children: [
        AppHeader(compact: !wide),
        Expanded(
          child: wide ? Row(children: [_sidebar(), Expanded(child: body)]) : body,
        ),
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: idx,
              onDestinationSelected: (i) => setState(() => idx = i),
              destinations: [
                for (final it in items) NavigationDestination(icon: Icon(it[0] as IconData), label: it[1] as String),
              ],
            ),
    );
  }

  Widget _sidebar() {
    return Container(
      width: 150,
      color: navy,
      padding: EdgeInsets.fromLTRB(8, 12, 8, 12),
      child: Column(children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => idx = i),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                decoration: BoxDecoration(
                  color: idx == i ? blue : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(items[i][0] as IconData, color: Colors.white, size: 22),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(items[i][1] as String,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class AppHeader extends StatelessWidget {
  final bool compact;
  AppHeader({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Container(
      color: navy,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(Icons.ramen_dining, color: navy, size: 24),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.storeName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                if (!compact || s.branch.isNotEmpty)
                  Text(compact ? s.branch : s.tagline, style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 12)),
              ]),
            ),
            if (!compact) ...[
              Icon(Icons.account_circle, color: Colors.white, size: 34),
              SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Kasir', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                Text(s.branch.isEmpty ? s.kasir : '${s.kasir} • ${s.branch}', style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 11)),
              ]),
              SizedBox(width: 20),
            ],
            StreamBuilder<DateTime>(
              stream: Stream.periodic(Duration(seconds: 15), (_) => DateTime.now()),
              initialData: DateTime.now(),
              builder: (c, snap) {
                final d = snap.data!;
                return Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text(jam(d), style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(tgl(d), style: TextStyle(color: Color(0xFFB8C7DE), fontSize: 11)),
                ]);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
