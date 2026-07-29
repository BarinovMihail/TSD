import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/confirm_dialog.dart';
import '../../../core/result/result.dart';
import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../../docs/application/completed_docs_provider.dart';
import '../application/inventory_screen_controller.dart';
import '../application/scan_controller.dart';
import '../domain/barcode_assignment.dart';
import '../domain/doc_table_row.dart';
import 'barcode_capture_dialog.dart';
import 'barcode_dialog.dart';
import 'inventory_body.dart';
import 'inventory_dialogs.dart';
import 'unknown_barcode_dialog.dart';

export 'barcode_capture_dialog.dart' show BarcodeCaptureDialog;

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final KeyboardWedgeScanner _scanner;
  final _scanFocus = FocusNode();
  Completer<String>? _barcodeCapture;
  final Set<int> _deletingLineNumbers = {};

  @override
  void initState() {
    super.initState();
    _scanner = KeyboardWedgeScanner();
    _scanner.codes.listen(_onCode);
    // Авто-возврат фокуса к wedge-узлу: сканер снова работает после тапа
    // по полю поиска (там фокус нужен для набора, но затем возвращается сюда).
    _scanFocus.addListener(() {
      if (mounted && !_scanFocus.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final screenIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
          if (screenIsCurrent && !_scanFocus.hasFocus) {
            _scanFocus.requestFocus();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    final capture = _barcodeCapture;
    if (capture != null && !capture.isCompleted) capture.complete('');
    _scanner.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  ScanController? get _scan =>
      ref.read(inventoryScreenControllerProvider(widget.docCode).notifier).scan;

  Future<void> _onCode(String code) async {
    // В режиме привязки следующий код отдаётся окну добавления ШК и не
    // увеличивает фактическое количество позиции.
    final capture = _barcodeCapture;
    if (capture != null) {
      final trimmed = code.trim();
      if (trimmed.isNotEmpty && !capture.isCompleted) capture.complete(trimmed);
      return;
    }

    final scan = _scan;
    if (scan == null) return;
    final outcome = await scan.onScanned(code);
    if (!mounted) return;
    switch (outcome) {
      case Found():
        _showScanSuccess(outcome.row);
      case NotFoundInDocument():
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        await _resolveNotFoundBarcode(outcome.code);
      case Ambiguous():
        _showAmbiguous(outcome.candidates);
      case ScanIgnored():
        // Пустое после trim — игнорируем без反馈.
        break;
    }
  }

  void _showScanSuccess(DocTableRow row) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${AppStrings.scanSuccess}: ${row.nomenclature}'),
        backgroundColor: Theme.of(context).colorScheme.secondary,
        duration: const Duration(milliseconds: 800),
      ),
    );
  }

  Future<void> _resolveNotFoundBarcode(String code) async {
    final ctrl = ref.read(inventoryScreenControllerProvider(widget.docCode));
    final lookup = await ctrl.repo.getBarcodeAssignment(code);
    if (!mounted) return;
    if (lookup is Failure<BarcodeAssignment?>) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(AppStrings.barcodeLookupFailed),
          action: SnackBarAction(
            label: AppStrings.retry,
            onPressed: () => _onCode(code),
          ),
        ),
      );
      return;
    }

    final assignment = (lookup as Success<BarcodeAssignment?>).value;
    if (assignment == null) {
      await _showUnknownBarcode(code);
      return;
    }

    final scan = _scan;
    if (scan == null) return;
    final outcome = await scan.onRegisteredBarcode(code, assignment);
    if (!mounted) return;
    switch (outcome) {
      case Found():
        _showScanSuccess(outcome.row);
      case NotFoundInDocument():
        await _showAddToDocument(code, assignment);
      case Ambiguous():
        _showAmbiguous(outcome.candidates);
      case ScanIgnored():
        break;
    }
  }

  Future<void> _showAddToDocument(
    String code,
    BarcodeAssignment assignment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) =>
          AddPositionToDocumentDialog(barcode: code, assignment: assignment),
    );
    if (!mounted || confirmed != true) return;
    await _addMissingLine(assignment);
  }

  Future<void> _addMissingLine(BarcodeAssignment assignment) async {
    final scan = _scan;
    if (scan == null) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showMaterialBanner(
      MaterialBanner(
        content: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(AppStrings.addingToDocument),
          ],
        ),
        actions: const [SizedBox.shrink()],
      ),
    );
    final result = await scan.addMissingLine(assignment);
    if (!mounted) return;
    messenger.hideCurrentMaterialBanner();
    result.maybeWhen(
      onValue: (_) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(AppStrings.positionAddedToDocument),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      },
      orElse: (_) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text(AppStrings.addToDocumentFailed),
            action: SnackBarAction(
              label: AppStrings.retry,
              onPressed: () => _addMissingLine(assignment),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showUnknownBarcode(String code) async {
    final normalized = code.trim();
    try {
      final shouldCreate = await showDialog<bool>(
        context: context,
        builder: (context) => UnknownBarcodePromptDialog(barcode: normalized),
      );
      if (!mounted || shouldCreate != true) return;

      final ctrl = ref.read(inventoryScreenControllerProvider(widget.docCode));
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            UnknownBarcodeDialog(barcode: normalized, ctrl: ctrl),
      );
    } finally {
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanFocus.requestFocus();
        });
      }
    }
  }

  /// Открытие окна штрихкода позиции по тапу на иконку:
  /// есть штрихкоды → просмотр, нет штрихкодов → добавление.
  void _openBarcodeDialog(DocTableRow row) {
    final ctrl = ref.read(inventoryScreenControllerProvider(widget.docCode));
    showDialog<void>(
      context: context,
      builder: (ctx) => row.hasBarcodes
          ? ViewBarcodesDialog(
              lineNumber: row.lineNumber,
              ctrl: ctrl,
              onCaptureBarcode: _captureBarcodeFromItem,
            )
          : AddBarcodeDialog(
              row: row,
              ctrl: ctrl,
              onCaptureBarcode: _captureBarcodeFromItem,
            ),
    );
  }

  /// Временно переключает аппаратный сканер из режима подсчёта в режим
  /// получения штрихкода, который нужно привязать к выбранной строке.
  Future<String?> _captureBarcodeFromItem(DocTableRow row) async {
    if (_barcodeCapture != null) return null;
    final capture = Completer<String>();
    _barcodeCapture = capture;
    try {
      final value = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => BarcodeCaptureDialog(
          row: row,
          codeFuture: capture.future,
          scanner: _scanner,
        ),
      );
      final normalized = value?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    } finally {
      if (identical(_barcodeCapture, capture)) _barcodeCapture = null;
      if (!capture.isCompleted) capture.complete('');
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scanFocus.requestFocus();
        });
      }
    }
  }

  void _showAmbiguous(List<DocTableRow> candidates) {
    showDialog<void>(
      context: context,
      builder: (context) => AmbiguousBarcodeDialog(
        candidates: candidates,
        onSelected: (row) => _scan?.applyChoice(row),
      ),
    );
  }

  /// Диалог снятия факта сканирования позиции (долгое нажатие по карточке,
  /// где факт > 0): убрать единицу (−1) или сбросить факт (=0).
  void _showUnscanDialog(DocTableRow row) {
    showDialog<void>(
      context: context,
      builder: (context) => UnscanDialog(
        row: row,
        onDecrement: () => _scan?.decrementActual(row),
        onReset: () => _scan?.resetActual(row),
      ),
    );
  }

  Future<void> _confirmDeleteLine(DocTableRow row) async {
    if (_deletingLineNumbers.contains(row.lineNumber)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeletePositionDialog(row: row),
    );
    if (!mounted || confirmed != true) return;
    await _deleteLine(row);
  }

  Future<void> _deleteLine(DocTableRow row) async {
    if (_deletingLineNumbers.contains(row.lineNumber)) return;
    setState(() => _deletingLineNumbers.add(row.lineNumber));
    final ctrl = ref.read(inventoryScreenControllerProvider(widget.docCode));
    final result = await ctrl.deleteLineAndReload(row: row);
    if (!mounted) return;
    setState(() => _deletingLineNumbers.remove(row.lineNumber));

    switch (result.outcome) {
      case DeleteLineOutcome.done:
      case DeleteLineOutcome.verifiedAfterTimeout:
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: const Text(AppStrings.positionDeletedSuccess),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
        );
      case DeleteLineOutcome.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error?.userMessage ?? AppStrings.errGeneric),
            action: SnackBarAction(
              label: AppStrings.retry,
              onPressed: () => _deleteLine(row),
            ),
          ),
        );
      case DeleteLineOutcome.inconclusive:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(AppStrings.deletePositionInconclusive),
            action: SnackBarAction(
              label: AppStrings.retry,
              onPressed: () => _deleteLine(row),
            ),
          ),
        );
    }
  }

  Future<void> _finish() async {
    final scan = _scan;
    if (scan == null) return;
    // Нельзя завершить, если не отсканировано ни одной позиции.
    if (scan.scannedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала отсканируйте хотя бы одну позицию'),
        ),
      );
      return;
    }
    final fullyScanned = scan.isFullyScanned;
    // Расхождения считаем по отсканированным позициям (факт ≠ учёту).
    final hasDiscrepancies = scan.hasDiscrepancies;
    final discrepancyCount = scan.scannedDiscrepancyCount;

    // Приоритет: непросканировано (с учётом расхождений) → расхождения → всё ок.
    final Widget title;
    final Widget content;
    final String sendLabel;
    if (!fullyScanned) {
      final left = scan.total - scan.scannedCount;
      if (discrepancyCount > 0) {
        // Неполный список, но по отсканированным позициям есть расхождения.
        title = const Text('Отправить неполный результат с расхождениями?');
        content = Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Отсканировано '),
              b('${scan.scannedCount}'),
              const TextSpan(text: ' из '),
              b('${scan.total}'),
              const TextSpan(text: ' позиций, '),
              b('$left'),
              const TextSpan(text: ' не отсканировано.\n'),
              const TextSpan(text: 'По '),
              b('$discrepancyCount'),
              const TextSpan(
                text: ' отсканированным позициям факт не совпадает с учётом.',
              ),
            ],
          ),
        );
        sendLabel = 'Отправить неполное с расхождением';
      } else {
        title = const Text('Отправить неполный результат?');
        content = Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Отсканировано '),
              b('${scan.scannedCount}'),
              const TextSpan(text: ' из '),
              b('${scan.total}'),
              const TextSpan(text: ' позиций, '),
              b('$left'),
              const TextSpan(text: ' не отсканировано.'),
            ],
          ),
        );
        sendLabel = 'Отправить неполное';
      }
    } else if (hasDiscrepancies) {
      title = const Text('Отправить с расхождениями?');
      content = const Text(
        'Фактическое количество по некоторым позициям не совпадает с учётом.',
      );
      sendLabel = 'Отправить с расхождением';
    } else {
      title = const Text('Завершить и отправить?');
      content = const Text('Все позиции отсканированы без расхождений.');
      sendLabel = 'Отправить';
    }

    await ConfirmDialog.show(
      context,
      title: title,
      content: content,
      // Безопасное действие — рекомендуемое (заполненная кнопка, сверху).
      primaryLabel: 'Проверить ещё раз',
      onPrimary: () {}, // просто закрыть диалог, ничего не отправлять
      // Рискованное действие — отправка (outline, снизу).
      secondaryLabel: sendLabel,
      onSecondary: _doCommit,
    );
  }

  Future<void> _doCommit() async {
    final scan = _scan;
    if (scan == null) return;
    final res = await scan.commit();
    if (!mounted) return;
    res.maybeWhen(
      onValue: (_) {
        // Обновляем метку «отправлен» в списке документов.
        ref.invalidate(completedDocsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Результаты отправлены'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/docs');
      },
      orElse: (err) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.sendError),
            action: SnackBarAction(label: AppStrings.retry, onPressed: _finish),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(inventoryScreenControllerProvider(widget.docCode));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/docs'),
        ),
        title: Text(widget.docCode, style: const TextStyle(fontSize: 18)),
      ),
      body: ctrl.loading
          ? const Center(child: CircularProgressIndicator())
          : ctrl.loadError != null
          ? Center(
              child: Text(
                ctrl.loadError!,
                style: const TextStyle(fontSize: 18),
              ),
            )
          : Focus(
              focusNode: _scanFocus,
              onKeyEvent: _scanner.handleKeyEvent,
              autofocus: true,
              child: InventoryBody(
                controller: ctrl,
                onUnscan: _showUnscanDialog,
                onTapBarcode: _openBarcodeDialog,
                onDelete: _confirmDeleteLine,
                deletingLineNumbers: _deletingLineNumbers,
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            // Кнопка отключена, пока не отсканировано ни одной позиции.
            onPressed: (ctrl.scan?.scannedCount ?? 0) > 0 ? _finish : null,
            child: Text(
              '${AppStrings.finish} (${ctrl.scan?.scannedCount ?? 0}/${ctrl.scan?.total ?? 0})',
            ),
          ),
        ),
      ),
    );
  }
}
