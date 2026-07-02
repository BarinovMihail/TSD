import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../../docs/application/completed_docs_provider.dart';
import '../application/inventory_screen_controller.dart';
import '../application/scan_controller.dart';
import '../domain/doc_table_row.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.scanSuccess}: ${outcome.row.nomenclature}'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(milliseconds: 800),
        ));
      case NotFound():
        _showNotFound(code);
      case Ambiguous():
        _showAmbiguous(outcome.candidates);
    }
  }

  void _showNotFound(String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final manualCtrl = TextEditingController();
        return AlertDialog(
          title: Text(AppStrings.notFoundCode(code)),
          content: TextField(
            controller: manualCtrl,
            decoration:
                const InputDecoration(labelText: AppStrings.enterManually),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.cancel)),
            ElevatedButton(
              onPressed: () {
                final v = manualCtrl.text.trim();
                Navigator.pop(ctx);
                if (v.isNotEmpty) _onCode(v);
              },
              child: const Text(AppStrings.confirm),
            ),
          ],
        );
      },
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
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.cancel)),
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

  Future<void> _finish() async {
    final scan = _scan;
    if (scan == null) return;
    final hasDiscrepancies = scan.hasDiscrepancies;
    final fullyScanned = scan.isFullyScanned;
    // Приоритет: непросканировано → расхождения → всё ок.
    final String title;
    final String contentText;
    final String confirmLabel;
    if (!fullyScanned) {
      final left = scan.total - scan.scannedCount;
      title = 'Отправить неполные результаты?';
      contentText = 'Отсканировано ${scan.scannedCount} из ${scan.total} '
          'позиций ($left не отсканировано). Отправить как есть?';
      confirmLabel = 'Отправить неполное';
    } else if (hasDiscrepancies) {
      title = 'Отправить результаты с расхождениями?';
      contentText =
          'По некоторым позициям фактическое количество не совпадает с учётом. '
          'Результаты будут отправлены как есть.';
      confirmLabel = 'Отправить с расхождением';
    } else {
      title = 'Завершить и отправить?';
      contentText =
          'Все позиции отсканированы без расхождений. Отправить результаты в 1С?';
      confirmLabel = 'Отправить';
    }
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(title),
            content: Text(contentText),
            actionsAlignment: MainAxisAlignment.spaceBetween,
            actionsOverflowAlignment: OverflowBarAlignment.center,
            actionsOverflowButtonSpacing: 8,
            actions: [
              OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Проверить ещё раз')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirmLabel)),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final res = await scan.commit();
    if (!mounted) return;
    res.maybeWhen(
      onValue: (_) {
        // Обновляем метку «отправлен» в списке документов.
        ref.invalidate(completedDocsProvider);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Результаты отправлены'),
            backgroundColor: Colors.green));
        context.go('/docs');
      },
      orElse: (err) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.sendError),
          action: SnackBarAction(label: AppStrings.retry, onPressed: _finish),
        ));
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
                  child: Text(ctrl.loadError!,
                      style: const TextStyle(fontSize: 18)))
              : Focus(
                  focusNode: _scanFocus,
                  onKeyEvent: _scanner.handleKeyEvent,
                  autofocus: true,
                  child: _Body(ctrl: ctrl),
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _finish,
            child: Text(
                '${AppStrings.finish} (${ctrl.scan?.scannedCount ?? 0}/${ctrl.scan?.total ?? 0})'),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.ctrl});
  final InventoryScreenController ctrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Слушаем ctrl (он перенаправляет notifyListeners от ScanController).
    ref.watch(inventoryScreenControllerProvider(ctrl.docCode));

    final scan = ctrl.scan!;

    // Фильтр + сортировка.
    var rows = List<DocTableRow>.from(scan.rows);
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
                      fontSize: 18, fontWeight: FontWeight.w600),
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
        // Список строк + pull-to-refresh.
        Expanded(
          child: RefreshIndicator(
            onRefresh: ctrl.reload,
            child: ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, i) => RowCard(row: rows[i]),
            ),
          ),
        ),
      ],
    );
  }
}
