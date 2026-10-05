import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0B1220);
  static const bgDeep = Color(0xFF05080F);
  static const surface = Color(0xFF131C2E);
  static const surface2 = Color(0xFF1C2840);
  static const border = Color(0xFF22304A);
  static const text = Color(0xFFE8EEF7);
  static const muted = Color(0xFF93A3BC);
  static const accent = Color(0xFF33E0C0);
  static const onAccent = Color(0xFF04251F);
  static const accentDim = Color(0xFF0F2E2A);
  static const orange = Color(0xFFFF9F45);
  static const onOrange = Color(0xFF2A1600);
  static const danger = Color(0xFFE5484D);
  static const dangerText = Color(0xFFFF8A80);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.orange,
    onSecondary: AppColors.onOrange,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.muted),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface2,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
