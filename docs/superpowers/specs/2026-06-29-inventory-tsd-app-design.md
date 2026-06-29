# Дизайн: Flutter-приложение инвентаризации для ТСД M3 SL20

**Дата:** 2026-06-29
**Статус:** Утверждён (brainstorming завершён)
**Целевое устройство:** M3 SL20 (Android 11, API 30; экран 5.45" HD; встроенный 2D-имидж-сканер)
**Стек:** Flutter 3.44 / Dart 3.12, Android minSdk 30

---

## 1. Контекст и цели

Android-приложение для терминала сбора данных (ТСД) M3 SL20, выполняющее инвентаризацию основных средств через HTTP-сервисы 1С (ERP). Пользователь авторизуется учёткой 1С (Basic Auth), получает список назначенных ему документов инвентаризации, открывает табличную часть и поштучно сканирует штрихкоды, отмечая найденные строки. Результаты отправляются обратно в 1С.

Интерфейс — крупный, контрастный, «палочко-устойчивый»: управление преимущественно сканером и тапами по крупным элементам, без лишних жестов.

### Зафиксированные решения (из уточняющих вопросов)

| Параметр | Решение |
|---|---|
| Что закодировано в штрихкоде | **Код номенклатуры** (поле `НоменклатураКод` из ответа `/code/`) |
| Количество фактическое при скане | **+1 (инкремент)** при каждом сканировании |
| Аппаратный сканер | **Keyboard wedge** (M3 SDK недоступен); Broadcast-Intent и камера — переключаемые стратегии |
| Получение ФИО | **Логин = ФИО** |
| Persistence (прогресс сканирования) | **drift (SQLite)** |

---

## 2. Архитектура и слои

```
lib/
├── main.dart                      # ProviderScope, runApp
├── app.dart                       # MaterialApp, тема, go_router
├── core/                          # сквозная инфраструктура
│   ├── config/app_config.dart     # baseUrl, таймауты, режим сканера
│   ├── network/
│   │   ├── dio_client.dart        # dio + BasicAuth interceptor + retry + timeout
│   │   └── api_error.dart         # sealed ApiError (Auth/Network/Server/NotFound)
│   ├── result/result.dart         # sealed Result<T> = Success | Failure
│   ├── storage/
│   │   ├── secure_credentials_store.dart  # flutter_secure_storage
│   │   └── app_database.dart      # drift: scan_progress, cached_docs
│   ├── scanner/
│   │   ├── scanner_source.dart    # abstract interface ScannerSource
│   │   ├── keyboard_wedge_scanner.dart
│   │   ├── broadcast_intent_scanner.dart  # TODO M3 SDK
│   │   └── camera_scanner.dart    # mobile_scanner (резерв)
│   └── feedback/feedback_service.dart  # звук/вибро/цвет
├── features/
│   ├── auth/
│   │   ├── data/auth_repository.dart
│   │   ├── application/auth_controller.dart
│   │   └── presentation/login_screen.dart
│   ├── docs/
│   │   ├── data/docs_repository.dart
│   │   ├── domain/doc_list_item.dart
│   │   ├── domain/doc_list_parser.dart   # обход "#value"
│   │   └── presentation/docs_list_screen.dart
│   └── inventory/
│       ├── data/inventory_repository.dart
│       ├── domain/doc_table_row.dart
│       ├── domain/doc_table_parser.dart
│       ├── domain/barcode_matcher.dart
│       ├── application/scan_controller.dart
│       └── presentation/inventory_screen.dart
├── l10n/app_strings.dart          # все тексты на русском
└── theme/app_theme.dart           # крупный/контрастный
```

**Правило зависимостей:** presentation → application → domain → data. Слой **domain** не зависит от dio/drift/Flutter — отсюда лёгкие unit-тесты парсеров и `BarcodeMatcher`.

**State management:** Riverpod. `AsyncValue` (loading/data/error в одной сущности) — для экранов «список» и «табличная часть».

**Навигация:** `go_router`, маршруты `/login`, `/docs`, `/docs/:code`. `redirect` на `/login` при отсутствии сессии.

---

## 3. API 1С и сетевой слой

Базовый URL конфигурируется (`AppConfig.baseUrl`): `http://10.0.2.2/ERP_Local` для эмулятора, `http://<IP-сервера>/ERP_Local` для ТСД в локальной сети. Авторизация — HTTP Basic Auth на каждый запрос через перехватчик dio.

| Метод | URL | Назначение | Статус |
|---|---|---|---|
| GET | `/hs/inventory/fio/{ФИО}` | Список документов по ФИО (URL-encoded) | реализуется |
| GET | `/hs/inventory/code/{Код}` | Табличная часть документа | реализуется |
| POST | `/hs/inventory/code/{Код}` | Запись фактических количеств (предполагаемый) | **заглушка, TODO(1С)** |
| GET | `/hs/inventory/me` | ФИО аутентифицированного пользователя (предполагаемый) | **заглушка, TODO(1С)**, не используется (ФИО=логин) |

**`dio_client.dart`:** `connectTimeout` 10с, `receiveTimeout` 30с, `RetryInterceptor` (2 попытки, backoff 1с/3с), `BasicAuthInterceptor` (заголовок `Authorization: Basic base64(login:password)`).

**`ApiError` (sealed):** `AuthError` (401), `NetworkError` (socket/timeout), `ServerError` (5xx), `NotFoundError` (404). Фабрика `ApiError.fromDio(DioException)`.

**`Result<T>` (sealed):** `Success<T>(value)` / `Failure<T>(error: ApiError)`. Репозитории возвращают `Result<T>`; контроллеры разворачивают в `AsyncValue` для UI.

**Проверка учётных данных при логине:** лёгкий GET-зонд под Basic Auth; 200/204 → успех, 401 → `AuthError`.

---

## 4. Модели данных и парсеры

### DocListItem (из `/fio/`)

```dart
class DocListItem {
  final String ref;                   // GUID
  final String number;                // "АЕ-00000002"
  final DateTime date;
  final bool posted;
  final String? organizationGuid;     // GUID; человекочитаемого в /fio/ нет
  final String? departmentGuid;
  final String? responsibleGuid;
  // const-конструктор, == / hashCode по ref
}
```

### DocTableRow (из `/code/`)

```dart
class DocTableRow {
  final int lineNumber;               // ключ "1","2" → int
  final String inventoryNumber;       // "44182" или ""
  final String nomenclature;          // человекочитаемый текст
  final String nomenclatureCode;      // НоменклатураКод — КЛЮЧ матчера
  final String characteristic;
  final String series;
  final String seriesStatus;          // "0"..
  final String fio;                   // ФизическоеЛицо (текст)
  final int qtyAccounting;            // int.tryParse
  final int qtyActual;                // int.tryParse
  final String action;                // Действие (расхождения)

  bool get isFound => qtyActual > 0;
  bool get hasDiscrepancy => qtyActual != qtyAccounting;
}
```

### Парсеры (чистые функции, без зависимости от Flutter/dio)

**`parseDocList(Object? json) → List<DocListItem>`** (обход `#value`):
-顶层 массив; каждый элемент → `Map['#value']` (если `#value` отсутствует — сам элемент как Map).
- Пустые GUID (`""`) → `null`.
- Невалидная дата → пропустить элемент с логированием, не валить весь список.

**`parseDocTable(Object? json) → List<DocTableRow>`**:
- Ключи-номера строк (`"1"`, `"2"`) → `int.tryParse` (невалид → 0).
- Количества-строки → `int.tryParse` (невалид → 0).
- Пустые поля → `''`.
- Сортировка результата по `lineNumber`.

### Формат тела POST (предполагаемый, TODO(1С))

```json
{
  "Lines": {
    "1": { "КоличествоФактическое": 1, "Действие": "" },
    "2": { "КоличествоФактическое": 0, "Действие": "" }
  }
}
```

---

## 5. Логика сканирования и сопоставления

### 5.1 Абстракция сканера

```dart
abstract interface class ScannerSource {
  Stream<String> get codes;
  Future<void> start();
  Future<void> dispose();
}
```

Три реализации, выбор через конфигурацию `scannerMode`:

| Реализация | Когда | Механика |
|---|---|---|
| **`KeyboardWedgeScanner`** (по умолчанию) | M3 SL20 без SDK (текущий случай) | Скрытый всегда-в-фокусе `TextField` + `onSubmitted`; буфер быстрого ввода (таймаут ~80мс) → одна строка в поток `codes`. |
| `BroadcastIntentScanner` | есть M3 SDK (будущее) | Android `EventChannel`/`BroadcastReceiver`. `TODO: requires M3 Mobile SDK`. |
| `CameraScanner` | резерв / ручной режим | `mobile_scanner`. Кнопка «Сканировать камерой». |

**«Палочко-устойчивость» wedge-поля:** `FocusNode` + `autofocus: true` + `requestFocus()` после каждого `onSubmitted` → случайный тап по экрану не теряет сканер.

### 5.2 Сопоставление штрихкода — `BarcodeMatcher`

**Ключевое правило:** штрихкод = **код номенклатуры** (`НоменклатураКод`).

```dart
class MatchResult {
  final List<DocTableRow> exact;
  const MatchResult(this.exact);
  bool get isUnique => exact.length == 1;
  bool get isNone => exact.isEmpty;
  bool get isAmbiguous => exact.length > 1;
}

class BarcodeMatcher {
  MatchResult match(String code, List<DocTableRow> rows) {
    final norm = normalize(code);
    if (norm.isEmpty) return MatchResult(const []);
    // 1) Основной ключ: НоменклатураКод
    var hits = rows.where((r) => normalize(r.nomenclatureCode) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);
    // 2) Fallback ТОЛЬКО если НоменклатураКод пуст у всех строк
    final anyPrimary = rows.any((r) => r.nomenclatureCode.trim().isNotEmpty);
    if (!anyPrimary) {
      hits = rows.where((r) => normalize(r.inventoryNumber) == norm).toList();
      if (hits.isNotEmpty) return MatchResult(hits);
      hits = rows.where((r) => normalize(r.series) == norm).toList();
      if (hits.isNotEmpty) return MatchResult(hits);
      hits = rows.where((r) => normalize(r.nomenclature) == norm).toList();
      if (hits.isNotEmpty) return MatchResult(hits);
    }
    return MatchResult(const []);
  }
  String normalize(String s) => s.trim();  // case-sensitive по умолчанию
}
```

**Поведение по числу совпадений:**

| Совпадений | Действие |
|---|---|
| 1 | +1 к `qtyActual`, зелёная подсветка, feedback.success |
| >1 | диалог выбора строки (`AmbiguousDialog`) |
| 0 | алерт «Штрихкод не найден» + поле ручного ввода (`NotFoundDialog`) |

### 5.3 ScanController (оркестратор, Riverpod)

```dart
class ScanController {
  final InventoryRepository _repo;
  final BarcodeMatcher _matcher;
  final AppDatabase _db;
  final FeedbackService _feedback;
  final String docCode;
  List<DocTableRow> rows;

  int get scannedCount => rows.where((r) => r.isFound).length;
  int get total => rows.length;

  Future<ScanOutcome> onScanned(String code) async { ... }
  Future<void> hydrateFromDb() async { ... }
  Future<void> commit() async { ... }   // POST результатов
}

sealed class ScanOutcome { const ScanOutcome(); }
class Found extends ScanOutcome { final DocTableRow row; }
class NotFound extends ScanOutcome { final String code; }
class Ambiguous extends ScanOutcome { final List<DocTableRow> candidates; }
```

`onScanned`: матч → найдено ровно одно (`+1`, `feedback.success`, `db.upsertScanProgress`) / не найдено (`feedback.error`) / несколько (`feedback.attention`, кандидаты).

Инкремент `+1` при **каждом** сканировании (решение пользователя) — повторный скан той же строки снова добавляет +1.

### 5.4 Обратная связь — `FeedbackService`

```dart
void success()   => _beep(1500, vibrateMs: 30);   // высокий тон
void error()     => _beep(400,  vibrateMs: 200);  // низкий тон, длинная вибро
void attention() => _beep(900,  vibrateMs: 100);  // средний тон
```
Реализация: `audioplayers` / `HapticFeedback` / `SystemSound`. Опционально — цветовая вспышка экрана (зелёный/красный бордер на 300мс).

---

## 6. Экраны

### 6.1 Тема (общая)

`ColorScheme.highContrastLight` (тёмно-синий primary, зелёный secondary для «найдено», красный error). Шрифты: bodyLarge 20, titleLarge 24 w700, labelLarge 20. Кнопки: `minimumSize: Size(double.infinity, 64)`. Минимум 48dp tap-target. Только тапы + pull-to-refresh, без свайпов.

### 6.2 Экран 1 — Авторизация

Поля: логин, пароль (toggle показать/скрыть). Чекбоксы: «Запомнить логин» (всегда), «Запомнить пароль» (опционально, Keystore). Кнопка «Войти» (h≥64, disabled при пустых полях).

Поведение: валидация непустых полей → `AuthRepository.login` → `Result`. 401 → «Неверный логин или пароль» (красным под кнопкой). Сетевая ошибка → «Нет связи с сервером. Проверьте Wi-Fi». Успех → secure storage + `AuthSession(login, password)` → редирект `/docs`. **Логин = ФИО** — используется для запроса `/fio/`.

### 6.3 Экран 2 — Список документов

Шапка: ФИО пользователя (из логина) + кнопки меню/refresh. Список карточек: `Number`, `Date`, организация/подразделение (GUID; человекочитаемых в `/fio/` нет → `TODO`), `Posted`.

Состояния через `AsyncValue<List<DocListItem>>`:
- loading → индикатор/скелетон
- error → красная карточка «Ошибка загрузки» + «Повторить»
- empty → «Документов не найдено»
- data → список карточек
- pull-to-refresh

Тап по карточке → `/docs/${item.number}`.

### 6.4 Экран 3 — Табличная часть + сканирование

Шапка: код документа, дата, прогресс «Отсканировано X из Y» + прогресс-бар.

Фильтр/поиск: `lowercase contains` по `nomenclature` + `inventoryNumber`. Сортировка по умолчанию: сначала неотсканированные (`!isFound`), затем по `lineNumber`.

Карточка строки:
- `qtyActual > 0 && == qtyAccounting` → зелёный фон + ✓ «найдено»
- `qtyActual > 0 && != qtyAccounting` → зелёный + ⚠ «расхождение: факт N, учёт M»
- `qtyActual == 0` → нейтральный
- после неудачного скана → красная вспышка 300мс

Сканер: скрытый wedge-`TextField` (визуальный индикатор «готов к сканированию»), подписка на `scanController.onScanned`.

Диалоги: `AmbiguousDialog` (множественное совпадение → выбор), `NotFoundDialog` («Штрихкод XXX не найден» + поле ручного ввода), подтверждение «Завершить» → `postDocResult`.

Кнопки: «Камера» (резерв), «Завершить» (отправить). При ошибке сети при отправке: «Сохранено локально. Повторить отправку?» (прогресс остаётся в БД).

---

## 7. Persistence (drift)

### Таблицы

```dart
class ScanProgress extends Table {
  TextColumn get docCode => text()();
  IntColumn get lineNumber => integer()();
  TextColumn get nomenclatureCode => text().nullable()();
  IntColumn get qtyActual => integer().withDefault(const Constant(0))();
  TextColumn get action => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(Current.now)();
  @override Set<Column> get primaryKey => {docCode, lineNumber};
}

class CachedDoc extends Table {
  TextColumn get code => text()();
  TextColumn get json => text()();          // сырой JSON /code/
  DateTimeColumn get fetchedAt => dateTime()();
  @override Set<Column> get primaryKey => {code};
}
```

### Методы AppDatabase

```dart
Future<void> upsertScanProgress({docCode, lineNo, nomenclatureCode, qtyActual, action});
Future<Map<int, ScanProgressData>> getScanProgress(String docCode);
Future<void> clearScanProgress(String docCode);
Future<void> cacheDoc(String code, String json);
Future<CachedDocData?> getCachedDoc(String code);
```

### Стратегия кэш+сеть

```
Загрузка таблицы(code):
  try { network = repo.getTable(code)
        db.cacheDoc(code, rawJson)
        hydrateScanProgress(code)
        → rows }
  catch (network error) {
    cached = db.getCachedDoc(code)
    if cached != null { parse(cached.json) + hydrateScanProgress → rows }   // офлайн
    else → error «Нет сохранённой копии и нет связи»
  }

Отправка:
  try { repo.postDocResult(code, lines)
        db.clearScanProgress(code) }        // успех → чистим локальный прогресс
  catch (network) { «Сохранено локально. Повторить?» (прогресс остаётся) }
```

---

## 8. Нефункциональные требования

| Требование | Реализация |
|---|---|
| Нестабильная сеть: повтор | `RetryInterceptor` (2 попытки, backoff) |
| Кэширование документа | `CachedDoc` (drift) |
| Локальное сохранение прогресса | `ScanProgress` (drift) — восстановление при разряде/перезагрузке |
| Журналирование ошибок | `logging` package + типизированные `ApiError` |
| Понятные сообщения | `AppStrings` (русский) + `ApiError` → текст |
| Локализация в отдельном слое | `l10n/app_strings.dart` |
| HTTP cleartext | `usesCleartextTraffic` + `network_security_config.xml` |
| Крупный/контрастный UI | `appTheme()` |

---

## 9. Тесты

| Компонент | Что тестируем |
|---|---|
| `parseDocList` | обход `#value`; пустые GUID→null; невалидная дата→пропуск; `Posted`; отсутствие `#value` |
| `parseDocTable` | ключи-номера строк; количества-строки→int; сортировка; пустые поля→`''` |
| `BarcodeMatcher` | точное совпадение по `НоменклатураКод`; уникальное/множественное/не найдено; fallback (когда `НоменклатураКод` пуст у всех); fallback НЕ срабатывает, когда часть строк с кодом; normalize |
| `DocTableRow.isFound/hasDiscrepancy` | границы |
| `ScanController.onScanned` (mock) | found→+1+persist; notFound→error; ambiguous→candidates; повторный скан→ещё +1 |
| `ApiError.fromDio` | 401/socket/500/404 |
| Widget (smoke) | login: пустые поля → кнопка disabled; docs: loading/error/empty/data |

---

## 10. Ответы на открытые вопросы

| № | Вопрос | Решение |
|---|---|---|
| 1 | Сопоставление штрихкода | **Код номенклатуры** (`НоменклатураКод`); fallback на Инв.№/Серию/Номенклатуру только если `НоменклатураКод` пуст у всех строк |
| 2 | Запись в 1С | **POST `/hs/inventory/code/{Код}`** (предполагаемый), тело `{Lines:{lineNo:{КоличествоФактическое, Действие}}}`. `TODO(1С)` — уточнить с разработчиком 1С |
| 3 | ФИО пользователя | **Логин = ФИО**. `getCurrentUserFio()` — stub (`UnimplementedError`) на случай появления `/me` |
| 4 | Аппаратный сканер M3 | **Keyboard wedge** (нет SDK). Broadcast-Intent + камера как стратегии через `ScannerSource` |
| 5 | Кол-во фактическое | **+1 при каждом сканировании** (инкремент) |
| 6 | Расхождения | Сохраняем поле **`Действие`**; UI: «расхождение: факт N, учёт M». Конкретные значения `Действие` (Оприходование/Списание) — `TODO(1С)` |

---

## 11. Зависимости

```yaml
dependencies:
  flutter: { sdk: flutter }
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  dio: ^5.4.0
  retry: ^3.1.2                # или dio_interceptorretry
  drift: ^2.16.0
  sqlite3_flutter_libs: ^0.5.0
  flutter_secure_storage: ^9.0.0
  mobile_scanner: ^5.0.0
  audioplayers: ^6.0.0
  shared_preferences: ^2.2.0
  intl: ^0.19.0
  logging: ^1.2.0

dev_dependencies:
  flutter_test: { sdk: flutter }
  drift_dev: ^2.16.0
  build_runner: ^2.4.0
  mocktail: ^1.0.0
```

---

## 12. Android-конфигурация

**`AndroidManifest.xml`:** `INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE`, `CAMERA`; `usesCleartextTraffic="true"`, `networkSecurityConfig`.

**`res/xml/network_security_config.xml`** — белый список cleartext-доменов (10.0.2.2, локальная сеть 192.168.0.0/16, реальный IP сервера 1С).

**`app/build.gradle`:** `minSdk = 30`, `targetSdk = 34`.

---

## 13. Definition of Done

- [ ] Приложение собирается под Android (minSdk 30), запускается на эмуляторе и деплоится на M3 SL20.
- [ ] 3 экрана: авторизация, список документов, табличная часть + сканирование.
- [ ] API-слой: Basic Auth, оба GET-метода (`/fio/`, `/code/`); заглушки `postDocResult` и `getCurrentUserFio` с `TODO`.
- [ ] Сканер: keyboard wedge принимает код, отметка строк работает (+1, зелёная подсветка, feedback).
- [ ] Модели с парсерами + unit-тесты на парсинг и сопоставление — зелёные.
- [ ] Persistence: прогресс сохраняется и восстанавливается после перезапуска.
- [ ] README: сборка, настройка baseUrl, режим сканера, тестовые учётки `testInv/Test12345`.
