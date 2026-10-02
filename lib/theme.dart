import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'models.dart';

const navy = Color(0xFF0B2A4A);
const navy2 = Color(0xFF123A66);
const blue = Color(0xFF1565F0);
const bgColor = Color(0xFFF1F5FB);
const green = Color(0xFF16A34A);
const lineColor = Color(0xFFDCE6F5);

ThemeData buildTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: blue, primary: blue),
      scaffoldBackgroundColor: bgColor,
    );

BoxDecoration cardDeco({Color color = Colors.white}) =>
    BoxDecoration(color: color, borderRadius: BorderRadius.circular(14), border: Border.all(color: lineColor));

class MenuImage extends StatelessWidget {
  final MenuItem item;
  final double? size;
  const MenuImage(this.item, {super.key, this.size});

  Widget _emoji() => Container(
        width: size,
        height: size,
        color: const Color(0xFFE6EEFB),
        alignment: Alignment.center,
        child: Text(item.emoji, style: TextStyle(fontSize: size == null ? 44 : size! * 0.5)),
      );

  @override
  Widget build(BuildContext context) {
    // Foto dari bos (tersimpan di cache HP, jadi tetap tampil saat internet mati)
    if (item.imageUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: item.imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => _emoji(),
        errorWidget: (_, __, ___) => _emoji(),
      );
    }
    return Image.asset(
      item.asset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _emoji(),
    );
  }
}
