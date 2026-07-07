// Генератор иконки приложения из логотипа.
// Вписывает исходный PNG (любого размера/пропорций) в квадрат 1024×1024 с
// прозрачным фоном, сохраняя пропорции (без обрезки/искажения).
//
// Запуск: dart run tool/generate_icon.dart
//
// Результат записывается в assets/icon.png — используется flutter_launcher_icons
// для генерации всех mipmap-размеров.

import 'dart:io';

import 'package:image/image.dart';

void main() {
  final src = decodePng(File('assets/logo_source.png').readAsBytesSync())!;
  print('Исходник: ${src.width}×${src.height}');

  const targetSize = 1024;

  // Масштабируем по большей стороне, чтобы вписать в квадрат.
  final scale = targetSize / src.width > targetSize / src.height
      ? targetSize / src.width
      : targetSize / src.height;
  final newW = (src.width * scale).round();
  final newH = (src.height * scale).round();
  final scaled = copyResize(src, width: newW, height: newH);

  // Кладём по центру на прозрачный квадрат 1024×1024 (RGBA по умолчанию прозрачный).
  final canvas = Image(width: targetSize, height: targetSize, numChannels: 4);
  compositeImage(canvas, scaled,
      dstX: (targetSize - newW) ~/ 2, dstY: (targetSize - newH) ~/ 2);

  final out = encodePng(canvas, level: 9);
  File('assets/icon.png').writeAsBytesSync(out);
  print('Готово: assets/icon.png ${canvas.width}×${canvas.height}');
}
