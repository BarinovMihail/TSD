import 'package:flutter/material.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';

/// Виджет, держащий фокус на скрытом TextField для приёма keyboard wedge.
/// После каждого submit возвращает фокус, чтобы случайный тап не терял сканер.
class KeyboardWedgeField extends StatefulWidget {
  const KeyboardWedgeField({super.key, required this.scanner});
  final KeyboardWedgeScanner scanner;

  @override
  State<KeyboardWedgeField> createState() => _KeyboardWedgeFieldState();
}

class _KeyboardWedgeFieldState extends State<KeyboardWedgeField> {
  final _focus = FocusNode();
  final _ctrl = TextEditingController();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _keepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _keepFocus,
      child: Stack(
        children: [
          // Визуальная плашка-индикатор.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _focused ? scheme.primary : scheme.outline, width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner,
                    size: 30, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _focused ? AppStrings.readyToScan : 'Коснитесь и сканируйте',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          // Скрытое поле поверх плашки (прозрачное, высота как у плашки).
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 56,
              child: TextField(
                focusNode: _focus,
                controller: _ctrl,
                autofocus: true,
                onChanged: widget.scanner.onTextChanged,
                onSubmitted: (v) {
                  widget.scanner.onSubmitted(v);
                  _ctrl.clear();
                  _keepFocus();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
