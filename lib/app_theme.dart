// تم‌های ای‌چت — دقیقاً رنگ‌های نسخهٔ وب (style.css :root و
// [data-theme="dark"]). تمِ روشن «کاغذی» و تمِ تیرهٔ وب، نه seed تصادفی.

import 'package:flutter/material.dart';

import 'settings.dart';

/// وضعیتِ تم برای کل اپ؛ main.dart با ValueListenableBuilder گوش می‌دهد و
/// صفحهٔ تنظیمات با تغییر آن تم را همان لحظه عوض می‌کند.
final ValueNotifier<ThemeMode> appThemeMode =
    ValueNotifier<ThemeMode>(ThemeMode.light);

/// مقداردهیِ اولیه از تنظیماتِ ذخیره‌شده (پیش‌فرض روشن، مثل وب).
Future<void> initAppTheme() async {
  final settings = await AppSettings.load();
  appThemeMode.value = settings.themeMode == AppThemeMode.dark
      ? ThemeMode.dark
      : ThemeMode.light;
}

/// تمِ روشن — :root در style.css.
ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFFC2694A), // --accent
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFE3DCC4), // --bg-active (حباب پیام کاربر)
    onPrimaryContainer: Color(0xFF3D3929),
    secondary: Color(0xFFA9603F), // --accent-soft
    onSecondary: Colors.white,
    error: Color(0xFFC0392B), // --danger
    onError: Colors.white,
    surface: Color(0xFFFFFFFF), // --bg-panel (حباب دستیار)
    onSurface: Color(0xFF3D3929), // --text-primary
    surfaceContainerLow: Color(0xFFF1EEE1), // --bg-section
    surfaceContainerHighest: Color(0xFFEAE6D6), // --bg-hover
    outline: Color(0xFFDED8C2), // --border-color
    outlineVariant: Color(0xFFE7E2D1), // --border-soft
    onSurfaceVariant: Color(0xFF5B5645), // --text-secondary
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F4EE), // --bg-app
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFFECE8DA), // --bg-sidebar
    ),
    useMaterial3: true,
  );
}

/// تمِ تیره — [data-theme="dark"] در style.css.
ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFF4F46E5), // --accent
    onPrimary: Colors.white,
    primaryContainer: Color(0xFF2B2B52), // --bg-active (حباب پیام کاربر)
    onPrimaryContainer: Color(0xFFE5E5E5),
    secondary: Color(0xFFA5B4FC), // --accent-soft
    onSecondary: Color(0xFF121212),
    error: Color(0xFFEF4444), // --danger
    onError: Colors.white,
    surface: Color(0xFF1E1E1E), // --bg-panel (حباب دستیار)
    onSurface: Color(0xFFE5E5E5), // --text-primary
    surfaceContainerLow: Color(0xFF252525), // --bg-section
    surfaceContainerHighest: Color(0xFF23232A), // --bg-hover
    outline: Color(0xFF374151), // --border-color
    outlineVariant: Color(0xFF2A2A2E), // --border-soft
    onSurfaceVariant: Color(0xFFD1D5DB), // --text-secondary
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF121212), // --bg-app
    drawerTheme: const DrawerThemeData(
      backgroundColor: Color(0xFF17171A), // --bg-sidebar
    ),
    useMaterial3: true,
  );
}

/// پس‌زمینهٔ بلوک کد (همان --code-block-bg در style.css).
Color codeBlockBackground(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF17171A)
        : Colors.white;

/// پس‌زمینهٔ سربرگ بلوک کد (همان --code-toolbar-bg در style.css).
Color codeToolbarBackground(Brightness brightness) =>
    brightness == Brightness.dark
        ? const Color(0xFF1F1F24)
        : const Color(0xFFF1EEE1);
