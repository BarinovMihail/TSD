import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/update/application/update_controller.dart';
import 'package:tsd_inventory/core/update/data/apk_installer.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

class _MockRepo extends Mock implements UpdateRepository {}

class _MockInstaller extends Mock implements ApkInstaller {}

const _config = AppConfig(baseUrl: 'http://test-host/erp/');

VersionManifest _manifest({
  int versionCode = 5,
  bool required = false,
  String apkUrl = 'https://storage.example/file.apk?sig=abc',
  String sha256 = 'abc',
}) => VersionManifest(
  versionCode: versionCode,
  versionName: '0.5.0',
  apkUrl: apkUrl,
  releaseNotes: 'Тест',
  sha256: sha256,
  urlExpiresInSec: 600,
  required: required,
);

void main() {
  late _MockRepo repo;
  late _MockInstaller installer;

  setUp(() {
    repo = _MockRepo();
    installer = _MockInstaller();
    registerFallbackValue(File('x'));
  });

  group('checkAndPrompt', () {
    test('манифест новее текущей → UpdateAvailable', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateAvailable>());
      expect((controller.state as UpdateAvailable).manifest.versionCode, 5);
    });

    test('манифест равен текущей → UpdateIdle', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 2)));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('манифест старее текущей → UpdateIdle', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 1)));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('сетевая ошибка → тихо UpdateIdle (не мешает работе)', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test(
      'повторный вызов во время UpdateChecking не запускает второй запрос',
      () async {
        when(
          () => repo.checkForUpdate(any()),
        ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
        final controller = UpdateController(
          config: _config,
          repo: repo,
          installer: installer,
          currentVersionCodeProvider: () async => 2,
        );
        final f1 = controller.checkAndPrompt();
        final f2 = controller
            .checkAndPrompt(); // повтор, пока первая ещё в полёте
        await Future.wait([f1, f2]);

        verify(() => repo.checkForUpdate(any())).called(1);
        expect(controller.state, isA<UpdateAvailable>());
      },
    );

    test('повторный вызов при UpdateAvailable не сбрасывает диалог', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();
      expect(controller.state, isA<UpdateAvailable>());

      await controller.checkAndPrompt(); // не должен перезапросить/сбросить

      verify(() => repo.checkForUpdate(any())).called(1);
      expect(controller.state, isA<UpdateAvailable>());
    });
  });

  group('downloadAndInstall', () {
    test('успех → Downloading → Installing', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final apkFile = File('test_apk');
      when(
        () => repo.downloadApk(
          any(),
          sha256: any(named: 'sha256'),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Success(apkFile));
      when(() => installer.installApk(any())).thenAnswer((_) async {});
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateInstalling>());
      verify(() => installer.installApk(apkFile)).called(1);
    });

    test(
      'невалидный манифест (пустой sha256) → UpdateError без скачивания',
      () async {
        when(() => repo.checkForUpdate(any())).thenAnswer(
          (_) async => Success(_manifest(versionCode: 5, sha256: '')),
        );
        final controller = UpdateController(
          config: _config,
          repo: repo,
          installer: installer,
          currentVersionCodeProvider: () async => 2,
        );
        await controller.checkAndPrompt();

        await controller.downloadAndInstall();

        expect(controller.state, isA<UpdateError>());
        verifyNever(
          () => repo.downloadApk(
            any(),
            sha256: any(named: 'sha256'),
            targetDir: any(named: 'targetDir'),
            onProgress: any(named: 'onProgress'),
          ),
        );
        verifyNever(() => installer.installApk(any()));
      },
    );

    test('SHA-256 несовпадение → UpdateError', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          sha256: any(named: 'sha256'),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const Failure(IntegrityError()));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateError>());
      verifyNever(() => installer.installApk(any()));
    });

    test('сбой скачивания → UpdateError', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          sha256: any(named: 'sha256'),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateError>());
      verifyNever(() => installer.installApk(any()));
    });

    test('сбой установки (PlatformException) → UpdateError', () async {
      when(
        () => repo.checkForUpdate(any()),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          sha256: any(named: 'sha256'),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Success(File('test_apk')));
      when(() => installer.installApk(any())).thenThrow(Exception('denied'));
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateError>());
    });
  });

  group('required', () {
    test(
      'required=false → манифест доступен, skip сбрасывает в idle',
      () async {
        when(() => repo.checkForUpdate(any())).thenAnswer(
          (_) async => Success(_manifest(versionCode: 5, required: false)),
        );
        final controller = UpdateController(
          config: _config,
          repo: repo,
          installer: installer,
          currentVersionCodeProvider: () async => 2,
        );
        await controller.checkAndPrompt();

        expect(
          (controller.state as UpdateAvailable).manifest.required,
          isFalse,
        );

        controller.skip();

        expect(controller.state, isA<UpdateIdle>());
      },
    );

    test('required=true → манифест доступен с флагом обязательности', () async {
      when(() => repo.checkForUpdate(any())).thenAnswer(
        (_) async => Success(_manifest(versionCode: 5, required: true)),
      );
      final controller = UpdateController(
        config: _config,
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      expect((controller.state as UpdateAvailable).manifest.required, isTrue);
    });
  });
}
