import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../domain/barcode_assignment.dart';
import '../domain/doc_table_row.dart';

class AddPositionToDocumentDialog extends StatelessWidget {
  const AddPositionToDocumentDialog({
    super.key,
    required this.barcode,
    required this.assignment,
  });

  final String barcode;
  final BarcodeAssignment assignment;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.addPositionToDocumentTitle),
      content: Text(
        AppStrings.addPositionToDocumentMessage(
          barcode: barcode,
          nomenclature: assignment.nomenclature,
          characteristic: assignment.characteristic,
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text(AppStrings.addToDocument),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class UnknownBarcodePromptDialog extends StatelessWidget {
  const UnknownBarcodePromptDialog({super.key, required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.unknownBarcodeTitle),
      content: Text(AppStrings.unknownBarcodeMessage(barcode)),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.createNomenclatureFromBarcode),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AmbiguousBarcodeDialog extends StatelessWidget {
  const AmbiguousBarcodeDialog({
    super.key,
    required this.candidates,
    required this.onSelected,
  });

  final List<DocTableRow> candidates;
  final ValueChanged<DocTableRow> onSelected;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.multipleMatches),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: candidates.length,
          itemBuilder: (context, index) {
            final row = candidates[index];
            return ListTile(
              title: Text(row.nomenclature),
              subtitle: Text(_subtitle(row)),
              onTap: () {
                Navigator.pop(context);
                onSelected(row);
              },
            );
          },
        ),
      ),
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          onPressed: () => Navigator.pop(context),
          child: const Text(AppStrings.cancel),
        ),
      ],
    );
  }

  String _subtitle(DocTableRow row) {
    final characteristic = row.characteristic.trim();
    final inventoryNumber = 'Инв. ${row.inventoryNumber}';
    return characteristic.isEmpty
        ? inventoryNumber
        : '$inventoryNumber | $characteristic';
  }
}

class UnscanDialog extends StatelessWidget {
  const UnscanDialog({
    super.key,
    required this.row,
    required this.onDecrement,
    required this.onReset,
  });

  final DocTableRow row;
  final VoidCallback onDecrement;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(AppStrings.unscanTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.nomenclature,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (row.characteristic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                row.characteristic,
                style: TextStyle(color: scheme.outline),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              AppStrings.qtyActualOf(row.qtyActual),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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
              onPressed: () {
                Navigator.pop(context);
                onDecrement();
              },
              child: const Text(AppStrings.unscanDecrement),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
              onPressed: () {
                Navigator.pop(context);
                onReset();
              },
              child: const Text(AppStrings.unscanReset),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(AppStrings.cancel),
            ),
          ],
        ),
      ],
    );
  }
}

class DeletePositionDialog extends StatelessWidget {
  const DeletePositionDialog({super.key, required this.row});

  final DocTableRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text(AppStrings.deletePositionTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.nomenclature,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (row.characteristic.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                row.characteristic,
                style: TextStyle(color: scheme.outline),
              ),
            ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actions: [
        SizedBox(
          width: double.maxFinite,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                child: const Text(AppStrings.deletePosition),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text(AppStrings.cancel),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
