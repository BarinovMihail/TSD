import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

void main() {
  group('VersionManifest.fromJson', () {
    test('корректный JSON → все поля заполнены', () {
      final m = VersionManifest.fromJson({
        'versionName': '0.2.6',
        'versionCode': 8,
        'apkUrl': 'https://storage.example/file.apk?sig=abc',
        'urlExpiresInSec': 600,
        'sha256': 'abc123',
        'releaseNotes': 'Что-то новое',
        'required': true,
      });
      expect(m.versionCode, 8);
      expect(m.versionName, '0.2.6');
      expect(m.apkUrl, 'https://storage.example/file.apk?sig=abc');
      expect(m.urlExpiresInSec, 600);
      expect(m.sha256, 'abc123');
      expect(m.releaseNotes, 'Что-то новое');
      expect(m.required, isTrue);
    });

    test('versionCode как строка («8») → int 8', () {
      final m = VersionManifest.fromJson({'versionCode': '8'});
      expect(m.versionCode, 8);
    });

    test('versionCode как double (8.0) → int 8', () {
      final m = VersionManifest.fromJson({'versionCode': 8.0});
      expect(m.versionCode, 8);
    });

    test('отсутствует versionCode → 0 (не валит приложение)', () {
      final m = VersionManifest.fromJson({'versionName': '0.2.6'});
      expect(m.versionCode, 0);
    });

    test('невалидный versionCode («abc») → 0', () {
      final m = VersionManifest.fromJson({'versionCode': 'abc'});
      expect(m.versionCode, 0);
    });

    test('отсутствуют необязательные строковые поля → пустые строки', () {
      final m = VersionManifest.fromJson({'versionCode': 5});
      expect(m.versionName, '');
      expect(m.apkUrl, '');
      expect(m.releaseNotes, '');
      expect(m.sha256, '');
    });

    test('required отсутствует → false', () {
      final m = VersionManifest.fromJson({'versionCode': 5});
      expect(m.required, isFalse);
    });

    test('urlExpiresInSec отсутствует → 0', () {
      final m = VersionManifest.fromJson({'versionCode': 5});
      expect(m.urlExpiresInSec, 0);
    });

    test('urlExpiresInSec как строка («600») → 600', () {
      final m = VersionManifest.fromJson({'urlExpiresInSec': '600'});
      expect(m.urlExpiresInSec, 600);
    });

    test('required явно false → false', () {
      final m = VersionManifest.fromJson({'required': false});
      expect(m.required, isFalse);
    });
  });

  group('isValid', () {
    test('apkUrl + sha256 непусты → true', () {
      const m = VersionManifest(
        versionCode: 8,
        versionName: '',
        apkUrl: 'https://x',
        releaseNotes: '',
        sha256: 'abc',
        urlExpiresInSec: 0,
        required: false,
      );
      expect(m.isValid, isTrue);
    });

    test('пустой apkUrl → false', () {
      const m = VersionManifest(
        versionCode: 8,
        versionName: '',
        apkUrl: '',
        releaseNotes: '',
        sha256: 'abc',
        urlExpiresInSec: 0,
        required: false,
      );
      expect(m.isValid, isFalse);
    });

    test('пустой sha256 → false (хеш обязателен)', () {
      const m = VersionManifest(
        versionCode: 8,
        versionName: '',
        apkUrl: 'https://x',
        releaseNotes: '',
        sha256: '',
        urlExpiresInSec: 0,
        required: false,
      );
      expect(m.isValid, isFalse);
    });
  });

  group('isNewerThan', () {
    const m = VersionManifest(
      versionCode: 5,
      versionName: '',
      apkUrl: 'https://x',
      releaseNotes: '',
      sha256: 'abc',
      urlExpiresInSec: 0,
      required: false,
    );

    test('манифест новее → true', () {
      expect(m.isNewerThan(2), isTrue);
    });

    test('манифест равен текущей → false (строгое сравнение)', () {
      expect(m.isNewerThan(5), isFalse);
    });

    test('манифест старее текущей → false', () {
      expect(
        const VersionManifest(
          versionCode: 1,
          versionName: '',
          apkUrl: 'https://x',
          releaseNotes: '',
          sha256: 'abc',
          urlExpiresInSec: 0,
          required: false,
        ).isNewerThan(5),
        isFalse,
      );
    });
  });
}
