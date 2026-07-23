## Цель
Перевести автообновление с Yandex Cloud (Object Storage + API Gateway + Cloud Function + эндпоинт 1С) на **Яндекс Диск** через публичный REST API (без токена в приложении). APK хранится zip-архивом в `releases/`, после скачивания распаковывается. Проверка по-прежнему запускается после входа в 1С (на экране документов).

## Одноразовое действие (ваше, вручную)
Ваша текущая ссылка `disk.yandex.ru/client/disk/...` — **приватная** (хозяина), API по ней без авторизации не ответит. Нужно:
1. В Диске открыть папку `APK NO DELETE/ТСД` → «Поделиться» → «доступ по ссылке» (публичная).
2. Прислать публичную ссылку `disk.yandex.ru/d/XXXX` — подставлю в конфиг.

APK инвентаризационного приложения не секрет, публикация безопасна.

## Новая цепочка
```
приложение → Yandex Disk REST API (публичные эндпоинты, без токена)
   GET .../public/resources/download?public_key=...&path=manifest.json → временный href → качаем manifest.json
   GET .../public/resources/download?public_key=...&path=releases/x.zip → временный href → качаем zip → распаковываем → .apk → SHA-256 → установщик
```

## Изменения в коде

### 1. `pubspec.yaml`
Добавить `archive: ^4.0.2` (распаковка zip → .apk, чистый Dart).

### 2. НОВЫЙ `lib/core/update/data/yandex_disk_update_config.dart`
Конфиг источника на Диске: `publicKey`, `manifestPath` (`manifest.json`), `apiBase`. Константа `kYandexDiskUpdateConfig` со ссылкой-заглушкой `<ВСТАВИТЬ d/XXXX>`.

### 3. `lib/core/update/domain/version_manifest.dart`
- `apkUrl` → **`apkPath`** (путь к zip внутри публичной папки).
- **Удалить** `urlExpiresInSec` (подписанных ссылок больше нет — Диск отдаёт свежий href при каждом скачивании).
- `isValid` → проверка `apkPath` + `sha256`.
- Обновить контракт JSON в doc-комментарии под Диск.

### 4. `lib/core/update/data/update_repository.dart` (переписать)
Больше без авторизованного `DioClient` 1С — один чистый `Dio` + `YandexDiskUpdateConfig`:
- `checkForUpdate()` (без аргумента-пути): `GET .../public/resources/download` → временный href manifest.json → качаем → парсим в `VersionManifest` (с `apkPath`).
- `downloadApk(VersionManifest manifest, ...)`: свежий href для `manifest.apkPath` → качаем zip → **распаковываем** (`archive`) → извлекаем `.apk` → сверяем SHA-256 извлечённого APK с `manifest.sha256` → несовпадение = удалить файлы + `IntegrityError`.
- Ошибки сети/HTTP → `Result`/`Failure` как раньше.

### 5. `lib/core/update/application/update_controller.dart`
- `checkAndPrompt()`/`downloadLatestAndInstall()`: `_repo.checkForUpdate()` **без** `'hs/inventory/update'`.
- `downloadAndInstall()`: `_repo.downloadApk(manifest, ...)`.
- `updateControllerProvider`: убрать зависимость от сессии 1С и `DioClient`; репозиторий от `kYandexDiskUpdateConfig`. `StateError` про сессию убрать (защиту «только после входа» обеспечивает экран документов).

### 6. `lib/core/config/app_config.dart`
Поправить doc-комментарий `inventoryPath` (больше не упоминает эндпоинт обновления — только `updateFact`).

### 7. `tsd_inventory/scripts/publish-release.ps1` (переписать выгрузку)
Сборку/SHA-256/генерацию manifest оставить. Вместо yc/aws→S3:
- Упаковать APK в zip `releases/tsd-inventory-<ver>-<code>.zip`.
- `manifest.json`: `apkKey`→**`apkPath`** = `releases/...zip`; `sha256` = SHA-256 **APK**.
- Выгрузка в Диск через REST API при `$env:YANDEX_DISK_OAUTH_TOKEN`: `GET .../resources/upload?path=...&overwrite=true` (с `Authorization: OAuth`) → `PUT` байт по href; сначала zip, потом manifest.json. Без токена — `-BuildOnly`: готовые локальные файлы + инструкция по ручной заливке. Параметры `yc/aws/S3Endpoint/Bucket` убрать.

### 8. `tsd_inventory/dist/manifest.json`
`apkKey`→`apkPath`, значение — `releases/tsd-inventory-0.2.10-12.zip` (шаблон).

### 9. `cloud/update_endpoint/` — удалить целиком
`index.py`, `openapi.yaml`, `requirements.txt`, `test_index.py`, `README.md` (мёртвая инфраструктура). Декомисс самих ресурсов Yandex Cloud — отдельно, вне репо.

### 10. `README.md`
Переписать раздел «Контроль версий»: схема «приложение → публичный REST API Диска», контракт (`apkPath`), публикация (zip + manifest.json); убрать упоминания 1С-эндпоинта/API Gateway/Cloud Function/`X-Update-Token`.

### 11. Тесты (под новый контракт)
- `version_manifest_test.dart`: `apkUrl`→`apkPath`, убрать `urlExpiresInSec`.
- `update_repository_test.dart`: переписать — мокать два шага Диска (resolve href → контент); добавить тесты распаковки zip и сверки SHA-256 извлечённого APK.
- `update_controller_test.dart`: `checkForUpdate()` без аргумента, `downloadApk(manifest)`.
- `update_banner_test.dart`: `apkUrl`→`apkPath`, убрать `urlExpiresInSec`.

## Без изменений
- Вся UI-логика (`update_dialog.dart`, `update_banner.dart`, экран документов): состояния, обязательное обновление, плашка.
- `apk_installer.dart` (нативный установщик) — передаём готовый `.apk`.
- Проверка SHA-256, сравнение по `versionCode`, запуск только после входа в 1С.
- Подпись release-APK тем же ключом.

## Проверка
- `flutter test` — модуль update + существующие тесты проходят.
- Энд-ту-энд (после заполнения `yandexDiskPublicKey` и публикации папки): заливка zip+manifest, старая версия → предложение обновления → установка.

## Остаётся за вами
Перед запуском опубликовать папку `APK NO DELETE/ТСД` и прислать публичную ссылку `disk.yandex.ru/d/XXXX`.