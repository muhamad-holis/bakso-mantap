import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SupabaseClient;

SupabaseClient get sb => Supabase.instance.client;

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
