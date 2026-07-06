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

AppConfig _config({String manifestUrl = 'http://host/manifest.json'}) =>
    AppConfig(updateManifestUrl: manifestUrl);

VersionManifest _manifest({int versionCode = 5}) => VersionManifest(
      versionCode: versionCode,
      versionName: '0.5.0',
      apkUrl: 'http://host/app.apk',
      releaseNotes: 'Тест',
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
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateAvailable>());
      expect((controller.state as UpdateAvailable).manifest.versionCode, 5);
    });

    test('манифест равен текущей → UpdateIdle', () async {
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 2)));
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('манифест старее текущей → UpdateIdle', () async {
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 1)));
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('ошибка сети → тихо UpdateIdle (не мешает работе)', () async {
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => const Failure(NetworkError()));
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      expect(controller.state, isA<UpdateIdle>());
    });

    test('пустой URL манифеста → не дёргает сеть, UpdateIdle', () async {
      final controller = UpdateController(
        config: _config(manifestUrl: ''),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );

      await controller.checkAndPrompt();

      verifyNever(() => repo.checkForUpdate(any()));
      expect(controller.state, isA<UpdateIdle>());
    });
  });

  group('downloadAndInstall', () {
    test('успех → Downloading → Installing', () async {
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      final apkFile = File('test_apk');
      when(() => repo.downloadApk(any(),
              targetDir: any(named: 'targetDir'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => Success(apkFile));
      when(() => installer.installApk(any())).thenAnswer((_) async {});
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateInstalling>());
      verify(() => installer.installApk(apkFile)).called(1);
    });

    test('сбой скачивания → UpdateError', () async {
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(() => repo.downloadApk(any(),
              targetDir: any(named: 'targetDir'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => const Failure(NetworkError()));
      final controller = UpdateController(
        config: _config(),
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
      when(() => repo.checkForUpdate(any()))
          .thenAnswer((_) async => Success(_manifest(versionCode: 5)));
      when(() => repo.downloadApk(any(),
              targetDir: any(named: 'targetDir'),
              onProgress: any(named: 'onProgress')))
          .thenAnswer((_) async => Success(File('test_apk')));
      when(() => installer.installApk(any())).thenThrow(Exception('denied'));
      final controller = UpdateController(
        config: _config(),
        repo: repo,
        installer: installer,
        currentVersionCodeProvider: () async => 2,
      );
      await controller.checkAndPrompt();

      await controller.downloadAndInstall();

      expect(controller.state, isA<UpdateError>());
    });
  });

  test('skip → UpdateIdle', () async {
    when(() => repo.checkForUpdate(any()))
        .thenAnswer((_) async => Success(_manifest(versionCode: 5)));
    final controller = UpdateController(
      config: _config(),
      repo: repo,
      installer: installer,
      currentVersionCodeProvider: () async => 2,
    );
    await controller.checkAndPrompt();
    expect(controller.state, isA<UpdateAvailable>());

    controller.skip();

    expect(controller.state, isA<UpdateIdle>());
  });
}
