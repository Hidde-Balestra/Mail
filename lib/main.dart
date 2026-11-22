import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const MailClientApp());
}

class MailClientApp extends StatelessWidget {
  const MailClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3B6FD8);
    return MaterialApp(
      title: 'Mail Client',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: seed,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      ),
      home: const HomeScreen(),
    );
  }
}
