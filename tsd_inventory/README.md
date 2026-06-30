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

Базовый URL задаётся в `lib/core/config/app_config.dart` (поле `baseUrl`):

```dart
const AppConfig({
  this.baseUrl = 'http://10.0.2.2/ERP_Local',   // ← заменить на свой
  ...
});
```

- **Эмулятор:** `http://10.0.2.2/ERP_Local` (10.0.2.2 → localhost хоста).
- **Реальный ТСД:** IP сервера 1С в локальной сети, напр. `http://192.168.1.10/ERP_Local`.
- HTTP (cleartext) разрешён через `android:usesCleartextTraffic` +
  `network_security_config.xml`.

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

## Тесты

```bash
flutter test
```

Покрытие unit-тестами: парсеры `/fio/` и `/code/`, `BarcodeMatcher`,
`ScanController`, `ApiError`, `Result`.

## Архитектура

Feature-first слоистая: `presentation → application → domain → data`.
State — Riverpod; навигация — go_router; сеть — dio; БД — drift.

```
lib/
├── core/          # инфраструктура: network (dio+BasicAuth), storage (drift), scanner, feedback
├── features/
│   ├── auth/      # экран 1: авторизация
│   ├── docs/      # экран 2: список документов
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
