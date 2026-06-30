import 'package:flutter/services.dart';

/// Звуковая/вибро-обратная связь на результат сканирования.
/// Для шумных цехов: высокий тон = успех, низкий = ошибка, средний = внимание.
///
/// Реализация на системных средствах (без аудио-ассетов):
/// разная вибро-сигнатура различает тип результата.
class FeedbackService {
  bool _muted = false;

  /// Отключить звук/сигналы (например, по настройке).
  set muted(bool v) => _muted = v;

  Future<void> success() async {
    if (_muted) return;
    // Успех: короткая вибро + системный клик.
    await Future.wait([
      HapticFeedback.heavyImpact(),
      SystemSound.play(SystemSoundType.click),
    ]);
  }

  Future<void> error() async {
    if (_muted) return;
    // Ошибка: длинная вибро + двойной сигнал.
    await HapticFeedback.vibrate();
    await Future.delayed(const Duration(milliseconds: 120));
    await HapticFeedback.vibrate();
  }

  Future<void> attention() async {
    if (_muted) return;
    // Внимание (множественное совпадение): средняя вибро.
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.mediumImpact();
  }
}
