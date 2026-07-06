import 'package:flutter/material.dart';

/// Единый диалог подтверждения для приложения.
///
/// Принципы (для ТСД, крупными пальцами):
/// - кнопки в виде ВЕРТИКАЛЬНОГО СТЕКА, каждая на всю ширину — легко попасть;
/// - primary (рекомендуемое/безопасное действие) сверху — заполненная [FilledButton];
/// - secondary (рискованное/подтверждающее действие) снизу — [OutlinedButton];
/// - единая высота/радиус скругления кнопок (10px);
/// - отступ 12px между кнопками для чётких зон тапа.
///
/// primary (верхняя, заполненная) — БЕЗОПАСНОЕ действие, рекомендуемое по умолчанию.
/// secondary (нижняя, outline) — рискованное действие, требующее осознанного выбора.
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.content,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.destructiveSecondary = false,
  });

  final Widget title;
  final Widget content;
  final String primaryLabel; // рекомендуемое (заполненная, сверху)
  final VoidCallback onPrimary;
  final String secondaryLabel; // рискованное/подтверждающее (outline, снизу)
  final VoidCallback onSecondary;
  // true → secondary (нижняя) кнопка красная, для деструктивных подтверждений.
  final bool destructiveSecondary;

  /// Показать диалог с колбэками. После любого выбора диалог закрывается
  /// и вызывается соответствующий колбэк.
  static Future<void> show(
    BuildContext context, {
    required Widget title,
    required Widget content,
    required String primaryLabel,
    required VoidCallback onPrimary,
    required String secondaryLabel,
    required VoidCallback onSecondary,
    bool destructiveSecondary = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ConfirmDialog(
        title: title,
        content: content,
        primaryLabel: primaryLabel,
        onPrimary: () {
          Navigator.of(ctx).pop();
          onPrimary();
        },
        secondaryLabel: secondaryLabel,
        onSecondary: () {
          Navigator.of(ctx).pop();
          onSecondary();
        },
        destructiveSecondary: destructiveSecondary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        child: title,
      ),
      content: DefaultTextStyle.merge(
        style: TextStyle(fontSize: 18, height: 1.35, color: scheme.onSurface),
        child: content,
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Primary (рекомендуемое/безопасное действие) — заполненная, сверху.
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
            const SizedBox(height: 12),
            // Secondary (рискованное/подтверждающее) — outline, снизу.
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    destructiveSecondary ? scheme.error : scheme.primary,
                side: BorderSide(
                  color: destructiveSecondary ? scheme.error : scheme.primary,
                ),
              ),
              onPressed: onSecondary,
              child: Text(secondaryLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// Жирный фрагмент для inline-выделения чисел в Text.rich.
InlineSpan b(String text) =>
    TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w700));
