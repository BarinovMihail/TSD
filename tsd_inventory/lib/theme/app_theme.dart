import 'package:flutter/material.dart';

/// Тема: крупная, контрастная, «палочко-устойчивая» для ТСД M3 SL20.
ThemeData appTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: const ColorScheme.highContrastLight(
      primary: Color(0xFF0D47A1), // тёмно-синий
      onPrimary: Colors.white,
      secondary: Color(0xFF2E7D32), // зелёный — «найдено»
      onSecondary: Colors.white,
      error: Color(0xFFC62828), // красный
      surface: Colors.white,
      onSurface: Colors.black,
    ),
    textTheme: base.textTheme.copyWith(
      bodyLarge: const TextStyle(fontSize: 20, height: 1.3),
      bodyMedium: const TextStyle(fontSize: 18, height: 1.3),
      titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      labelLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      contentPadding: EdgeInsets.all(16),
      border: OutlineInputBorder(),
      filled: true,
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
