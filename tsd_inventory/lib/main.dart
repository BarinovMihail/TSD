import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'app.dart';

void main() {
  // В debug выводим логи package:logging в debugPrint (видно в logcat: flutter:).
  if (kDebugMode) {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((r) {
      debugPrint('[${r.level.name}] ${r.loggerName}: ${r.message}');
    });
  }
  runApp(const ProviderScope(child: TsdApp()));
}
