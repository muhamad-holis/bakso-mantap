import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthState, AuthException;
import '../cloud.dart';
import '../state.dart';
import '../theme.dart';
import 'bos_admin.dart';
import 'shell.dart';

class AuthGate extends StatelessWidget {
  AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: sb.auth.onAuthStateChange,
      builder: (c, snap) {
        final session = sb.auth.currentSession;
        if (session == null) return LoginPage();
        return RoleGate(key: ValueKey(session.user.id));
      },
    );
  }
}

class RoleGate extends StatefulWidget {
  RoleGate({super.key});
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late Future<Map<String, dynamic>?> f = fetchProfile();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: f,
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final p = snap.data;
        if (snap.hasError || p == null) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Gagal memuat akun.\nPeriksa koneksi internet lalu coba lagi.', textAlign: TextAlign.center),
                  SizedBox(height: 16),
                  FilledButton(onPressed: () => setState(() => f = fetchProfile()), child: Text('Coba lagi')),
                  TextButton(onPressed: () => context.read<AppState>().logout(), child: Text('Keluar')),
                ]),
              ),
            ),
          );
        }
        if ((p['role'] as String?) == 'bos') return BosShell();
        final name = (p['name'] as String?) ?? '';
        context.read<AppState>().setKasirQuiet(name.isEmpty ? (sb.auth.currentUser?.email ?? 'kasir') : name, (p['branch'] as String?) ?? '');
        return HomeShell();
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  bool loading = false;
  String? error;

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await sb.auth.signInWithPassword(email: email.text.trim(), password: pass.text);
    } on AuthException {
      error = 'Email atau password salah';
    } catch (_) {
      error = 'Tidak bisa terhubung. Periksa internet.';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppState>().storeName;
    return Scaffold(
      backgroundColor: navy,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.ramen_dining, size: 48, color: navy),
                SizedBox(height: 6),
                Text(store, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: navy)),
                Text('Masuk sebagai kasir atau bos', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
                SizedBox(height: 18),
                TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
                SizedBox(height: 12),
                TextField(controller: pass, obscureText: true, onSubmitted: (_) => _login(), decoration: InputDecoration(labelText: 'Password', border: OutlineInputBorder())),
                if (error != null) Padding(padding: EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: Colors.red))),
                SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: blue, minimumSize: Size.fromHeight(50)),
                  onPressed: loading ? null : _login,
                  child: loading ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Masuk'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
