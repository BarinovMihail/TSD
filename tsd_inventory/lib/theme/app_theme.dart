import 'package:flutter/material.dart';

/// Тема: крупная, контрастная, «палочко-устойчивая» для ТСД M3 SL20.
ThemeData appTheme() {
  final base = ThemeData.light(useMaterial3: true);
  // Цвета текста задаём явно: ThemeData.copyWith(textTheme: ...copyWith(...))
  // сбрасывает color в null → текст становится невидимым. Поэтому применяем
  // applyDisplayVariant для подстановки colorScheme.onSurface к нашим стилям.
  const onText = Colors.black;
  final textTheme = base.textTheme
      .copyWith(
        bodyLarge: const TextStyle(fontSize: 20, height: 1.3),
        bodyMedium: const TextStyle(fontSize: 18, height: 1.3),
        titleLarge: const TextStyle(
            fontSize: 24, fontWeight: FontWeight.w700, color: onText),
        titleMedium: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: onText),
        labelLarge: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w600, color: onText),
      )
      .apply(
        bodyColor: onText,
        displayColor: onText,
      );

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
    textTheme: textTheme,
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    // Больше воздуха под контентом диалога — отступ до кнопок.
    dialogTheme: const DialogThemeData(
      actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      contentPadding: EdgeInsets.all(16),
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
      // Явные цвета: вводимый текст и подписи — чёрные на белой заливке.
      hintStyle: TextStyle(color: Colors.black54),
      labelStyle: TextStyle(color: Colors.black87),
      floatingLabelStyle: TextStyle(color: Colors.black),
    ),
    cardTheme: CardThemeData(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
