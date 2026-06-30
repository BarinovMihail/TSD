import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../application/inventory_screen_controller.dart';
import '../application/scan_controller.dart';
import '../domain/doc_table_row.dart';
import 'keyboard_wedge_field.dart';
import 'row_card.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final KeyboardWedgeScanner _scanner;

  @override
  void initState() {
    super.initState();
    _scanner = KeyboardWedgeScanner();
    _scanner.codes.listen(_onCode);
  }

  @override
  void dispose() {
    _scanner.dispose();
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
                subtitle: Text('Инв. ${r.inventoryNumber}'),
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

  Future<void> _finish() async {
    final scan = _scan;
    if (scan == null) return;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.finish),
            content: Text(AppStrings.finishConfirm),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(AppStrings.no)),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(AppStrings.yes)),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final res = await scan.commit();
    if (!mounted) return;
    res.maybeWhen(
      onValue: (_) {
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
              : _Body(ctrl: ctrl, scanner: _scanner),
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
  const _Body({required this.ctrl, required this.scanner});
  final InventoryScreenController ctrl;
  final KeyboardWedgeScanner scanner;

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
        // Сканер-поле.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: KeyboardWedgeField(scanner: scanner),
        ),
        // Список строк.
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => RowCard(row: rows[i]),
          ),
        ),
      ],
    );
  }
}
