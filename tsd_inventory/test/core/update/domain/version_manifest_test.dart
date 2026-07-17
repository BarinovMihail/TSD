import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/update/domain/version_manifest.dart';

void main() {
  group('VersionManifest.fromJson', () {
    test('корректный JSON → все поля заполнены', () {
      final m = VersionManifest.fromJson({
        'versionName': '0.2.0',
        'versionCode': 2,
        'apkFileId': 58930,
        'releaseNotes': 'Что-то новое',
      });
      expect(m.versionCode, 2);
      expect(m.versionName, '0.2.0');
      expect(m.apkFileId, 58930);
      expect(m.releaseNotes, 'Что-то новое');
    });

    test('versionCode как строка («2») → int 2', () {
      final m = VersionManifest.fromJson({'versionCode': '2'});
      expect(m.versionCode, 2);
    });

    test('versionCode как double (2.0) → int 2', () {
      final m = VersionManifest.fromJson({'versionCode': 2.0});
      expect(m.versionCode, 2);
    });

    test('отсутствует versionCode → 0 (не валит приложение)', () {
      final m = VersionManifest.fromJson({'versionName': '0.2.0'});
      expect(m.versionCode, 0);
    });

    test('невалидный versionCode («abc») → 0', () {
      final m = VersionManifest.fromJson({'versionCode': 'abc'});
      expect(m.versionCode, 0);
    });

    test('отсутствуют строковые поля → пустые строки', () {
      final m = VersionManifest.fromJson({'versionCode': 5});
      expect(m.versionName, '');
      expect(m.apkFileId, 0);
      expect(m.releaseNotes, '');
    });
  });

  group('isNewerThan', () {
    test('манифест новее → true', () {
      const m = VersionManifest(
          versionCode: 5, versionName: '', apkFileId: 0, releaseNotes: '');
      expect(m.isNewerThan(2), isTrue);
    });

    test('манифест равен текущей → false (строгое сравнение)', () {
      const m = VersionManifest(
          versionCode: 5, versionName: '', apkFileId: 0, releaseNotes: '');
      expect(m.isNewerThan(5), isFalse);
    });

    test('манифест старее текущей → false', () {
      const m = VersionManifest(
          versionCode: 1, versionName: '', apkFileId: 0, releaseNotes: '');
      expect(m.isNewerThan(5), isFalse);
    });
  });
}
