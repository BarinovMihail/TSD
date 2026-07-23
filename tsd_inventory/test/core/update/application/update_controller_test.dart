import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/update/application/update_controller.dart';
import 'package:tsd_inventory/core/update/data/apk_installer.dart';
import 'package:tsd_inventory/core/update/data/update_repository.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

class _MockRepo extends Mock implements UpdateRepository {}

class _MockInstaller extends Mock implements ApkInstaller {}

/// Fallback для mocktail: downloadApk принимает VersionManifest, а в stub-ах
/// используется any() — mocktail требует валидное значение типа.
class _ManifestFake extends Fake implements VersionManifest {}

VersionManifest _manifest({
  int versionCode = 5,
  bool required = false,
  String apkPath = 'releases/tsd-inventory-0.5.0-5.zip',
  String sha256 = 'abc',
}) => VersionManifest(
  versionCode: versionCode,
  versionName: '0.5.0',
  apkPath: apkPath,
  releaseNotes: 'Тест',
  sha256: sha256,
  required: required,
);

UpdateController _controller({
  required _MockRepo repo,
  required _MockInstaller installer,
  required Future<int> Function() currentVersionCodeProvider,
}) =>
    UpdateController(
      repo: repo,
      installer: installer,
      currentVersionCodeProvider: currentVersionCodeProvider,
    );

void main() {
  late _MockRepo repo;
  late _MockInstaller installer;

  setUpAll(() {
    registerFallbackValue(_ManifestFake());
    registerFallbackValue(File('x'));
  });

  setUp(() {
    repo = _MockRepo();
    installer = _MockInstaller();
  });

  group('checkAndPrompt', () {
    test('манифест новее текущей → UpdateAvailable', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final controller = _controller(
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
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 2)));
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('манифест старее текущей → UpdateIdle', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 1)));
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('сетевая ошибка → тихо UpdateIdle (не мешает работе)', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final controller = _controller(
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
          () => repo.checkForUpdate(),
        ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
        final controller = _controller(
          repo: repo,
          installer: installer,
          currentVersionCodeProvider: () async => 2,
        );
        final f1 = controller.checkAndPrompt();
        final f2 = controller
            .checkAndPrompt(); // повтор, пока первая ещё в полёте
        await Future.wait([f1, f2]);

        verify(() => repo.checkForUpdate()).called(1);
        expect(controller.state, isA<UpdateAvailable>());
      },
    );

    test('повторный вызов при UpdateAvailable не сбрасывает диалог', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();
      expect(controller.state, isA<UpdateAvailable>());

      await controller.checkAndPrompt(); // не должен перезапросить/сбросить

      verify(() => repo.checkForUpdate()).called(1);
      expect(controller.state, isA<UpdateAvailable>());
    });
  });

  group('downloadAndInstall', () {
    test('успех → Downloading → Installing', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final apkFile = File('test_apk');
      when(
        () => repo.downloadApk(
          any(),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Success(apkFile));
      when(() => installer.installApk(any())).thenAnswer((_) async {});
      final controller = _controller(
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
        when(() => repo.checkForUpdate()).thenAnswer(
          (_) async => Success(_manifest(versionCode: 5, sha256: '')),
        );
        final controller = _controller(
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
            targetDir: any(named: 'targetDir'),
            onProgress: any(named: 'onProgress'),
          ),
        );
        verifyNever(() => installer.installApk(any()));
      },
    );

    test('SHA-256 несовпадение → UpdateError', () async {
      when(
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const Failure(IntegrityError()));
      final controller = _controller(
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
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const Failure(NetworkError()));
      final controller = _controller(
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
        () => repo.checkForUpdate(),
      ).thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(
        () => repo.downloadApk(
          any(),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Success(File('test_apk')));
      when(() => installer.installApk(any())).thenThrow(Exception('denied'));
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateError>());
    });

    test('плашка получает свежий apkPath перед скачиванием', () async {
      var manifestRequest = 0;
      when(() => repo.checkForUpdate()).thenAnswer((_) async {
        manifestRequest++;
        return Success(
          _manifest(
            versionCode: 5,
            apkPath: manifestRequest == 1
                ? 'releases/expired.zip'
                : 'releases/fresh.zip',
          ),
        );
      });
      final apkFile = File('test_apk');
      when(
        () => repo.downloadApk(
          any(),
          targetDir: any(named: 'targetDir'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => Success(apkFile));
      when(() => installer.installApk(any())).thenAnswer((_) async {});
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadLatestAndInstall();

      verify(() => repo.checkForUpdate()).called(2);
      // Проверяем, что скачивание пошло по свежему манифесту (fresh.zip).
      final captured =
          verify(
                () => repo.downloadApk(
                  captureAny(),
                  targetDir: any(named: 'targetDir'),
                  onProgress: any(named: 'onProgress'),
                ),
              ).captured
              .single as VersionManifest;
      expect(captured.apkPath, 'releases/fresh.zip');
      verify(() => installer.installApk(apkFile)).called(1);
    });
  });

  group('required', () {
    test(
      'required=false → манифест доступен, skip сбрасывает в idle',
      () async {
        when(() => repo.checkForUpdate()).thenAnswer(
          (_) async => Success(_manifest(versionCode: 5, required: false)),
        );
        final controller = _controller(
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
      when(() => repo.checkForUpdate()).thenAnswer(
        (_) async => Success(_manifest(versionCode: 5, required: true)),
      );
      final controller = _controller(
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      expect((controller.state as UpdateAvailable).manifest.required, isTrue);
    });
  });
}
