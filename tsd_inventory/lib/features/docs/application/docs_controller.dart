import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/features/auth/application/auth_controller.dart';

import '../data/docs_repository.dart';
import '../domain/doc_list_item.dart';

/// Загрузка списка документов для текущего пользователя.
/// AsyncValue (loading/data/error одной сущностью).
class DocsController extends AsyncNotifier<List<DocListItem>> {
  late String _fio;
  late DocsRepository _repo;

  @override
  Future<List<DocListItem>> build() async {
    final session = ref.watch(authControllerProvider).session;
    if (session == null) {
      state = const AsyncValue.error('Не авторизован', StackTrace.empty);
      return [];
    }
    _fio = session.fio;
    _repo = ref.watch(docsRepositoryProvider);
    return _load();
  }

  Future<List<DocListItem>> _load() async {
    final res = await _repo.getByFio(_fio);
    return res.maybeWhen(
      onValue: (v) => v,
      orElse: (err) => throw Exception(err.userMessage),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }
}

final docsControllerProvider =
    AsyncNotifierProvider<DocsController, List<DocListItem>>(DocsController.new);

/// Фабрика DocsRepository: использует DioClient с учёткой текущей сессии.
final docsRepositoryProvider = Provider<DocsRepository>((ref) {
  final session = ref.watch(authControllerProvider).session!;
  final config = ref.watch(appConfigProvider);
  final client = DioClient(
    config: config,
    credentials: BasicCredentials(session.login, session.password),
  );
  return DocsRepository(client);
});
