import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'config.dart';
import 'screens/auth.dart';
import 'screens/shell.dart';
import 'state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (cloudEnabled) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final name = context.select<AppState, String>((s) => s.storeName);
    return MaterialApp(
      title: name,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: cloudEnabled ? AuthGate() : HomeShell(),
    );
  }
}
