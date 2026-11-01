import 'package:flutter/material.dart';
import 'package:game/home.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Đã gỡ bỏ Supabase.initialize(...)

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NTU Map',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const Menu(),
    );
  }
}