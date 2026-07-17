import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../l10n/app_strings.dart';
import '../application/inventory_screen_controller.dart';
import '../domain/doc_table_row.dart';

/// Окно добавления штрихкода для позиции без штрихкодов (barcode_missing).
///
/// Показывает номенклатуру (не редактируется) и характеристику: если она уже
/// заполнена в строке — показывается предзаполненной; иначе загружается список
/// характеристик выбранной номенклатуры (GET /hs/inventory/invent/{Номенклатура})
/// с вариантом «Без характеристики» (отправляется пустая строка).
///
/// POST /hs/inventory/newBarcode → при успехе перезагрузка документа, новый
/// штрихкод берётся из обновлённого массива «Штрихкоды». Окно не закрывается
/// до получения результата отправки.
class AddBarcodeDialog extends ConsumerStatefulWidget {
  const AddBarcodeDialog({super.key, required this.row, required this.ctrl});
  final DocTableRow row;
  final InventoryScreenController ctrl;

  @override
  ConsumerState<AddBarcodeDialog> createState() => _AddBarcodeDialogState();
}

class _AddBarcodeDialogState extends ConsumerState<AddBarcodeDialog> {
  List<String>? _characteristics; // null — ещё не загружены
  ApiError? _loadError;
  String? _selected; // выбранная характеристика ('' = «Без характеристики»)
  bool _sending = false;

  bool get _charPrefilled => widget.row.characteristic.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_charPrefilled) {
      _selected = widget.row.characteristic;
      _characteristics = const []; // список не нужен — характеристика уже есть
    } else {
      _loadCharacteristics();
    }
  }

  Future<void> _loadCharacteristics() async {
    setState(() {
      _characteristics = null;
      _loadError = null;
    });
    final res = await widget.ctrl.repo.getCharacteristics(
      widget.row.nomenclature,
    );
    if (!mounted) return;
    res.maybeWhen(
      onValue: (list) {
        setState(() {
          _characteristics = list;
          // По умолчанию — «Без характеристики», если список не пуст —
          // пользователь может выбрать конкретную.
          _selected = '';
        });
      },
      orElse: (err) {
        setState(() {
          _loadError = err;
        });
      },
    );
  }

  Future<void> _add() async {
    if (_sending) return; // защита от двойного нажатия
    final characteristic = _selected ?? '';
    final prevBarcodes = <String>{...widget.row.barcodes};
    setState(() => _sending = true);
    final result = await widget.ctrl.addBarcodeAndReload(
      nomenclature: widget.row.nomenclature,
      characteristic: characteristic,
      prevBarcodes: prevBarcodes,
    );
    if (!mounted) return;
    switch (result.outcome) {
      case AddBarcodeOutcome.done:
      case AddBarcodeOutcome.verifiedAfterTimeout:
        // Штрихкод записан и виден в данных — закрываем окно.
        if (mounted) Navigator.of(context).pop(true);
      case AddBarcodeOutcome.failed:
        // Штрихкод НЕ записан — показываем ошибку 1С, окно оставляем.
        setState(() => _sending = false);
        if (result.error != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.error!.userMessage)));
        }
      case AddBarcodeOutcome.inconclusive:
        // Нет ответа 1С и штрихкод в данных не появился — «Повторить».
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(AppStrings.errNetwork),
            action: SnackBarAction(label: AppStrings.retry, onPressed: _add),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Слушаем контроллер, чтобы иконка/состояние обновлялись после reload.
    ref.watch(inventoryScreenControllerProvider(widget.ctrl.docCode));
    return AlertDialog(
      title: const Text(AppStrings.addBarcodeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Номенклатура — только чтение.
            Text(
              widget.row.nomenclature,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _characteristicField(scheme),
          ],
        ),
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _canSubmit ? (_sending ? null : _add) : null,
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.addBarcode),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: _sending
                  ? null
                  : () => Navigator.of(context).pop(false),
              child: const Text(AppStrings.cancel),
            ),
          ],
        ),
      ],
    );
  }

  bool get _canSubmit {
    if (_sending) return true;
    if (_charPrefilled) return true; // характеристика уже есть
    return _characteristics != null && _loadError == null;
  }

  Widget _characteristicField(ColorScheme scheme) {
    if (_charPrefilled) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.characteristicLabel,
            style: TextStyle(fontSize: 14, color: scheme.outline),
          ),
          Text(widget.row.characteristic, style: const TextStyle(fontSize: 16)),
        ],
      );
    }
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_loadError!.userMessage, style: TextStyle(color: scheme.error)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _loadCharacteristics,
            child: const Text(AppStrings.retry),
          ),
        ],
      );
    }
    final list = _characteristics;
    if (list == null) {
      return const Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(AppStrings.loadingCharacteristics),
        ],
      );
    }
    // Вариант «Без характеристики» (значение '') + загруженные.
    final items = <String>['', ...list];
    return DropdownButtonFormField<String>(
      decoration: const InputDecoration(
        labelText: AppStrings.characteristicLabel,
      ),
      initialValue: _selected ?? '',
      items: [
        for (final c in items)
          DropdownMenuItem(
            value: c,
            child: Text(c.isEmpty ? AppStrings.withoutCharacteristic : c),
          ),
      ],
      onChanged: _sending
          ? null
          : (v) {
              if (v != null) setState(() => _selected = v);
            },
    );
  }
}

/// Окно просмотра штрихкодов позиции (barcode_available): номенклатура,
/// характеристика, полный список всех штрихкодов, кнопка «Добавить новый
/// штрихкод» и «Закрыть». Существующие штрихкоды не удаляются и не меняются.
/// После успешного добавления список обновляется из перезагруженного документа.
class ViewBarcodesDialog extends ConsumerStatefulWidget {
  const ViewBarcodesDialog({
    super.key,
    required this.lineNumber,
    required this.ctrl,
  });
  final int lineNumber;
  final InventoryScreenController ctrl;

  @override
  ConsumerState<ViewBarcodesDialog> createState() => _ViewBarcodesDialogState();
}

class _ViewBarcodesDialogState extends ConsumerState<ViewBarcodesDialog> {
  bool _sending = false;

  DocTableRow? get _row {
    final rows = widget.ctrl.scan?.rows ?? const <DocTableRow>[];
    for (final r in rows) {
      if (r.lineNumber == widget.lineNumber) return r;
    }
    return null;
  }

  Future<void> _addNew() async {
    if (_sending) return;
    final row = _row;
    if (row == null) return;
    final prevBarcodes = <String>{...row.barcodes};
    setState(() => _sending = true);
    final result = await widget.ctrl.addBarcodeAndReload(
      nomenclature: row.nomenclature,
      characteristic: row.characteristic,
      prevBarcodes: prevBarcodes,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    switch (result.outcome) {
      case AddBarcodeOutcome.done:
      case AddBarcodeOutcome.verifiedAfterTimeout:
        // Штрихкод записан — список обновлён из перезагруженного документа.
        break;
      case AddBarcodeOutcome.failed:
        // Штрихкод НЕ записан — ошибка 1С.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error?.userMessage ?? AppStrings.errGeneric),
            action: SnackBarAction(label: AppStrings.retry, onPressed: _addNew),
          ),
        );
      case AddBarcodeOutcome.inconclusive:
        // Нет ответа 1С и штрихкод не подтвердился перезагрузкой — «Повторить».
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(AppStrings.errNetwork),
            action: SnackBarAction(label: AppStrings.retry, onPressed: _addNew),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Слушаем контроллер: после reload список штрихкодов обновится.
    ref.watch(inventoryScreenControllerProvider(widget.ctrl.docCode));
    final row = _row;
    final barcodes = row?.barcodes ?? const <String>[];
    return AlertDialog(
      title: const Text(AppStrings.viewBarcodesTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row != null)
                Text(
                  row.nomenclature,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (row != null && row.characteristic.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    row.characteristic,
                    style: TextStyle(fontSize: 15, color: scheme.outline),
                  ),
                ),
              const SizedBox(height: 12),
              if (barcodes.isEmpty)
                Text(
                  AppStrings.noBarcodesYet,
                  style: TextStyle(color: scheme.outline),
                )
              else
                for (final b in barcodes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(60),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: _sending ? null : _addNew,
              child: _sending
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(AppStrings.addNewBarcode),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(AppStrings.close),
            ),
          ],
        ),
      ],
    );
  }
}
