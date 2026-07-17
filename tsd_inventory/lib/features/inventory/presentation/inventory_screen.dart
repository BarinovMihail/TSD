import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/confirm_dialog.dart';
import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../../docs/application/completed_docs_provider.dart';
import '../application/inventory_screen_controller.dart';
import '../application/scan_controller.dart';
import '../domain/doc_table_row.dart';
import 'barcode_dialog.dart';
import 'row_card.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final KeyboardWedgeScanner _scanner;
  final _scanFocus = FocusNode();

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
          if (mounted && !_scanFocus.hasFocus) _scanFocus.requestFocus();
        });
      }
    });
  }

  @override
  void dispose() {
    _scanner.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  ScanController? get _scan =>
      ref.read(inventoryScreenControllerProvider(widget.docCode).notifier).scan;

  Future<void> _onCode(String code) async {
    final scan = _scan;
    if (scan == null) return;
    final outcome = await scan.onScanned(code);
    if (!mounted) return;
    switch (outcome) {
      case Found():
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${AppStrings.scanSuccess}: ${outcome.row.nomenclature}',
            ),
            backgroundColor: Theme.of(context).colorScheme.secondary,
            duration: const Duration(milliseconds: 800),
          ),
        );
      case NotFoundInDocument():
        // Штрихкод отсутствует во всех массивах «Штрихкоды» строк документа.
        // Резервный запрос и добавление номенклатуры больше не предлагаются.
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(AppStrings.barcodeNotFoundInDoc),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: const Duration(seconds: 2),
          ),
        );
      case Ambiguous():
        _showAmbiguous(outcome.candidates);
      case ScanIgnored():
        // Пустое после trim — игнорируем без反馈.
        break;
    }
  }

  /// Открытие окна штрихкода позиции по тапу на иконку:
  /// есть штрихкоды → просмотр, нет штрихкодов → добавление.
  void _openBarcodeDialog(DocTableRow row) {
    final ctrl = ref.read(inventoryScreenControllerProvider(widget.docCode));
    showDialog<void>(
      context: context,
      builder: (ctx) => row.hasBarcodes
          ? ViewBarcodesDialog(lineNumber: row.lineNumber, ctrl: ctrl)
          : AddBarcodeDialog(row: row, ctrl: ctrl),
    );
  }

  void _showAmbiguous(List<DocTableRow> candidates) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.multipleMatches),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (ctx, i) {
              final r = candidates[i];
              return ListTile(
                title: Text(r.nomenclature),
                subtitle: Text(_ambiguousSubTitle(r)),
                onTap: () {
                  Navigator.pop(ctx);
                  _scan?.applyChoice(r);
                },
              );
            },
          ),
        ),
        actions: [
          // Отмена на всю ширину (outline) — единственное действие.
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text(AppStrings.cancel),
          ),
        ],
      ),
    );
  }

  /// Подпись строки в списке неоднозначных совпадений: инв. номер и
  /// характеристика (чтобы различить одинаковые позиции по характеристике).
  String _ambiguousSubTitle(DocTableRow r) {
    final char = r.characteristic.trim();
    final inv = 'Инв. ${r.inventoryNumber}';
    return char.isEmpty ? inv : '$inv | $char';
  }

  /// Диалог снятия факта сканирования позиции (долгое нажатие по карточке,
  /// где факт > 0): убрать единицу (−1) или сбросить факт (=0).
  void _showUnscanDialog(DocTableRow row) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Primary (безопасное) — убрать одну единицу (заполненная, сверху).
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
                    Navigator.pop(ctx);
                    _scan?.decrementActual(row);
                  },
                  child: const Text(AppStrings.unscanDecrement),
                ),
                const SizedBox(height: 12),
                // Деструктивное — сброс факта в 0 (outline, красная).
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _scan?.resetActual(row);
                  },
                  child: const Text(AppStrings.unscanReset),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(AppStrings.cancel),
                ),
              ],
            ),
          ],
        );
      },
    );
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
              child: _Body(
                ctrl: ctrl,
                onUnscan: _showUnscanDialog,
                onTapBarcode: _openBarcodeDialog,
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

class _Body extends ConsumerWidget {
  const _Body({
    required this.ctrl,
    required this.onUnscan,
    required this.onTapBarcode,
  });
  final InventoryScreenController ctrl;

  /// Долгое нажатие по отсканированной позиции → диалог снятия факта.
  final void Function(DocTableRow row) onUnscan;

  /// Тап по иконке штрихкода → окно добавления/просмотра штрихкодов.
  final void Function(DocTableRow row) onTapBarcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Слушаем ctrl (он перенаправляет notifyListeners от ScanController).
    ref.watch(inventoryScreenControllerProvider(ctrl.docCode));

    final scan = ctrl.scan!;

    // Фильтр + сортировка.
    var rows = List<DocTableRow>.from(scan.rows);
    // Фильтр «Только без штрихкода»: только строки без штрихкодов.
    // Данные и прогресс сканирования не меняет.
    if (ctrl.onlyWithoutBarcode) {
      rows = rows.where((r) => r.barcodes.isEmpty).toList();
    }
    final q = ctrl.searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((r) {
        return r.nomenclature.toLowerCase().contains(q) ||
            r.inventoryNumber.toLowerCase().contains(q) ||
            r.nomenclatureCode.toLowerCase().contains(q);
      }).toList();
    }
    rows.sort((a, b) {
      if (ctrl.unscannedFirst) {
        final af = a.isFound ? 1 : 0;
        final bf = b.isFound ? 1 : 0;
        if (af != bf) return af - bf;
      }
      return a.lineNumber.compareTo(b.lineNumber);
    });

    return Column(
      children: [
        // Прогресс.
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
        // Фильтр.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(labelText: AppStrings.search),
            onChanged: ctrl.setSearch,
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: ctrl.unscannedFirst,
          onChanged: ctrl.toggleSort,
          title: const Text(AppStrings.sortUnscannedFirst),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: ctrl.onlyWithoutBarcode,
          onChanged: ctrl.toggleOnlyWithoutBarcode,
          title: const Text(AppStrings.onlyWithoutBarcode),
        ),
        // Список строк + pull-to-refresh.
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ctrl.reload(),
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => RowCard(
                row: rows[i],
                // Иконка штрихкода всегда активна (добавить/посмотреть).
                onTapBarcode: () => onTapBarcode(rows[i]),
                // Long-press доступен только для отсканированных позиций.
                onLongPress: rows[i].isFound ? () => onUnscan(rows[i]) : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
