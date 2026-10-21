import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import 'auth_gate.dart';

class KodeKoalesceApp extends StatefulWidget {
  const KodeKoalesceApp({super.key});

  @override
  State<KodeKoalesceApp> createState() => _KodeKoalesceAppState();
}

class _KodeKoalesceAppState extends State<KodeKoalesceApp> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KodeKoalesce',
      debugShowCheckedModeBanner: false,
      theme: _makeTheme(Brightness.light),
      darkTheme: _makeTheme(Brightness.dark),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 250),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: AuthGate(
        themeMode: _themeMode,
        onThemeModeChanged: (mode) => setState(() => _themeMode = mode),
      ),
    );
  }

  ThemeData _makeTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.green,
          brightness: brightness,
        ).copyWith(
          primary: isDark ? const Color(0xFF8BCFA7) : AppColors.green,
          onPrimary: isDark ? const Color(0xFF102018) : Colors.white,
          surface: isDark ? const Color(0xFF1A211D) : Colors.white,
          onSurface: isDark ? const Color(0xFFE7EEE9) : AppColors.ink,
          outline: isDark ? const Color(0xFF46534A) : const Color(0xFFE0E6E0),
          outlineVariant: isDark
              ? const Color(0xFF344139)
              : const Color(0xFFE8ECE7),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF111713)
          : AppColors.canvas,
      dividerColor: isDark ? const Color(0xFF344139) : const Color(0xFFE3E8E3),
      drawerTheme: DrawerThemeData(backgroundColor: scheme.surface),
      fontFamily: 'Roboto',
    );
  }
}
