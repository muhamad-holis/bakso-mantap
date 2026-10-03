import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

SupabaseClient get sb => Supabase.instance.client;

/// Dinaikkan setiap kali bos menyimpan/menghapus pengeluaran, supaya layar Pantau langsung memuat ulang laba.
final expenseChanged = ValueNotifier<int>(0);

/// Daftar nama cabang: gabungan tabel `branches` dan cabang pada akun kasir (urut abjad).
Future<List<String>> loadBranchNames() async {
  final set = <String>{};
  try {
    final r = await sb.from('branches').select('name');
    for (final e in r) {
      final n = e['name'] as String?;
      if (n != null && n.isNotEmpty) set.add(n);
    }
  } catch (_) {}
  try {
    final r = await sb.from('profiles').select('branch');
    for (final e in r) {
      final n = e['branch'] as String?;
      if (n != null && n.isNotEmpty) set.add(n);
    }
  } catch (_) {}
  return set.toList()..sort();
}

/// Ambil role & nama akun. Hasil disimpan lokal supaya kasir tetap bisa
/// membuka aplikasi saat internet mati.
Future<Map<String, dynamic>?> fetchProfile() async {
  final u = sb.auth.currentUser;
  if (u == null) return null;
  final p = await SharedPreferences.getInstance();
  try {
    final r = await sb.from('profiles').select().eq('id', u.id).maybeSingle();
    if (r != null) {
      await p.setString('profile_${u.id}', jsonEncode(r));
      return r;
    }
  } catch (_) {}
  final cached = p.getString('profile_${u.id}');
  return cached == null ? null : jsonDecode(cached) as Map<String, dynamic>;
}
