// ای‌چت — نسخهٔ نیتیو Flutter (بدون WebView).
// چت فارسی با مدل‌های هوش مصنوعی از طریق بک‌اند Flask خود کاربر.
// تم‌ها دقیقاً رنگ‌های نسخهٔ وب هستند (lib/app_theme.dart).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_theme.dart';
import 'ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initAppTheme();
  runApp(const AichatApp());
}

class AichatApp extends StatelessWidget {
  const AichatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeMode,
      builder: (context, mode, _) {
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
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: mode,
          home: const HomePage(),
        );
      },
    );
  }
}
