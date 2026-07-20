# Инвентаризация ОС — ТСД M3 SL20

Flutter-приложение для терминала сбора данных **M3 SL20** (Android 11, API 30).
Инвентаризация основных средств через HTTP-сервисы 1С (ERP) с Basic Auth.

## Возможности

- Авторизация учётной записью 1С (Basic Auth).
- Список документов инвентаризации по ФИО пользователя.
- Табличная часть документа: поштучное сканирование штрихкодов, отметка строк
  (+1), зелёная подсветка, звук/вибро-отклик.
- Офлайн: кэш документа и прогресса сканирования (SQLite/drift) — данные не
  теряются при разряде/перезагрузке.
- Запись результатов в 1С.

## Требования

- Flutter 3.44+ / Dart 3.12+
- Android SDK с minSdk 30
- Доступный HTTP-сервис 1С в локальной сети

## Сборка

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # drift codegen
flutter build apk --release
```

## Настройка адреса сервера 1С

Базовый URL задаётся в `lib/core/config/app_config.dart` (поле `baseUrl`).
По умолчанию приложение подключается к **удалённой базе ERP** на сервере
`db-srv14` (сервис опубликован как `erp`).

```dart
class AppConfig {
  const AppConfig({
    this.baseUrl = remoteUrl,   // = http://db-srv14/erp/ — db-srv14
    ...
  });

  static const remoteUrl         = 'http://db-srv14/erp/';        // основной (hostname)
  static const remoteUrlFallback = 'http://192.168.1.212/erp/';   // резервный (IP)
  static const remoteHosts = [remoteUrl, remoteUrlFallback];      // для failover
  static const localUrl    = 'http://192.168.1.51/ERP_Local/';    // fallback-база
}
```

- **ERP основной:** `http://db-srv14/erp/` (hostname сервера).
- **ERP резервный:** `http://192.168.1.212/erp/` (IP того же сервера).
- **ERP_Local (fallback-база):** `http://192.168.1.51/ERP_Local/`.
- **Эмулятор:** заменить хост на `10.0.2.2` (→ localhost хоста).
- **Реальный ТСД:** адрес сервера 1С в локальной сети.
- HTTP (cleartext) разрешён через `android:usesCleartextTraffic` +
  `network_security_config.xml`.

### Failover по адресам ERP

Запросы к ERP идут по списку `remoteHosts` (основной `db-srv14` + резервный
`192.168.1.212`). При сетевой ошибке или тайм-ауте на текущем адресе клиент
автоматически переключается на следующий и повторяет запрос. Рабочий адрес
запоминается и переиспользуется, чтобы не ждать тайм-аут на мёртвом хосте
каждый раз.

**Важно:** переключение происходит только при отсутствии связи
(connection timeout / connection error). При любом HTTP-ответе сервера
(401/403/404/5xx) адрес НЕ меняется — это реальная проблема учётной записи или
публикации сервиса, маскировать её переключением адреса нельзя.

### Fallback на локальную базу

При логине приложение сначала стучится к **ERP**. Если удалённая база недоступна
(нет связи), оператору предлагается диалог: подключиться к локальной базе
**ERP_Local** или остаться на ERP и повторить. Выбор действует до конца сессии —
при выходе снова по умолчанию ERP. Переключение меняет URL во всём приложении
автоматически (через Riverpod `appConfigProvider`).

## Режим сканера

По умолчанию **keyboard wedge** (сканер эмулирует ввод в фокусное поле + Enter) —
работает на M3 SL20 без SDK. Переключается в `lib/core/config/app_config.dart`
(`scannerMode`):

- `keyboardWedge` — по умолчанию (без SDK).
- `broadcastIntent` — требует M3 Mobile SDK (заглушка `broadcast_intent_scanner.dart`, TODO).
- `camera` — резервный камерный сканер (`mobile_scanner`).

## Тестовые учётные данные 1С

- Логин: `testInv`
- Пароль: `Test12345`
- Базовый путь сервисов: `/hs/inventory/...`

## Контроль версий (автообновление)

После успешного входа в 1С приложение проверяет наличие новой версии. Если есть
обновление — диалог («Обновить», и «Пропустить», только если обновление
необязательное). При обновлении: скачивание APK → проверка SHA-256 → системный
установщик Android.

### Архитектура цепочки

```
приложение → HTTP-сервис 1С (/hs/inventory/update, Basic Auth)
           → Yandex API Gateway → Cloud Function → приватный Object Storage
```

Приложение обращается **только** к 1С, под существующей Basic-аутентификацией
учётки пользователя (переиспользуется тот же `DioClient`, что и для остальных
запросов: таймауты, failover по адресам ERP). Прямого обращения к API Gateway
или Object Storage из приложения нет — 1С сам ходит в Cloud Function (с
`X-Update-Token`, который хранится только на стороне 1С/Lockbox, не в приложении).

В бакете хранится `apkKey` (путь до APK), а мобильному приложению 1С/Cloud Function
возвращает уже **подписанную временную ссылку** `apkUrl`. Поэтому APK скачивается
по `apkUrl` отдельным чистым `Dio` **без** Basic Auth, cookies и `X-Update-Token` —
ссылка самодостаточна и действует `urlExpiresInSec` секунд.

### Когда запускается проверка

Проверка идёт **только после успешной авторизации** в 1С (на экране списка
документов). До авторизации endpoint `/hs/inventory/update` недоступен —
он защищён Basic-аутентификацией сессии. Ошибка проверки не мешает работе
пользователя (тихо глушится), кроме случая обязательного обновления `required=true`.

### Контракт ответа 1С

```json
{
  "versionName": "0.2.6",
  "versionCode": 8,
  "apkUrl": "https://storage.yandexcloud.net/...?X-Amz-Signature=...",
  "urlExpiresInSec": 600,
  "sha256": "<sha256 APK в нижнем регистре>",
  "releaseNotes": "Описание изменений",
  "required": false
}
```

Парсинг безопасный: некорректный `versionCode` → 0, отсутствующие строки → `""`,
`required` по умолчанию `false`, `urlExpiresInSec` → 0. Битый JSON не роняет
приложение. Сравнение версий — строго по целочисленному `versionCode`
(монотонно растёт, надёжнее парсинга X.Y.Z).

### Проверка целостности (SHA-256)

После скачивания APK приложение считает SHA-256 файла и сравнивает с `sha256` из
манифеста без учёта регистра. При несовпадении APK **удаляется**, установка не
запускается, показывается ошибка целостности. Пустой `sha256` считается
некорректным манифестом — установка невозможна.

### Обязательное обновление (`required`)

- `required=false` — пользователь может закрыть диалог и продолжить работу.
- `required=true` — диалог нельзя закрыть свайпом/вне окна, нет кнопки
  «Пропустить»; обновление обязательно. Чтобы избежать бесконечного цикла
  диалогов, «Повторить» при ошибке запрашивает свежий манифест только по
  явному нажатию.

### Публикация новой версии

1. Собрать release-APK (тем же ключом, что установлен): `flutter build apk --release`.
2. Посчитать SHA-256 APK в нижнем регистре:
   `certutil -hashfile build/app/outputs/flutter-apk/app-release.apk SHA256`
   (Windows) или `shasum -a 256 ...` (Unix).
3. Залить APK в бакет `tsd-inventory-updates-b1g3poudt` по пути
   `releases/tsd-inventory-<version>-<code>.apk` (см. `cloud/update_endpoint/README.md`).
4. Обновить `manifest.json` в корне бакета: поднять `versionName`/`versionCode`,
   вписать `apkKey`, `sha256` и `required`. Шаблон — `dist/manifest.json` в репо.
5. Залить APK **раньше** `manifest.json`: иначе клиенты увидят манифест, ссылающийся
   на ещё не залитый APK.

> ⚠️ В бакете хранится `apkKey` (ключ объекта), приложению же отдаётся подписанная
> `apkUrl`. Проверять end-to-end нужно именно после заливки обоих файлов и
> реальной установки на устройство — подписанная ссылка живёт `urlExpiresInSec` (600с).

Требования Android (уже настроены):
- `REQUEST_INSTALL_PACKAGES` — запуск системного установщика.
- `FileProvider` (`res/xml/file_paths.xml`) — безопасная передача APK установщику.

> **Подпись release-сборки.** APK, распространяемый через автообновление, должен
> быть подписан **тем же ключом**, что и установленное приложение, иначе Android
> отклонит обновление. Release-keystore подключается через `android/key.properties`
> (файл **не коммитится**, см. `android/.gitignore`).
>
> **Создание keystore (один раз):**
> ```bash
> keytool -genkey -v -keystore android/app/release.keystore.jks \
>   -alias tsd -keyalg RSA -keysize 2048 -validity 10000 \
>   -storepass <пароль_хранилища> -keypass <пароль_ключа> \
>   -dname "CN=Inventory TSD, O=TSD, C=RU"
> ```
>
> **Файл `android/key.properties`:**
> ```properties
> storePassword=<пароль_хранилища>
> keyPassword=<пароль_ключа>
> keyAlias=tsd
> storeFile=release.keystore.jks
> ```
> `storeFile` указан относительно `android/app/`. При отсутствии `key.properties`
> release-сборка подписывается debug-ключом (только для локальной разработки —
> автообновление между debug-сборками работает).
>
> ⚠️ **Сделай резервную копию keystore** и паролей. Утеря ключа означает, что
> обновить уже установленное приложение будет невозможно — только снос и установка
> заново под другим ключом (данные drift-БД при этом сохранятся, т.к. путь не
> зависит от подписи, но пользователю придётся переустанавливать APK вручную).

## Тесты

```bash
flutter test
```

Покрытие unit-тестами: парсеры `/fio/` и `/code/`, `BarcodeMatcher`,
`ScanController`, `ApiError`, `Result`, модуль автообновления
(`VersionManifest`, `UpdateRepository`, `UpdateController`).

## Архитектура

Feature-first слоистая: `presentation → application → domain → data`.
State — Riverpod; навигация — go_router; сеть — dio; БД — drift.

```
lib/
├── core/          # инфраструктура: network (dio+BasicAuth), storage (drift), scanner, feedback, update (контроль версий)
├── features/
│   ├── auth/      # экран 1: авторизация
│   ├── docs/      # экран 2: список документов (+ проверка обновлений после входа)
│   └── inventory/ # экран 3: табличная часть + сканирование
├── l10n/          # все русские строки
└── theme/         # контрастная тема
```

Дизайн: `../docs/superpowers/specs/2026-06-29-inventory-tsd-app-design.md`.
План: `../docs/superpowers/plans/2026-06-29-inventory-tsd-app.md`.

## Открытые точки интеграции с 1С (TODO)

- **Запись результатов:** `POST /hs/inventory/code/{Код}` (предполагаемый).
  Тело/метод уточнить у 1С — см. `InventoryRepository.postDocResult`.
- **ФИО пользователя:** сейчас `логин = ФИО`. Заглушка `getCurrentUserFio()`
  под будущий `/hs/inventory/me`.
- **Сопоставление штрихкода:** ключ — `НоменклатураКод` (поле ответа `/code/`).
