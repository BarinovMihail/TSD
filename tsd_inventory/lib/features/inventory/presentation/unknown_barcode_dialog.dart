import 'package:flutter/material.dart';

import '../../../core/network/api_error.dart';
import '../../../core/result/result.dart';
import '../../../l10n/app_strings.dart';
import '../application/inventory_screen_controller.dart';
import '../domain/barcode_assignment.dart';

/// Выбор номенклатуры и характеристики для штрихкода, который не найден
/// в открытом документе.
class UnknownBarcodeDialog extends StatefulWidget {
  const UnknownBarcodeDialog({
    super.key,
    required this.barcode,
    required this.ctrl,
  });

  final String barcode;
  final InventoryScreenController ctrl;

  @override
  State<UnknownBarcodeDialog> createState() => _UnknownBarcodeDialogState();
}

class _UnknownBarcodeDialogState extends State<UnknownBarcodeDialog> {
  final _searchController = TextEditingController();

  List<String>? _nomenclatures;
  ApiError? _nomenclaturesError;
  String _query = '';

  String? _selectedNomenclature;
  List<String>? _characteristics;
  ApiError? _characteristicsError;
  String? _selectedCharacteristic;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _loadNomenclatures();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadNomenclatures() async {
    setState(() {
      _nomenclatures = null;
      _nomenclaturesError = null;
    });
    final result = await widget.ctrl.repo.getNomenclatures();
    if (!mounted) return;
    result.maybeWhen(
      onValue: (items) => setState(() => _nomenclatures = items),
      orElse: (error) => setState(() => _nomenclaturesError = error),
    );
  }

  Future<void> _selectNomenclature(String nomenclature) async {
    setState(() {
      _selectedNomenclature = nomenclature;
      _characteristics = null;
      _characteristicsError = null;
      _selectedCharacteristic = null;
    });
    final result = await widget.ctrl.repo.getCharacteristics(nomenclature);
    if (!mounted || _selectedNomenclature != nomenclature) return;
    result.maybeWhen(
      onValue: (items) {
        setState(() {
          _characteristics = items;
          // Если характеристик нет, в 1С передаётся пустая строка.
          _selectedCharacteristic = items.isEmpty ? '' : null;
        });
      },
      orElse: (error) => setState(() => _characteristicsError = error),
    );
  }

  void _changeNomenclature() {
    setState(() {
      _selectedNomenclature = null;
      _characteristics = null;
      _characteristicsError = null;
      _selectedCharacteristic = null;
    });
  }

  List<String> get _filteredNomenclatures {
    final items = _nomenclatures ?? const <String>[];
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return items;
    return [
      for (final item in items)
        if (item.toLowerCase().contains(query)) item,
    ];
  }

  Future<bool> _canAssignToSelectedPosition() async {
    final nomenclature = _selectedNomenclature;
    final characteristic = _selectedCharacteristic;
    if (nomenclature == null || characteristic == null) return false;

    final lookup = await widget.ctrl.repo.getBarcodeAssignment(widget.barcode);
    if (!mounted) return false;
    if (lookup is Failure<BarcodeAssignment?>) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(AppStrings.barcodeAssignmentCheckFailed)),
      );
      return false;
    }

    final current = (lookup as Success<BarcodeAssignment?>).value;
    if (current == null) return true;
    if (current.matches(
      nomenclature: nomenclature,
      characteristic: characteristic,
    )) {
      // ШК мог успеть записаться на предыдущей попытке, а /newStr — нет.
      // Разрешаем продолжить: контроллер распознает существующую привязку
      // и завершит добавление позиции в документ.
      return true;
    }

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text(AppStrings.barcodeAlreadyAssignedTitle),
            content: Text(
              AppStrings.barcodeTransferConfirm(
                barcode: widget.barcode,
                currentNomenclature: current.nomenclature,
                currentCharacteristic: current.characteristic,
                newNomenclature: nomenclature,
                newCharacteristic: characteristic,
              ),
            ),
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text(AppStrings.transferBarcode),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text(AppStrings.cancel),
                  ),
                ],
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> _assign() async {
    if (_sending) return;
    final nomenclature = _selectedNomenclature;
    final characteristic = _selectedCharacteristic;
    if (nomenclature == null || characteristic == null) return;

    setState(() => _sending = true);
    final canAssign = await _canAssignToSelectedPosition();
    if (!mounted) return;
    if (!canAssign) {
      setState(() => _sending = false);
      return;
    }

    final result = await widget.ctrl.assignUnknownBarcodeAndReload(
      nomenclature: nomenclature,
      characteristic: characteristic,
      barcode: widget.barcode,
    );
    if (!mounted) return;

    switch (result.outcome) {
      case AddBarcodeOutcome.done:
      case AddBarcodeOutcome.verifiedAfterTimeout:
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text(AppStrings.barcodeAndPositionAdded),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
        Navigator.of(context).pop(true);
      case AddBarcodeOutcome.failed:
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error?.userMessage ?? AppStrings.errGeneric),
            action: SnackBarAction(
              label: AppStrings.retry,
              onPressed: _assign,
            ),
          ),
        );
      case AddBarcodeOutcome.inconclusive:
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(AppStrings.errNetwork),
            action: SnackBarAction(
              label: AppStrings.retry,
              onPressed: _assign,
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.selectNomenclatureTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.sizeOf(context).height * 0.42,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.scannedBarcodeLabel,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            SelectableText(
              widget.barcode,
              style: const TextStyle(
                fontSize: 17,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _selectedNomenclature == null
                  ? _buildNomenclatureStep()
                  : _buildCharacteristicStep(),
            ),
          ],
        ),
      ),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedNomenclature != null) ...[
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed:
                    _selectedCharacteristic != null && !_sending
                    ? _assign
                    : null,
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(AppStrings.assignBarcode),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _sending ? null : _changeNomenclature,
                child: const Text(AppStrings.changeNomenclature),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
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

  Widget _buildNomenclatureStep() {
    final error = _nomenclaturesError;
    if (error != null) {
      return _LoadError(error: error, onRetry: _loadNomenclatures);
    }
    final allItems = _nomenclatures;
    if (allItems == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(AppStrings.loadingNomenclatures),
          ],
        ),
      );
    }

    final items = _filteredNomenclatures;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: AppStrings.searchNomenclature,
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: items.isEmpty
              ? const Center(child: Text(AppStrings.nomenclaturesEmpty))
              : ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      title: Text(item),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _selectNomenclature(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCharacteristicStep() {
    final nomenclature = _selectedNomenclature!;
    final error = _characteristicsError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.nomenclatureLabel,
          style: TextStyle(
            fontSize: 13,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        Text(
          nomenclature,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (error != null)
          Expanded(
            child: _LoadError(
              error: error,
              onRetry: () => _selectNomenclature(nomenclature),
            ),
          )
        else if (_characteristics == null)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text(AppStrings.loadingCharacteristics),
                ],
              ),
            ),
          )
        else if (_characteristics!.isEmpty)
          const Expanded(
            child: Center(
              child: Text(AppStrings.withoutCharacteristic),
            ),
          )
        else ...[
          const Text(
            AppStrings.selectCharacteristic,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RadioGroup<String>(
              groupValue: _selectedCharacteristic,
              onChanged: (value) {
                if (!_sending) {
                  setState(() => _selectedCharacteristic = value);
                }
              },
              child: ListView(
                children: [
                  for (final characteristic in _characteristics!)
                    RadioListTile<String>(
                      value: characteristic,
                      enabled: !_sending,
                      title: Text(characteristic),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final ApiError error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            error.userMessage,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }
}
