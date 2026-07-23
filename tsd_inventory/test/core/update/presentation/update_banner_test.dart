import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/update/application/update_controller.dart';
import 'package:tsd_inventory/core/update/data/apk_installer.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';
import 'package:tsd_inventory/core/update/presentation/update_banner.dart';

class _MockRepo extends Mock implements UpdateRepository {}

class _MockInstaller extends Mock implements ApkInstaller {}

const _manifest = VersionManifest(
  versionCode: 9,
  versionName: '0.2.7',
  apkPath: 'releases/tsd-inventory-0.2.7-9.zip',
  releaseNotes: 'Добавлена плашка обновления',
  sha256: 'abc',
  required: false,
);

void main() {
  late UpdateController controller;

  setUp(() {
    controller = UpdateController(
      repo: _MockRepo(),
      installer: _MockInstaller(),
      currentVersionCodeProvider: () async => 8,
    );
    controller.state = const UpdateAvailable(_manifest);
  });

  testWidgets('показывает версию, заметки и действия', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateBanner(controller: controller, manifest: _manifest),
        ),
      ),
    );

    expect(find.text('Доступна новая версия 0.2.7'), findsOneWidget);
    expect(find.text('Добавлена плашка обновления'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
    expect(find.text('Позже'), findsOneWidget);
  });

  testWidgets('кнопка «Позже» сбрасывает обновление', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpdateBanner(controller: controller, manifest: _manifest),
        ),
      ),
    );

    await tester.tap(find.text('Позже'));
    await tester.pump();

    expect(controller.state, isA<UpdateIdle>());
  });
}
