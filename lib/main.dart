// ای‌چت — نسخهٔ نیتیو Flutter (بدون WebView).
// چت فارسی با مدل‌های هوش مصنوعی از طریق بک‌اند Flask خود کاربر.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'ui/home_page.dart';

void main() {
  runApp(const AichatApp());
}

class AichatApp extends StatelessWidget {
  const AichatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ای‌چت',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      supportedLocales: const [
        Locale('fa'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
