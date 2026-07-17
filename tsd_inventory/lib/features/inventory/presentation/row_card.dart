import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../domain/doc_table_row.dart';

class RowCard extends StatelessWidget {
  const RowCard({
    super.key,
    required this.row,
    this.onLongPress,
    this.onTapBarcode,
  });
  final DocTableRow row;

  /// Долгое нажатие на карточке (например, для снятия факта сканирования).
  /// null → карточка не реагирует на нажатия.
  final VoidCallback? onLongPress;

  /// Нажатие на иконку штрихкода: открывает окно добавления (нет штрихкодов)
  /// или просмотра (есть штрихкоды). Иконка-кнопка в шапке строки.
  final VoidCallback? onTapBarcode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = row.isFound;
    final discrepancy = row.hasDiscrepancy;

    final bg = found
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;

    final card = Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  found ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: found ? scheme.secondary : scheme.outline,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.nomenclature,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTapBarcode != null)
                  // Иконка-кнопка состояния штрихкодов позиции:
                  // barcode_available.png — есть штрихкоды,
                  // barcode_missing.png — нет штрихкодов.
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                    icon: Image.asset(
                      'assets/icons/barcode_${row.hasBarcodes ? 'available' : 'missing'}.png',
                      width: 28,
                      height: 28,
                    ),
                    onPressed: onTapBarcode,
                    tooltip: row.hasBarcodes
                        ? AppStrings.viewBarcodesTitle
                        : AppStrings.addBarcodeTitle,
                  ),
              ],
            ),
            if (row.characteristic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text(
                  row.characteristic,
                  style: TextStyle(fontSize: 15, color: scheme.outline),
                ),
              ),
            if (row.inventoryNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text(
                  'Инв. ${row.inventoryNumber}',
                  style: TextStyle(fontSize: 15, color: scheme.outline),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 32),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(
                    AppStrings.qtyAccountingOf(row.qtyAccounting),
                    style: const TextStyle(fontSize: 16),
                  ),
                  Text(
                    AppStrings.qtyActualOf(row.qtyActual),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: found ? scheme.secondary : scheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (row.fio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text(
                  row.fio,
                  style: TextStyle(fontSize: 14, color: scheme.outline),
                ),
              ),
            if (discrepancy)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 32),
                child: Text(
                  '⚠ ${AppStrings.discrepancyOf(row.qtyActual, row.qtyAccounting)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // Long-press включается только когда передан колбэк (например, на
    // отсканированных позициях — для снятия факта).
    if (onLongPress == null) return card;
    return GestureDetector(
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}
