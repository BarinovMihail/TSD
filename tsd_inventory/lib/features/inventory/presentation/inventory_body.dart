import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../application/inventory_screen_controller.dart';
import '../domain/doc_table_row.dart';
import 'row_card.dart';

class InventoryBody extends ConsumerWidget {
  const InventoryBody({
    super.key,
    required this.controller,
    required this.onMarkPresent,
    required this.onUnscan,
    required this.onTapBarcode,
    required this.onDelete,
    required this.deletingLineNumbers,
  });

  final InventoryScreenController controller;
  final ValueChanged<DocTableRow> onMarkPresent;
  final ValueChanged<DocTableRow> onUnscan;
  final ValueChanged<DocTableRow> onTapBarcode;
  final ValueChanged<DocTableRow> onDelete;
  final Set<int> deletingLineNumbers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Контроллер перенаправляет уведомления ScanController, поэтому список
    // перестраивается и при изменении прогресса сканирования.
    ref.watch(inventoryScreenControllerProvider(controller.docCode));

    final scan = controller.scan!;
    final rows = controller.visibleRows;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.scannedProgressOf(scan.scannedCount, scan.total),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: LinearProgressIndicator(
            value: scan.total == 0 ? 0 : scan.scannedCount / scan.total,
            minHeight: 10,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(labelText: AppStrings.search),
            onChanged: controller.setSearch,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text(AppStrings.sortUnscannedFirst),
                  selected: controller.unscannedFirst,
                  onSelected: controller.toggleSort,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text(AppStrings.onlyWithoutBarcode),
                  selected: controller.onlyWithoutBarcode,
                  onSelected: controller.toggleOnlyWithoutBarcode,
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await controller.reload();
            },
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final row = rows[index];
                return RowCard(
                  row: row,
                  onMarkPresent: () => onMarkPresent(row),
                  onTapBarcode: () => onTapBarcode(row),
                  onDelete: () => onDelete(row),
                  deleting: deletingLineNumbers.contains(row.lineNumber),
                  onLongPress: row.isFound ? () => onUnscan(row) : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
