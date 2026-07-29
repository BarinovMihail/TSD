import 'package:flutter/material.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../domain/doc_table_row.dart';

/// Диалог, который временно направляет ввод аппаратного сканера в операцию
/// привязки штрихкода к выбранной строке.
class BarcodeCaptureDialog extends StatefulWidget {
  const BarcodeCaptureDialog({
    super.key,
    required this.row,
    required this.codeFuture,
    required this.scanner,
  });

  final DocTableRow row;
  final Future<String> codeFuture;
  final KeyboardWedgeScanner scanner;

  @override
  State<BarcodeCaptureDialog> createState() => _BarcodeCaptureDialogState();
}

class _BarcodeCaptureDialogState extends State<BarcodeCaptureDialog> {
  final _focusNode = FocusNode(debugLabel: 'barcode-capture');

  @override
  void initState() {
    super.initState();
    widget.codeFuture.then((code) {
      if (mounted) Navigator.of(context).pop(code);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: widget.scanner.handleKeyEvent,
      child: AlertDialog(
        title: const Text(AppStrings.scanBarcodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.row.nomenclature,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            if (widget.row.characteristic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(widget.row.characteristic),
              ),
            const SizedBox(height: 16),
            const Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text(AppStrings.scanBarcodePrompt)),
              ],
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(AppStrings.cancel),
          ),
        ],
      ),
    );
  }
}
