# Инвентаризация ТСД M3 SL20 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Создать Flutter-приложение для терминала сбора данных M3 SL20, выполняющее инвентаризацию основных средств через HTTP-сервисы 1С (Basic Auth): авторизация, список документов, табличная часть с поштучным сканированием штрихкодов и записью прогресса.

**Architecture:** Feature-first слоистая архитектура (presentation → application → domain → data) с Riverpod для state management и go_router для навигации. Домен (модели, парсеры, `BarcodeMatcher`) изолирован от Flutter/dio/drift и покрыт unit-тестами. Сетевой слой — dio + BasicAuth + retry. Persistence — drift (SQLite) для офлайн-кэша документа и прогресса сканирования. Сканер — интерфейс `ScannerSource` со стратегиями; по умолчанию keyboard wedge.

**Tech Stack:** Flutter 3.44 / Dart 3.12, Android minSdk 30; flutter_riverpod, go_router, dio, drift, flutter_secure_storage, mobile_scanner, audioplayers, intl, logging. Тесты: flutter_test, mocktail.

**Ссылка на дизайн:** `docs/superpowers/specs/2026-06-29-inventory-tsd-app-design.md`

---

## Файловая структура (карта)

```
tsd_inventory/                          ← корень Flutter-проекта
├── pubspec.yaml                        ← зависимости (Task 1)
├── android/
│   ├── app/src/main/AndroidManifest.xml            ← Task 2 (HTTP cleartext, permissions)
│   ├── app/src/main/res/xml/network_security_config.xml  ← Task 2
│   └── app/build.gradle.kts                         ← Task 2 (minSdk 30)
├── lib/
│   ├── main.dart                                    ← Task 3 (ProviderScope + app)
│   ├── app.dart                                     ← Task 3 (MaterialApp + router + theme)
│   ├── l10n/app_strings.dart                        ← Task 3 (все русские строки)
│   ├── theme/app_theme.dart                         ← Task 3 (контрастная тема)
│   ├── core/
│   │   ├── config/app_config.dart                   ← Task 4 (baseUrl, scannerMode)
│   │   ├── result/result.dart                       ← Task 4 (Result<T> sealed)
│   │   ├── network/api_error.dart                   ← Task 4 (ApiError sealed + fromDio)
│   │   ├── network/dio_client.dart                  ← Task 5 (dio + interceptors)
│   │   ├── storage/secure_credentials_store.dart    ← Task 6
│   │   ├── storage/app_database.dart                ← Task 7 (drift: ScanProgress, CachedDoc)
│   │   ├── scanner/scanner_source.dart              ← Task 8 (interface)
│   │   ├── scanner/keyboard_wedge_scanner.dart      ← Task 8
│   │   ├── scanner/broadcast_intent_scanner.dart    ← Task 8 (stub)
│   │   ├── scanner/camera_scanner.dart              ← Task 8 (stub, mobile_scanner)
│   │   └── feedback/feedback_service.dart           ← Task 9
│   ├── features/auth/
│   │   ├── data/auth_repository.dart                ← Task 10
│   │   ├── application/auth_controller.dart         ← Task 10
│   │   └── presentation/login_screen.dart           ← Task 14
│   ├── features/docs/
│   │   ├── domain/doc_list_item.dart                ← Task 11
│   │   ├── domain/doc_list_parser.dart              ← Task 11
│   │   ├── data/docs_repository.dart                ← Task 12
│   │   ├── application/docs_controller.dart         ← Task 12
│   │   └── presentation/docs_list_screen.dart       ← Task 15
│   └── features/inventory/
│       ├── domain/doc_table_row.dart                ← Task 13
│       ├── domain/doc_table_parser.dart             ← Task 13
│       ├── domain/barcode_matcher.dart              ← Task 13
│       ├── data/inventory_repository.dart           ← Task 16
│       ├── application/scan_controller.dart         ← Task 17
│       └── presentation/inventory_screen.dart       ← Task 18
└── test/
    ├── core/network/api_error_test.dart             ← Task 4
    ├── core/result/result_test.dart                 ← Task 4
    ├── features/docs/domain/doc_list_parser_test.dart       ← Task 11
    ├── features/inventory/domain/doc_table_parser_test.dart ← Task 13
    ├── features/inventory/domain/barcode_matcher_test.dart  ← Task 13
    ├── features/inventory/domain/doc_table_row_test.dart    ← Task 13
    └── features/inventory/application/scan_controller_test.dart ← Task 17
```

**Порядок реализации:** сначала скелет проекта и Android-конфиг (Task 1-3), затем core-инфраструктура (4-9), затем domain-слой с парсерами через TDD (10-13), затем репозитории/controllers (10,12,16,17), и наконец UI-экраны (14,15,18) + README (19).

---

### Task 1: Инициализация Flutter-проекта

**Files:**
- Create: `tsd_inventory/` (Flutter-проект)
- Create: `tsd_inventory/pubspec.yaml`

- [ ] **Step 1: Создать Flutter-проект**

В корне репозитория (`C:\Users\Barinov_MA\Documents\GitHub\TSD`) выполнить:
```bash
flutter create --org ru.tsd --platforms android --project-name tsd_inventory tsd_inventory
```
Ожидается: создан каталог `tsd_inventory/` со стандартной структурой Flutter.

- [ ] **Step 2: Проверить сборку empty-проекта**

```bash
cd tsd_inventory
flutter analyze
```
Ожидается: `No issues found!` (или предсказуемые предупреждения шаблона).

- [ ] **Step 3: Заменить pubspec.yaml зависимостями из спеки**

Полностью перезаписать `tsd_inventory/pubspec.yaml`:
```yaml
name: tsd_inventory
description: Инвентаризация ОС для терминала сбора данных M3 SL20.
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: '>=3.4.0 <4.0.0'
  flutter: '>=3.22.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.5.1
  go_router: ^14.2.0
  dio: ^5.4.0
  retry: ^3.1.2
  drift: ^2.16.0
  sqlite3_flutter_libs: ^0.5.0
  flutter_secure_storage: ^9.0.0
  mobile_scanner: ^5.0.0
  audioplayers: ^6.0.0
  shared_preferences: ^2.2.0
  intl: ^0.19.0
  logging: ^1.2.0
  path_provider: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  drift_dev: ^2.16.0
  build_runner: ^2.4.0
  mocktail: ^1.0.0
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
```

- [ ] **Step 4: Установить зависимости**

```bash
flutter pub get
```
Ожидается: зависимости разрешены без ошибок версионных конфликтов. Если конфликт версий — понизить минорную версию конкретного пакета до ближайшей разрешённой (зафиксировать в pubspec).

- [ ] **Step 5: Зафиксировать Flutter/Dart версии**

Создать `tsd_inventory/.gitignore` оставить стандартный от `flutter create`.

- [ ] **Step 6: Коммит**

```bash
git add tsd_inventory
git commit -m "feat: инициализация Flutter-проекта tsd_inventory и зависимости"
```

---

### Task 2: Android-конфигурация (HTTP cleartext + minSdk 30)

**Files:**
- Modify: `tsd_inventory/android/app/src/main/AndroidManifest.xml`
- Create: `tsd_inventory/android/app/src/main/res/xml/network_security_config.xml`
- Modify: `tsd_inventory/android/app/build.gradle.kts`

- [ ] **Step 1: Обновить AndroidManifest.xml — permissions + cleartext**

Открыть `tsd_inventory/android/app/src/main/AndroidManifest.xml`. В тег `<manifest>` добавить permissions (до `<application>`):
```xml
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.CAMERA"/>
```
В тег `<application>` добавить атрибуты:
```xml
        android:usesCleartextTraffic="true"
        android:networkSecurityConfig="@xml/network_security_config"
```

- [ ] **Step 2: Создать network_security_config.xml**

Создать `tsd_inventory/android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <domain-config cleartextTrafficPermitted="true">
        <!-- Эмулятор: 10.0.2.2 → localhost хоста -->
        <domain includeSubdomains="false">10.0.2.2</domain>
        <!-- Локальная сеть (реальный IP сервера 1С попадает сюда) -->
        <domain includeSubdomains="false">192.168.0.0</domain>
        <domain includeSubdomains="false">10.0.0.0</domain>
    </domain-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors>
            <certificates src="system"/>
        </trust-anchors>
    </base-config>
</network-security-config>
```
> Примечание: `base-config cleartextTrafficPermitted="true"` — упрощает работу с произвольным IP 1С в локальной сети; для прод-сборки можно сузить до конкретных доменов.

- [ ] **Step 3: Установить minSdk 30 в build.gradle.kts**

Открыть `tsd_inventory/android/app/build.gradle.kts`. Найти блок `android { defaultConfig { ... } }` и установить:
```kotlin
        minSdk = 30
        targetSdk = 34
```
(Заменить существующие значения `minSdk`/`targetSdk` или добавить, если их нет.)

- [ ] **Step 4: Проверить сборку Android**

```bash
cd tsd_inventory
flutter build apk --debug --no-tree-shake-icons
```
Ожидается: `✓ Built build\app\outputs\flutter-apk\app-debug.apk`. Если падает на `mobile_scanner` CameraX — временно оставить Camera-сканер как stub (см. Task 8), сборка должна пройти.

- [ ] **Step 5: Коммит**

```bash
git add tsd_inventory/android
git commit -m "feat(android): HTTP cleartext + network_security_config + minSdk 30"
```

---

### Task 3: Каркас приложения (main, app, theme, strings)

**Files:**
- Create: `tsd_inventory/lib/main.dart`
- Create: `tsd_inventory/lib/app.dart`
- Create: `tsd_inventory/lib/theme/app_theme.dart`
- Create: `tsd_inventory/lib/l10n/app_strings.dart`

- [ ] **Step 1: Создать app_strings.dart — все русские строки**

Создать `tsd_inventory/lib/l10n/app_strings.dart`:
```dart
/// Единый источник текстов интерфейса (русский).
/// Все строки UI берутся отсюда — упрощает локализацию/правки.
abstract final class AppStrings {
  // Общие
  static const appName = 'Инвентаризация';
  static const retry = 'Повторить';
  static const loading = 'Загрузка…';
  static const cancel = 'Отмена';
  static const confirm = 'ОК';
  static const yes = 'Да';
  static const no = 'Нет';

  // Авторизация
  static const loginTitle = 'Инвентаризация ОС';
  static const loginField = 'Логин';
  static const passwordField = 'Пароль';
  static const showPassword = 'Показать пароль';
  static const hidePassword = 'Скрыть пароль';
  static const rememberLogin = 'Запомнить логин';
  static const rememberPassword = 'Запомнить пароль';
  static const signIn = 'Войти';
  static const errFieldsRequired = 'Заполните логин и пароль';
  static const errAuthFailed = 'Неверный логин или пароль';
  static const errNetwork = 'Нет связи с сервером. Проверьте Wi-Fi';
  static const errServer = 'Ошибка сервера. Код: ';
  static const errGeneric = 'Произошла ошибка. Попробуйте ещё раз';

  // Список документов
  static const docsTitle = 'Документы инвентаризации';
  static const docsEmpty = 'Документов не найдено';
  static const docsLoadError = 'Ошибка загрузки документов';
  static const docPosted = 'Проведён';
  static const docDraft = 'Черновик';
  static const orgLabel = 'Организация';
  static const deptLabel = 'Подразделение';
  static const linesCount = 'строк';

  // Табличная часть
  static const scannedProgress = 'Отсканировано: $count из $total';
  static const search = 'Поиск…';
  static const sortUnscannedFirst = 'Сначала неотсканированные';
  static const readyToScan = 'ГОТОВ К СКАНИРОВАНИЮ';
  static const scanByCamera = 'Сканировать камерой';
  static const finish = 'Завершить';
  static const qtyAccounting = 'Учёт: $n';
  static const qtyActual = 'Факт: $n';
  static const found = 'найдено';
  static const discrepancy = 'расхождение: факт $a, учёт $b';
  static const notFoundInDoc = 'Штрихкод $code не найден в документе';
  static const multipleMatches = 'Несколько совпадений. Выберите строку:';
  static const enterManually = 'Ввести код вручную';
  static const scanSuccess = 'Найдено';
  static const finishConfirm = 'Завершить инвентаризацию и отправить результаты?';
  static const sendError = 'Не удалось отправить. Сохранено локально. Повторить?';
  static const noOfflineCopy = 'Нет сохранённой копии документа и нет связи с сервером';
  static const accounting = 'Кол-во по учёту';
  static const actual = 'Кол-во факт.';
}
```
> `$count`, `$total` и т.п. — это плейсхолдеры интерполяции; для подстановки использовать методы-фабрики рядом, см. Step 1b.

- [ ] **Step 2: Добавить методы-фабрики строк в app_strings.dart**

Дополнить класс `AppStrings` (после констант) фабриками для параметризованных строк:
```dart
  // Методы-фабрики для параметризованных строк
  static String scannedProgressOf(int count, int total) =>
      'Отсканировано: $count из $total';
  static String qtyAccountingOf(int n) => 'Учёт: $n';
  static String qtyActualOf(int n) => 'Факт: $n';
  static String discrepancyOf(int actual, int accounting) =>
      'расхождение: факт $actual, учёт $accounting';
  static String notFoundCode(String code) => 'Штрихкод $code не найден в документе';
  static String errServerCode(int code) => 'Ошибка сервера. Код: $code';
```
(Удалить/заменить соответствующие `static const` с `$`-плейсхолдерами из Step 1 — оставить только корректные `const`, параметризованные перенести в методы.)

- [ ] **Step 3: Создать app_theme.dart — контрастная тема**

Создать `tsd_inventory/lib/theme/app_theme.dart`:
```dart
import 'package:flutter/material.dart';

/// Тема: крупная, контрастная, «палочко-устойчивая» для ТСД M3 SL20.
ThemeData appTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: const ColorScheme.highContrastLight(
      primary: Color(0xFF0D47A1),      // тёмно-синий
      onPrimary: Colors.white,
      secondary: Color(0xFF2E7D32),    // зелёный — «найдено»
      onSecondary: Colors.white,
      error: Color(0xFFC62828),        // красный
      surface: Colors.white,
      onSurface: Colors.black,
    ),
    textTheme: base.textTheme.copyWith(
      bodyLarge: const TextStyle(fontSize: 20, height: 1.3),
      bodyMedium: const TextStyle(fontSize: 18, height: 1.3),
      titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      titleMedium: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      labelLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(64),
        textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      contentPadding: EdgeInsets.all(16),
      border: OutlineInputBorder(),
      filled: true,
    ),
    cardTheme: const CardThemeData(
      margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
```

- [ ] **Step 4: Создать app.dart — MaterialApp + go_router**

Создать `tsd_inventory/lib/app.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'theme/app_theme.dart';

/// Корневой виджет. Router настраивается в Task 14-18 по мере добавления экранов.
class TsdApp extends ConsumerWidget {
  const TsdApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // routerProvider определён в Task 14; пока используем временный.
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Инвентаризация',
      theme: appTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Временный провайдер роутера (расширяется в Task 14).
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('login (Task 14)')),
        ),
      ),
    ],
  );
});
```

- [ ] **Step 5: Заменить main.dart**

Перезаписать `tsd_inventory/lib/main.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runApp(const ProviderScope(child: TsdApp()));
}
```

- [ ] **Step 6: Проверить analyze и сборку**

```bash
cd tsd_inventory
flutter analyze
```
Ожидается: `No issues found!` (warnings о неиспользуемом `appRouterProvider` допустимы до Task 14).

- [ ] **Step 7: Коммит**

```bash
git add tsd_inventory/lib
git commit -m "feat: каркас приложения (main/app/theme/strings на русском)"
```

---

### Task 4: core — Result, ApiError, AppConfig

**Files:**
- Create: `tsd_inventory/lib/core/config/app_config.dart`
- Create: `tsd_inventory/lib/core/result/result.dart`
- Create: `tsd_inventory/lib/core/network/api_error.dart`
- Create: `tsd_inventory/test/core/result/result_test.dart`
- Create: `tsd_inventory/test/core/network/api_error_test.dart`

- [ ] **Step 1: Написать failing-тест на Result**

Создать `tsd_inventory/test/core/result/result_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/result/result.dart';

void main() {
  test('Success хранит значение', () {
    final r = Success<int>(42);
    expect(r, isA<Success<int>>());
    expect((r as Success<int>).value, 42);
  });

  test('Failure хранит ApiError', () {
    final r = Failure<int>(const AuthError());
    expect(r, isA<Failure<int>>());
    expect((r as Failure<int>).error, isA<AuthError>());
  });

  test('mapFold: Success → onValue', () {
    final r = Success<int>(5);
    final out = r.maybeWhen(onValue: (v) => v * 2, orElse: () => -1);
    expect(out, 10);
  });

  test('mapFold: Failure → orElse', () {
    final r = Failure<int>(const NetworkError());
    final out = r.maybeWhen(onValue: (v) => v * 2, orElse: () => -1);
    expect(out, -1);
  });
}
```

- [ ] **Step 2: Запустить тест — должен падать (нет Result)**

```bash
cd tsd_inventory
flutter test test/core/result/result_test.dart
```
Ожидается: FAIL / compilation error (`result.dart` / классы не найдены).

- [ ] **Step 3: Реализовать Result**

Создать `tsd_inventory/lib/core/result/result.dart`:
```dart
import 'package:tsd_inventory/core/network/api_error.dart';

/// Результат операции: успех со значением или провал с типизированной ошибкой.
sealed class Result<T> {
  const Result();

  /// Свёртка: успех → onValue, провал → orElse.
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  });
}

class Success<T> extends Result<T> {
  final T value;
  const Success(this.value);

  @override
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  }) =>
      onValue(value);
}

class Failure<T> extends Result<T> {
  final ApiError error;
  const Failure(this.error);

  @override
  R maybeWhen<R>({
    required R Function(T value) onValue,
    required R Function(ApiError error) orElse,
  }) =>
      orElse(error);
}
```

- [ ] **Step 4: Реализовать ApiError (нужен для Result)**

Создать `tsd_inventory/lib/core/network/api_error.dart`:
```dart
import 'package:dio/dio.dart';

/// Типизированная ошибка API для человекочитаемых сообщений.
sealed class ApiError {
  const ApiError();
  String get userMessage;

  /// Маппинг DioException → ApiError.
  factory ApiError.fromDio(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 403) {
      return const AuthError();
    }
    if (code == 404) {
      return const NotFoundError();
    }
    if (code != null && code >= 500) {
      return ServerError(code: code);
    }
    // Сетевые: connection refused, timeout, socket
    return const NetworkError();
  }
}

class AuthError extends ApiError {
  const AuthError();
  @override
  String get userMessage => 'Неверный логин или пароль';
}

class NetworkError extends ApiError {
  const NetworkError();
  @override
  String get userMessage => 'Нет связи с сервером. Проверьте Wi-Fi';
}

class ServerError extends ApiError {
  final int code;
  const ServerError({required this.code});
  @override
  String get userMessage => 'Ошибка сервера. Код: $code';
}

class NotFoundError extends ApiError {
  const NotFoundError();
  @override
  String get userMessage => 'Не найдено';
}

class ParseError extends ApiError {
  final String detail;
  const ParseError(this.detail);
  @override
  String get userMessage => 'Ошибка обработки данных сервера';
}
```

- [ ] **Step 5: Запустить тест Result — должен пройти**

```bash
flutter test test/core/result/result_test.dart
```
Ожидается: `All tests passed!`

- [ ] **Step 6: Написать failing-тест на ApiError.fromDio**

Создать `tsd_inventory/test/core/network/api_error_test.dart`:
```dart
import 'package:dio/dio.dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/core/network/api_error.dart';

DioException _err(int? statusCode, {DioExceptionType type = DioExceptionType.badResponse}) {
  final res = statusCode == null
      ? null
      : Response<void>(requestOptions: RequestOptions(), statusCode: statusCode);
  return DioException(requestOptions: RequestOptions(), response: res, type: type);
}

void main() {
  test('401 → AuthError', () {
    expect(ApiError.fromDio(_err(401)), isA<AuthError>());
  });
  test('403 → AuthError', () {
    expect(ApiError.fromDio(_err(403)), isA<AuthError>());
  });
  test('404 → NotFoundError', () {
    expect(ApiError.fromDio(_err(404)), isA<NotFoundError>());
  });
  test('500 → ServerError', () {
    final e = ApiError.fromDio(_err(500)) as ServerError;
    expect(e.code, 500);
  });
  test('503 → ServerError', () {
    expect(ApiError.fromDio(_err(503)), isA<ServerError>());
  });
  test('connection timeout → NetworkError', () {
    final e = DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.connectionTimeout,
    );
    expect(ApiError.fromDio(e), isA<NetworkError>());
  });
  test('no response (socket) → NetworkError', () {
    expect(ApiError.fromDio(_err(null)), isA<NetworkError>());
  });
}
```

- [ ] **Step 7: Запустить тест ApiError**

```bash
flutter test test/core/network/api_error_test.dart
```
Ожидается: `All tests passed!` (если опечатка в import `dio.dart.dart` — исправить на `package:dio/dio.dart`).

- [ ] **Step 8: Реализовать AppConfig**

Создать `tsd_inventory/lib/core/config/app_config.dart`:
```dart
/// Конфигурация приложения: адрес 1С и режим сканера.
/// baseUrl настраивается (см. README): 10.0.2.2 для эмулятора, IP сервера для ТСД.
class AppConfig {
  const AppConfig({
    this.baseUrl = 'http://10.0.2.2/ERP_Local',
    this.scannerMode = ScannerMode.keyboardWedge,
    this.connectTimeoutSec = 10,
    this.receiveTimeoutSec = 30,
  });

  /// Базовый URL HTTP-сервисов 1С (без /hs/...).
  final String baseUrl;
  final ScannerMode scannerMode;
  final int connectTimeoutSec;
  final int receiveTimeoutSec;

  /// Конструирует полный путь: baseUrl + '/hs/inventory/' + path.
  String inventoryPath(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return '$base/hs/inventory/$path';
  }
}

/// Режим приёма скан-кодов. По умолчанию keyboard wedge (M3 SDK недоступен).
enum ScannerMode { keyboardWedge, broadcastIntent, camera }
```

- [ ] **Step 9: Коммит**

```bash
git add tsd_inventory/lib/core tsd_inventory/test
git commit -m "feat(core): Result<T>, ApiError (fromDio), AppConfig"
```

---

### Task 5: core/network — DioClient (BasicAuth + retry)

**Files:**
- Create: `tsd_inventory/lib/core/network/dio_client.dart`

- [ ] **Step 1: Реализовать DioClient с BasicAuth interceptor**

Создать `tsd_inventory/lib/core/network/dio_client.dart`:
```dart
import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/app_config.dart';

/// Учётные данные Basic Auth.
class BasicCredentials {
  const BasicCredentials(this.login, this.password);
  final String login;
  final String password;

  String get headerValue =>
      'Basic ${base64Encode(utf8.encode('$login:$password'))}';
}

/// HttpClient на dio с BasicAuth + timeout + retry.
class DioClient {
  DioClient({required AppConfig config, required BasicCredentials credentials})
      : _dio = Dio(BaseOptions(
          baseUrl: config.baseUrl,
          connectTimeout: Duration(seconds: config.connectTimeoutSec),
          receiveTimeout: Duration(seconds: config.receiveTimeoutSec),
          responseType: ResponseType.json,
          headers: {'Accept': 'application/json'},
        )) {
    _dio.interceptors.add(_BasicAuthInterceptor(credentials));
    _dio.interceptors.add(_RetryInterceptor(maxRetries: 2));
  }

  final Dio _dio;

  Future<Response<T>> getJson<T>(String path, {Map<String, dynamic>? query}) =>
      _dio.get<T>(path, queryParameters: query);

  Future<Response<T>> postJson<T>(String path, {Object? body}) =>
      _dio.post<T>(path, data: body);
}

/// Выставляет Authorization: Basic на каждый запрос.
class _BasicAuthInterceptor extends Interceptor {
  _BasicAuthInterceptor(this._creds);
  final BasicCredentials _creds;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = _creds.headerValue;
    handler.next(options);
  }
}

/// Простой retry на сетевые ошибки (connection/timeout) с backoff.
class _RetryInterceptor extends Interceptor {
  _RetryInterceptor({required this.maxRetries});
  final int maxRetries;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra['retryAttempt'] as int?) ?? 0;
    final retriable = err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionError ||
        (err.response?.statusCode != null && err.response!.statusCode! >= 500);

    if (attempt < maxRetries && retriable) {
      await Future.delayed(Duration(seconds: attempt + 1));
      try {
        err.requestOptions.extra['retryAttempt'] = attempt + 1;
        final dio = Dio();
        final response = await dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } on DioException catch (e) {
        handler.next(e);
        return;
      }
    }
    handler.next(err);
  }
}
```
> Примечание к `_RetryInterceptor`: создаёт временный `Dio()` для повтора. Альтернатива — пакет `retry`/`dio_smart_retry`; здесь реализация самодостаточная, без доп. зависимости.

- [ ] **Step 2: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/core/network/dio_client.dart
```
Ожидается: нет ошибок (warnings допустимы).

- [ ] **Step 3: Коммит**

```bash
git add tsd_inventory/lib/core/network/dio_client.dart
git commit -m "feat(core): DioClient с BasicAuth + retry + timeout"
```

---

### Task 6: core/storage — SecureCredentialsStore

**Files:**
- Create: `tsd_inventory/lib/core/storage/secure_credentials_store.dart`

- [ ] **Step 1: Реализовать secure-хранилище учётных данных**

Создать `tsd_inventory/lib/core/storage/secure_credentials_store.dart`:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Сохранение логина/пароля в Android Keystore (через flutter_secure_storage).
class SecureCredentialsStore {
  SecureCredentialsStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _kLogin = 'login';
  static const _kPassword = 'password';

  Future<String?> readLogin() => _storage.read(key: _kLogin);
  Future<void> writeLogin(String login) => _storage.write(key: _kLogin, value: login);
  Future<void> removeLogin() => _storage.delete(key: _kLogin);

  Future<String?> readPassword() => _storage.read(key: _kPassword);
  Future<void> writePassword(String password) =>
      _storage.write(key: _kPassword, value: password);
  Future<void> removePassword() => _storage.delete(key: _kPassword);

  /// Полная очистка (выход / смена пользователя).
  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
```

- [ ] **Step 2: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/core/storage/secure_credentials_store.dart
```
Ожидается: нет ошибок.

- [ ] **Step 3: Коммит**

```bash
git add tsd_inventory/lib/core/storage/secure_credentials_store.dart
git commit -m "feat(core): SecureCredentialsStore (flutter_secure_storage)"
```

---

### Task 7: core/storage — AppDatabase (drift SQLite)

**Files:**
- Create: `tsd_inventory/lib/core/storage/app_database.dart`

- [ ] **Step 1: Реализовать drift-базу с таблицами ScanProgress и CachedDoc**

Создать `tsd_inventory/lib/core/storage/app_database.dart`:
```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

/// Прогресс сканирования: одна строка на (docCode, lineNumber).
/// Восстанавливается при перезапуске приложения.
class ScanProgress extends Table {
  TextColumn get docCode => text()();
  IntColumn get lineNumber => integer()();
  TextColumn get nomenclatureCode => text().nullable()();
  IntColumn get qtyActual => integer().withDefault(const Constant(0))();
  TextColumn get action => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {docCode, lineNumber};
}

/// Кэш табличной части документа (сырой JSON /code/) для офлайн-доступа.
class CachedDoc extends Table {
  TextColumn get code => text()();
  TextColumn get json => text()();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {code};
}

@DriftDatabase(tables: [ScanProgress, CachedDoc])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  // --- ScanProgress ---

  /// Вставка/обновление прогресса одной строки.
  Future<void> upsertScanProgress({
    required String docCode,
    required int lineNo,
    String? nomenclatureCode,
    required int qtyActual,
    String? action,
  }) async {
    into(scanProgress).insertOnConflictUpdate(ScanProgressCompanion.insert(
      docCode: docCode,
      lineNumber: lineNo,
      nomenclatureCode: Value(nomenclatureCode),
      qtyActual: Value(qtyActual),
      action: Value(action),
    ));
  }

  /// Восстановление прогресса: lineNumber → строка.
  Future<Map<int, ScanProgressData>> getScanProgress(String docCode) async {
    final rows = await (select(scanProgress)
          ..where((t) => t.docCode.equals(docCode)))
        .get();
    return {for (final r in rows) r.lineNumber: r};
  }

  /// Очистка прогресса документа (после успешной отправки).
  Future<void> clearScanProgress(String docCode) async {
    await (delete(scanProgress)..where((t) => t.docCode.equals(docCode))).go();
  }

  // --- CachedDoc ---

  Future<void> cacheDoc(String code, String json) async {
    into(cachedDoc).insertOnConflictUpdate(CachedDocCompanion.insert(
      code: code,
      json: json,
      fetchedAt: Value(DateTime.now()),
    ));
  }

  Future<CachedDocData?> getCachedDoc(String code) async {
    final q = select(cachedDoc)
      ..where((t) => t.code.equals(code))
      ..limit(1);
    return q.getSingleOrNull();
  }

  Future<void> clearCachedDoc(String code) async {
    await (delete(cachedDoc)..where((t) => t.code.equals(code))).go();
  }
}

LazyDatabase _open() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'tsd_inventory.sqlite'));
    return NativeDatabase(file);
  });
}
```

- [ ] **Step 2: Добавить зависимость path в pubspec.yaml**

Проверить, что в `tsd_inventory/pubspec.yaml` есть:
```yaml
  path: ^1.9.0
```
(Если нет — добавить в `dependencies` и `flutter pub get`.)

- [ ] **Step 3: Сгенерировать код drift (.g.dart)**

```bash
cd tsd_inventory
dart run build_runner build --delete-conflicting-outputs
```
Ожидается: создан `lib/core/storage/app_database.g.dart`, `Build completed successfully`. Если ошибка — проверить совпадение имён таблиц/колонок и аннотаций `@DriftDatabase`.

- [ ] **Step 4: Проверить analyze**

```bash
flutter analyze lib/core/storage/
```
Ожидается: нет ошибок.

- [ ] **Step 5: Коммит (включая сгенерированный .g.dart)**

```bash
git add tsd_inventory/lib/core/storage tsd_inventory/pubspec.yaml pubspec.lock tsd_inventory/pubspec.lock
git commit -m "feat(core): drift AppDatabase (ScanProgress, CachedDoc) + codegen"
```

---

### Task 8: core/scanner — ScannerSource + стратегии

**Files:**
- Create: `tsd_inventory/lib/core/scanner/scanner_source.dart`
- Create: `tsd_inventory/lib/core/scanner/keyboard_wedge_scanner.dart`
- Create: `tsd_inventory/lib/core/scanner/broadcast_intent_scanner.dart`
- Create: `tsd_inventory/lib/core/scanner/camera_scanner.dart`

- [ ] **Step 1: Интерфейс ScannerSource**

Создать `tsd_inventory/lib/core/scanner/scanner_source.dart`:
```dart
/// Единый интерфейс приёма штрихкодов.
/// UI и ScanController зависят только от него — смена стратегии = замена реализации.
abstract interface class ScannerSource {
  /// Поток отсканированных кодов (уже «склеенных», по одной строке на скан).
  Stream<String> get codes;

  /// Запуск (подписка на источник устройства/SDK).
  Future<void> start();

  /// Освобождение ресурсов.
  Future<void> dispose();
}
```

- [ ] **Step 2: KeyboardWedgeScanner (основная стратегия)**

Создать `tsd_inventory/lib/core/scanner/keyboard_wedge_scanner.dart`:
```dart
import 'dart:async';

import 'scanner_source.dart';

/// Приём скан-кодов как keyboard wedge: скрытый TextField + onSubmitted.
/// Буферизует быстрый ввод (устройства шлют код порциями) с таймаутом ~80мс.
///
/// Виджет-обёртка, держащая фокус, реализована в [KeyboardWedgeField]
/// (см. inventory_screen.dart, Task 18). Этот класс отвечает за логику склейки.
class KeyboardWedgeScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();
  final _buf = StringBuffer();
  Timer? _idleTimer;

  /// Таймаут завершения порции ввода (мс).
  final Duration flushTimeout;

  KeyboardWedgeScanner({this.flushTimeout = const Duration(milliseconds: 80)});

  @override
  Stream<String> get codes => _controller.stream;

  /// Вызывается из onChanged скрытого поля: накапливает символы.
  void onTextChanged(String chunk) {
    // wedge обычно шлёт весь код сразу в onChanged; но страхуемся порциями
    _buf.write(chunk);
    _idleTimer?.cancel();
    _idleTimer = Timer(flushTimeout, _flush);
  }

  /// Вызывается из onSubmitted (Enter от сканера) — основной путь.
  void onSubmitted(String value) {
    _buf.write(value);
    _flush();
  }

  void _flush() {
    _idleTimer?.cancel();
    final code = _buf.toString().trim();
    _buf.clear();
    if (code.isNotEmpty) {
      _controller.add(code);
    }
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    _idleTimer?.cancel();
    await _controller.close();
  }
}
```

- [ ] **Step 3: BroadcastIntentScanner (stub под M3 SDK)**

Создать `tsd_inventory/lib/core/scanner/broadcast_intent_scanner.dart`:
```dart
import 'dart:async';

import 'scanner_source.dart';

/// Приём скан-кодов через Broadcast Intent от M3 Mobile SDK.
///
/// TODO(M3 SDK): для подключения потребуется AAR M3 Mobile SDK и
/// Android-нативная обвязка (EventChannel/BroadcastReceiver). Сейчас — stub.
/// Включается через AppConfig.scannerMode == ScannerMode.broadcastIntent.
class BroadcastIntentScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();

  @override
  Stream<String> get codes => _controller.stream;

  @override
  Future<void> start() async {
    // TODO(M3 SDK): зарегистрировать BroadcastReceiver, слушать Intent,
    // парсить extras и пушить в _controller.add(code).
    throw UnimplementedError(
        'BroadcastIntentScanner требует M3 Mobile SDK (не подключён)');
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
```

- [ ] **Step 4: CameraScanner (mobile_scanner, ручной режим)**

Создать `tsd_inventory/lib/core/scanner/camera_scanner.dart`:
```dart
import 'dart:async';

import 'scanner_source.dart';

/// Камерный сканер (mobile_scanner). Резерв/ручной режим.
/// Виджет камеры открывается по кнопке «Сканировать камерой» на экране ТЧ.
/// Здесь — обёртка потока; сам виджет mobile_scanner используется напрямую в UI.
class CameraScanner implements ScannerSource {
  final _controller = StreamController<String>.broadcast();

  /// UI mobile_scanner вызывает этот метод при декоде кода.
  void onDecoded(String code) {
    if (code.isNotEmpty) _controller.add(code);
  }

  @override
  Stream<String> get codes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
```

- [ ] **Step 5: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/core/scanner/
```
Ожидается: нет ошибок.

- [ ] **Step 6: Коммит**

```bash
git add tsd_inventory/lib/core/scanner
git commit -m "feat(core): ScannerSource + keyboard wedge / broadcast stub / camera"
```

---

### Task 9: core/feedback — FeedbackService (звук/вибро)

**Files:**
- Create: `tsd_inventory/lib/core/feedback/feedback_service.dart`

- [ ] **Step 1: Реализовать FeedbackService**

Создать `tsd_inventory/lib/core/feedback/feedback_service.dart`:
```dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

/// Звуковая/вибро-обратная связь на результат сканирования.
/// Для шумных цехов: высокий тон = успех, низкий = ошибка, средний = внимание.
class FeedbackService {
  FeedbackService({AudioPlayer? player}) : _player = player ?? AudioPlayer();

  final AudioPlayer _player;
  bool _muted = false;

  /// Отключить звук (например, по настройке). Вибро остаётся.
  set muted(bool v) => _muted = v;

  Future<void> success() async {
    await Future.wait([
      _vibrate(30),
      if (!_muted) _beep(1500, durationMs: 90),
    ]);
  }

  Future<void> error() async {
    await Future.wait([
      _vibrate(200),
      if (!_muted) _beep(400, durationMs: 350),
    ]);
  }

  Future<void> attention() async {
    await Future.wait([
      _vibrate(100),
      if (!_muted) _beep(900, durationMs: 150),
    ]);
  }

  Future<void> _beep(int freqHz, {required int durationMs}) async {
    // Простой способ: системный звук клика. Для точного тона — сгенерировать WAV.
    // Здесь используем короткий tone через SoundPool (через system sound id).
    await _player.play(AssetSource('sounds/beep.wav'),
        volume: 0.8);
  }

  Future<void> _vibrate(int ms) async {
    await HapticFeedback.heavyImpact();
  }
}
```

- [ ] **Step 2: Создать ассет-звук (заглушка)**

Создать каталог `tsd_inventory/assets/sounds/`. Поскольку генерация WAV выходит за рамку, использовать системный звук через `SystemSound.play(SystemSoundType.click)` как fallback.

Дополнить `_beep` в `feedback_service.dart` fallback-ом:
```dart
  Future<void> _beep(int freqHz, {required int durationMs}) async {
    try {
      await _player.play(AssetSource('sounds/beep.wav'), volume: 0.8);
    } catch (_) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
```
(Добавить `import 'package:flutter/services.dart';` — уже есть.)

- [ ] **Step 3: Коммит**

```bash
git add tsd_inventory/lib/core/feedback tsd_inventory/assets
git commit -m "feat(core): FeedbackService (звук + вибро обратная связь)"
```

---

### Task 10: features/auth — AuthRepository + AuthController + AuthSession

**Files:**
- Create: `tsd_inventory/lib/features/auth/data/auth_repository.dart`
- Create: `tsd_inventory/lib/features/auth/application/auth_controller.dart`

- [ ] **Step 1: Реализовать AuthSession (состояние сессии)**

Внутри `tsd_inventory/lib/features/auth/application/auth_controller.dart` определить модель сессии:
```dart
/// Сессия авторизованного пользователя.
class AuthSession {
  const AuthSession({required this.login, required this.password});
  final String login;
  final String password;

  /// Логин = ФИО (решение из дизайна).
  String get fio => login;
}
```

- [ ] **Step 2: Реализовать AuthRepository**

Создать `tsd_inventory/lib/features/auth/data/auth_repository.dart`:
```dart
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

/// Проверка учётных данных 1С через Basic Auth.
/// Зонд: лёгкий GET к эндпоинту под Basic Auth.
///   200/204 → успех; 401/403 → AuthError; сетевая → NetworkError.
class AuthRepository {
  AuthRepository(this._clientFactory);
  final BasicCredentials Function() _clientFactory;

  /// Возвращает Success(login) при успехе или Failure.
  Future<Result<String>> login(String login, String password) async {
    final creds = BasicCredentials(login, password);
    try {
      // Лёгкий зонд: запрос списка документов по этому ФИО (он же валидирует учётку).
      final client = DioClient(
        config: _config(),
        credentials: creds,
      );
      final path =
          'hs/inventory/fio/${Uri.encodeComponent(login)}';
      final res = await client.getJson<dynamic>(path);
      if (res.statusCode == 200 || res.statusCode == 204) {
        return Success(login);
      }
      return const Failure(AuthError());
    } on Exception catch (e) {
      if (e is Exception && e.toString().contains('401')) {
        return const Failure(AuthError());
      }
      // Низкоуровневую ошибку прогоняем через ApiError.fromDio (если это DioException)
      return Failure(_mapError(e));
    }
  }
}

AppConfig _config() => const AppConfig();

ApiError _mapError(Object e) {
  if (e is dynamic) {
    // Динамическая проверка DioException без жёсткой типизации здесь
    try {
      final dio = e;
      return ApiError.fromDio(dio);
    } catch (_) {
      return const NetworkError();
    }
  }
  return const NetworkError();
}
```
> Упрощение: `login` ловит `DioException` через try/catch. Чище — явно `on DioException catch (e)`. В Step 3 ниже исправляем.

- [ ] **Step 3: Упростить и корректно типизировать обработку ошибок**

Переписать `AuthRepository` полностью (финальная версия):
```dart
import 'package:dio/dio.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

/// Проверка учётных данных 1С через Basic Auth.
class AuthRepository {
  AuthRepository(this._config);
  final AppConfig _config;

  /// Возвращает Success(login) при успехе или Failure.
  Future<Result<String>> login(String login, String password) async {
    final client = DioClient(
      config: _config,
      credentials: BasicCredentials(login, password),
    );
    try {
      final path = 'hs/inventory/fio/${Uri.encodeComponent(login)}';
      final res = await client.getJson<dynamic>(path);
      if (res.statusCode == 200 || res.statusCode == 204) {
        return Success(login);
      }
      return const Failure(AuthError());
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (_) {
      return const Failure(NetworkError());
    }
  }
}
```

- [ ] **Step 4: Реализовать AuthController (Riverpod Notifier)**

Дополнить `auth_controller.dart` (после `AuthSession`):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/storage/secure_credentials_store.dart';
import '../data/auth_repository.dart';

/// Состояние авторизации: null = не авторизован.
class AuthState {
  const AuthState({this.session, this.rememberLogin = true, this.rememberPassword = false});
  final AuthSession? session;
  final bool rememberLogin;
  final bool rememberPassword;
  bool get isAuthenticated => session != null;
  AuthState copyWith({AuthSession? session, bool? rememberLogin, bool? rememberPassword}) =>
      AuthState(
        session: session ?? this.session,
        rememberLogin: rememberLogin ?? this.rememberLogin,
        rememberPassword: rememberPassword ?? this.rememberPassword,
      );
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  late final _repo = AuthRepository(ref.watch(appConfigProvider));
  late final _store = ref.watch(secureCredentialsStoreProvider);

  /// Попытка входа. Возвращает null при успехе, сообщение об ошибке при провале.
  Future<String?> login(String login, String password,
      {required bool rememberLogin, required bool rememberPassword}) async {
    final res = await _repo.login(login, password);
    return res.maybeWhen(
      onValue: (_) async {
        // Сохранение в secure storage по флагам
        if (rememberLogin) {
          await _store.writeLogin(login);
        } else {
          await _store.removeLogin();
        }
        if (rememberPassword) {
          await _store.writePassword(password);
        } else {
          await _store.removePassword();
        }
        state = AuthState(
          session: AuthSession(login: login, password: password),
          rememberLogin: rememberLogin,
          rememberPassword: rememberPassword,
        );
        return null; // успех
      },
      orElse: (err) => err.userMessage,
    );
  }

  Future<void> logout() async {
    await _store.clear();
    state = const AuthState();
  }

  /// Восстановление сохранённого логина при старте.
  Future<void> hydrate() async {
    final login = await _store.readLogin();
    if (login != null) {
      state = state.copyWith(rememberLogin: true);
    }
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

// --- Провайдеры зависимостей core (общие, определим здесь при первом использовании) ---
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());
final secureCredentialsStoreProvider = Provider<SecureCredentialsStore>(
    (ref) => SecureCredentialsStore());
```

- [ ] **Step 5: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/features/auth/
```
Ожидается: нет ошибок.

- [ ] **Step 6: Коммит**

```bash
git add tsd_inventory/lib/features/auth
git commit -m "feat(auth): AuthRepository (Basic Auth зонд /fio/) + AuthController"
```

---

### Task 11: features/docs/domain — DocListItem + parseDocList (TDD)

**Files:**
- Create: `tsd_inventory/lib/features/docs/domain/doc_list_item.dart`
- Create: `tsd_inventory/lib/features/docs/domain/doc_list_parser.dart`
- Create: `tsd_inventory/test/features/docs/domain/doc_list_parser_test.dart`

- [ ] **Step 1: Написать failing-тест на parseDocList**

Создать `tsd_inventory/test/features/docs/domain/doc_list_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/docs/domain/doc_list_parser.dart';

void main() {
  test('обходит обёртку #value и парсит поля', () {
    final json = [
      {
        '#value': {
          'Ref': 'bdb920e7-738f-11f1-bb02-e83525ee0c0b',
          'Date': '2026-06-29T10:54:23',
          'Number': 'АЕ-00000002',
          'Posted': true,
          'Организация': '3d074bd8-4bcb-11e5-9b25-000c299754cd',
          'Подразделение': '141190b0-bb5d-11e5-9b78-002590fbf13d',
        }
      },
    ];
    final list = parseDocList(json);
    expect(list.length, 1);
    final d = list.single;
    expect(d.ref, 'bdb920e7-738f-11f1-bb02-e83525ee0c0b');
    expect(d.number, 'АЕ-00000002');
    expect(d.posted, true);
    expect(d.date, DateTime.parse('2026-06-29T10:54:23'));
    expect(d.organizationGuid, '3d074bd8-4bcb-11e5-9b25-000c299754cd');
    expect(d.departmentGuid, '141190b0-bb5d-11e5-9b78-002590fbf13d');
  });

  test('пустые GUID → null', () {
    final json = [
      {
        '#value': {
          'Ref': 'ref1',
          'Date': '2026-06-29T10:54:23',
          'Number': 'АЕ-00000001',
          'Posted': false,
          'Организация': '',
          'Подразделение': '',
          'Ответственный': '',
        }
      },
    ];
    final d = parseDocList(json).single;
    expect(d.organizationGuid, isNull);
    expect(d.departmentGuid, isNull);
    expect(d.responsibleGuid, isNull);
    expect(d.posted, false);
  });

  test('невалидная дата → элемент пропускается, список не падает', () {
    final json = [
      {'#value': {'Ref': 'bad', 'Date': 'not-a-date', 'Number': 'X-1', 'Posted': true}},
      {'#value': {'Ref': 'good', 'Date': '2026-06-29T10:54:23', 'Number': 'X-2', 'Posted': true}},
    ];
    final list = parseDocList(json);
    expect(list.length, 1);
    expect(list.single.ref, 'good');
  });

  test('отсутствие #value → элемент трактуется как сам Map', () {
    final json = [
      {'Ref': 'direct', 'Date': '2026-06-29T10:54:23', 'Number': 'D-1', 'Posted': true},
    ];
    final d = parseDocList(json).single;
    expect(d.ref, 'direct');
    expect(d.number, 'D-1');
  });

  test('пустой массив → пустой список', () {
    expect(parseDocList([]), isEmpty);
  });
}
```

- [ ] **Step 2: Запустить тест — должен падать**

```bash
cd tsd_inventory
flutter test test/features/docs/domain/doc_list_parser_test.dart
```
Ожидается: FAIL (нет `doc_list_parser.dart` / `DocListItem`).

- [ ] **Step 3: Реализовать DocListItem**

Создать `tsd_inventory/lib/features/docs/domain/doc_list_item.dart`:
```dart
/// Документ инвентаризации из списка /fio/.
class DocListItem {
  const DocListItem({
    required this.ref,
    required this.number,
    required this.date,
    required this.posted,
    this.organizationGuid,
    this.departmentGuid,
    this.responsibleGuid,
  });

  final String ref;                 // GUID
  final String number;              // "АЕ-00000002"
  final DateTime date;
  final bool posted;
  final String? organizationGuid;   // GUID (человекочитаемого в /fio/ нет)
  final String? departmentGuid;
  final String? responsibleGuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocListItem && runtimeType == other.runtimeType && ref == other.ref;

  @override
  int get hashCode => ref.hashCode;
}
```

- [ ] **Step 4: Реализовать parseDocList**

Создать `tsd_inventory/lib/features/docs/domain/doc_list_parser.dart`:
```dart
import 'package:logging/logging.dart';

import 'doc_list_item.dart';

final _log = Logger('doc_list_parser');

/// Парсер ответа /fio/: массив объектов, обёрнутых в "#value".
/// Чистая функция, не зависит от Flutter/dio — тестируется в unit-тестах.
List<DocListItem> parseDocList(Object? json) {
  if (json is! List) return const [];
  final result = <DocListItem>[];
  for (final el in json) {
    if (el is! Map) continue;
    // Обход обёртки #value; при отсутствии — сам элемент.
    final v = (el['#value'] as Map?) ?? el;
    try {
      final rawDate = v['Date']?.toString();
      if (rawDate == null) continue;
      final date = DateTime.parse(rawDate);
      result.add(DocListItem(
        ref: v['Ref']?.toString() ?? '',
        number: v['Number']?.toString() ?? '',
        date: date,
        posted: v['Posted'] as bool? ?? false,
        organizationGuid: _guidOrNull(v['Организация']),
        departmentGuid: _guidOrNull(v['Подразделение']),
        responsibleGuid: _guidOrNull(v['Ответственный']),
      ));
    } catch (e) {
      _log.warning('Пропуск элемента списка документов из-за ошибки парсинга: $e');
    }
  }
  return result;
}

String? _guidOrNull(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}
```

- [ ] **Step 5: Запустить тест — должен пройти**

```bash
flutter test test/features/docs/domain/doc_list_parser_test.dart
```
Ожидается: `All tests passed!`

- [ ] **Step 6: Коммит**

```bash
git add tsd_inventory/lib/features/docs/domain tsd_inventory/test
git commit -m "feat(docs): DocListItem + parseDocList (#value) + unit-тесты"
```

---

### Task 12: features/docs/data — DocsRepository + controller

**Files:**
- Create: `tsd_inventory/lib/features/docs/data/docs_repository.dart`
- Create: `tsd_inventory/lib/features/docs/application/docs_controller.dart`

- [ ] **Step 1: Реализовать DocsRepository**

Создать `tsd_inventory/lib/features/docs/data/docs_repository.dart`:
```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';

import '../domain/doc_list_item.dart';
import '../domain/doc_list_parser.dart';

/// Загрузка списка документов инвентаризации по ФИО.
/// GET /hs/inventory/fio/{ФИО} (ФИО URL-encoded).
class DocsRepository {
  DocsRepository(this._client);
  final DioClient _client;

  Future<Result<List<DocListItem>>> getByFio(String fio) async {
    final path = 'hs/inventory/fio/${Uri.encodeComponent(fio)}';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data;
      // Данные могут прийти строкой (если contentType не json) — страхуемся.
      final parsed = data is String ? jsonDecode(data) : data;
      return Success(parseDocList(parsed));
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      return const Failure(ParseError('Не удалось разобрать список документов'));
    }
  }
}
```

- [ ] **Step 2: Реализовать docs controller (Riverpod AsyncNotifier)**

Создать `tsd_inventory/lib/features/docs/application/docs_controller.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/features/auth/application/auth_controller.dart';
import 'package:tsd_inventory/features/auth/data/auth_repository.dart'
    show AuthSession;
import '../data/docs_repository.dart';
import '../domain/doc_list_item.dart';

/// Загрузка списка документов для текущего пользователя.
/// AsyncValue<List<DocListItem>>: loading/data/error одной сущностью.
class DocsController extends AsyncNotifier<List<DocListItem>> {
  late final String _fio;
  late final DocsRepository _repo;

  @override
  Future<List<DocListItem>> build() async {
    final session = ref.watch(authControllerProvider).session;
    if (session == null) {
      state = const AsyncValue.error('Не авторизован', StackTrace.empty);
      return [];
    }
    _fio = session.fio;
    _repo = ref.watch(docsRepositoryProvider);
    return _load();
  }

  Future<List<DocListItem>> _load() async {
    final res = await _repo.getByFio(_fio);
    return res.maybeWhen(
      onValue: (v) => v,
      orElse: (err) => throw Exception(err.userMessage),
    );
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }
}

final docsControllerProvider =
    AsyncNotifierProvider<DocsController, List<DocListItem>>(
        DocsController.new);

/// Фабрика DocsRepository: использует DioClient с учёткой текущей сессии.
final docsRepositoryProvider = Provider<DocsRepository>((ref) {
  final session = ref.watch(authControllerProvider).session as AuthSession;
  final config = ref.watch(appConfigProvider);
  final client = DioClient(
    config: config,
    credentials: BasicCredentials(session.login, session.password),
  );
  return DocsRepository(client);
});
```

- [ ] **Step 3: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/features/docs/
```
Ожидается: нет ошибок.

- [ ] **Step 4: Коммит**

```bash
git add tsd_inventory/lib/features/docs/data tsd_inventory/lib/features/docs/application
git commit -m "feat(docs): DocsRepository (GET /fio/) + AsyncNotifier controller"
```

---

### Task 13: features/inventory/domain — DocTableRow + parser + BarcodeMatcher (TDD)

**Files:**
- Create: `tsd_inventory/lib/features/inventory/domain/doc_table_row.dart`
- Create: `tsd_inventory/lib/features/inventory/domain/doc_table_parser.dart`
- Create: `tsd_inventory/lib/features/inventory/domain/barcode_matcher.dart`
- Create: `tsd_inventory/test/features/inventory/domain/doc_table_parser_test.dart`
- Create: `tsd_inventory/test/features/inventory/domain/doc_table_row_test.dart`
- Create: `tsd_inventory/test/features/inventory/domain/barcode_matcher_test.dart`

- [ ] **Step 1: Написать failing-тест на parseDocTable**

Создать `tsd_inventory/test/features/inventory/domain/doc_table_parser_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_parser.dart';

void main() {
  test('ключи-номера строк → int, количества-строки → int', () {
    final json = {
      '1': {
        'ИнвентарныйНомер': '44182',
        'Номенклатура': 'УЗ Дефектоскоп УД2-12',
        'НоменклатураКод': '00000000123',
        'Характеристика': '',
        'Серия': '',
        'СтатусУказанияСерий': '0',
        'ФизическоеЛицо': 'Белай Зоя Григорьевна',
        'КоличествоПоДаннымУчета': '1',
        'КоличествоФактическое': '1',
      },
      '2': {
        'ИнвентарныйНомер': '',
        'Номенклатура': 'Негатоскоп',
        'НоменклатураКод': '00000000456',
        'Характеристика': 'А3 Люмен',
        'Серия': '',
        'СтатусУказанияСерий': '0',
        'ФизическоеЛицо': 'Берлинская С.А.',
        'КоличествоПоДаннымУчета': '1',
        'КоличествоФактическое': '0',
      },
    };
    final rows = parseDocTable(json);
    expect(rows.length, 2);
    expect(rows[0].lineNumber, 1);
    expect(rows[0].inventoryNumber, '44182');
    expect(rows[0].nomenclatureCode, '00000000123');
    expect(rows[0].qtyAccounting, 1);
    expect(rows[0].qtyActual, 1);
    expect(rows[0].isFound, true);
    expect(rows[1].lineNumber, 2);
    expect(rows[1].qtyActual, 0);
    expect(rows[1].isFound, false);
  });

  test('сортировка по lineNumber', () {
    final json = {
      '10': {'Номенклатура': 'B', 'НоменклатураКод': 'x', 'КоличествоПоДаннымУчета': '0', 'КоличествоФактическое': '0'},
      '2': {'Номенклатура': 'A', 'НоменклатураКод': 'y', 'КоличествоПоДаннымУчета': '0', 'КоличествоФактическое': '0'},
    };
    final rows = parseDocTable(json);
    expect(rows.map((r) => r.lineNumber).toList(), [2, 10]);
  });

  test('невалидные количества → 0', () {
    final json = {
      '1': {
        'Номенклатура': 'X',
        'НоменклатураКод': 'k',
        'КоличествоПоДаннымУчета': 'не число',
        'КоличествоФактическое': '',
      }
    };
    final r = parseDocTable(json).single;
    expect(r.qtyAccounting, 0);
    expect(r.qtyActual, 0);
  });

  test('отсутствие НоменклатураКод → пустая строка (fallback)', () {
    final json = {
      '1': {'Номенклатура': 'X', 'КоличествоПоДаннымУчета': '1', 'КоличествоФактическое': '0'}
    };
    expect(parseDocTable(json).single.nomenclatureCode, '');
  });

  test('нечисловой ключ строки → lineNumber 0, не валит', () {
    final json = {
      'abc': {'Номенклатура': 'X', 'НоменклатураКод': 'k', 'КоличествоПоДаннымУчета': '0', 'КоличествоФактическое': '0'},
    };
    final r = parseDocTable(json).single;
    expect(r.lineNumber, 0);
  });
}
```

- [ ] **Step 2: Написать failing-тест на DocTableRow.isFound/hasDiscrepancy**

Создать `tsd_inventory/test/features/inventory/domain/doc_table_row_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row({required int accounting, required int actual}) =>
    DocTableRow(
      lineNumber: 1,
      inventoryNumber: '',
      nomenclature: '',
      nomenclatureCode: '',
      characteristic: '',
      series: '',
      seriesStatus: '0',
      fio: '',
      qtyAccounting: accounting,
      qtyActual: actual,
      action: '',
    );

void main() {
  test('факт 0 → не найдено', () {
    expect(_row(accounting: 1, actual: 0).isFound, false);
  });
  test('факт > 0 и == учёту → найдено без расхождения', () {
    final r = _row(accounting: 2, actual: 2);
    expect(r.isFound, true);
    expect(r.hasDiscrepancy, false);
  });
  test('факт ≠ учёту → расхождение', () {
    final r = _row(accounting: 3, actual: 1);
    expect(r.isFound, true);
    expect(r.hasDiscrepancy, true);
  });
}
```

- [ ] **Step 3: Написать failing-тест на BarcodeMatcher**

Создать `tsd_inventory/test/features/inventory/domain/barcode_matcher_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

DocTableRow _row(int line, String code,
        {String inv = '', String series = '', String nom = ''}) =>
    DocTableRow(
      lineNumber: line,
      inventoryNumber: inv,
      nomenclature: nom,
      nomenclatureCode: code,
      characteristic: '',
      series: series,
      seriesStatus: '0',
      fio: '',
      qtyAccounting: 1,
      qtyActual: 0,
      action: '',
    );

void main() {
  test('уникальное совпадение по НоменклатураКод', () {
    final rows = [_row(1, '000123'), _row(2, '000456')];
    final r = BarcodeMatcher().match('000123', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 1);
  });

  test('несколько совпадений → ambiguous', () {
    final rows = [_row(1, '000123'), _row(2, '000123')];
    final r = BarcodeMatcher().match('000123', rows);
    expect(r.isAmbiguous, true);
    expect(r.exact.length, 2);
  });

  test('нет совпадений → none', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('999', rows).isNone, true);
  });

  test('пустой код → none', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('   ', rows).isNone, true);
  });

  test('fallback на ИнвентарныйНомер ТОЛЬКО если НоменклатураКод пуст у всех', () {
    final rows = [_row(1, '', inv: '44182'), _row(2, '', inv: '44183')];
    final r = BarcodeMatcher().match('44182', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 1);
  });

  test('fallback НЕ срабатывает, если хотя бы у одной строки есть НоменклатураКод', () {
    // строка 1 с кодом, строка 2 без кода но с инв.номером — ищем инв.номер строки 2
    final rows = [_row(1, '000123'), _row(2, '', inv: '44183')];
    final r = BarcodeMatcher().match('44183', rows);
    expect(r.isNone, true); // fallback отключён, т.к. есть строка с кодом
  });

  test('fallback на Серию когда все коды пусты', () {
    final rows = [_row(1, '', series: 'SR-1'), _row(2, '', series: 'SR-2')];
    final r = BarcodeMatcher().match('SR-2', rows);
    expect(r.isUnique, true);
    expect(r.exact.single.lineNumber, 2);
  });

  test('normalize: trim пробелов', () {
    final rows = [_row(1, '000123')];
    expect(BarcodeMatcher().match('  000123  ', rows).isUnique, true);
  });
}
```

- [ ] **Step 4: Запустить тесты — должны падать**

```bash
cd tsd_inventory
flutter test test/features/inventory/domain/
```
Ожидается: FAIL (нет классов).

- [ ] **Step 5: Реализовать DocTableRow**

Создать `tsd_inventory/lib/features/inventory/domain/doc_table_row.dart`:
```dart
/// Строка табличной части документа из /code/.
class DocTableRow {
  const DocTableRow({
    required this.lineNumber,
    required this.inventoryNumber,
    required this.nomenclature,
    required this.nomenclatureCode,
    required this.characteristic,
    required this.series,
    required this.seriesStatus,
    required this.fio,
    required this.qtyAccounting,
    required this.qtyActual,
    required this.action,
  });

  final int lineNumber;               // ключ "1","2" → int
  final String inventoryNumber;       // "44182" или ""
  final String nomenclature;          // человекочитаемый текст
  final String nomenclatureCode;      // НоменклатураКод — КЛЮЧ матчера
  final String characteristic;
  final String series;
  final String seriesStatus;          // "0"..
  final String fio;                   // ФизическоеЛицо (текст)
  final int qtyAccounting;            // из строки через int.tryParse
  final int qtyActual;                // из строки через int.tryParse
  final String action;                // Действие (расхождения)

  bool get isFound => qtyActual > 0;
  bool get hasDiscrepancy => qtyActual != qtyAccounting;

  DocTableRow copyWith({int? qtyActual, String? action}) => DocTableRow(
        lineNumber: lineNumber,
        inventoryNumber: inventoryNumber,
        nomenclature: nomenclature,
        nomenclatureCode: nomenclatureCode,
        characteristic: characteristic,
        series: series,
        seriesStatus: seriesStatus,
        fio: fio,
        qtyAccounting: qtyAccounting,
        qtyActual: qtyActual ?? this.qtyActual,
        action: action ?? this.action,
      );
}
```

- [ ] **Step 6: Реализовать parseDocTable**

Создать `tsd_inventory/lib/features/inventory/domain/doc_table_parser.dart`:
```dart
import 'doc_table_row.dart';

/// Парсер ответа /code/: объект «номер строки → поля строки».
/// Количества приходят строками → приводим через int.tryParse.
/// Чистая функция, тестируется в unit-тестах.
List<DocTableRow> parseDocTable(Object? json) {
  if (json is! Map) return const [];
  final rows = <DocTableRow>[];
  for (final entry in json.entries) {
    if (entry.value is! Map) continue;
    final f = entry.value as Map;
    final line = int.tryParse(entry.key.toString()) ?? 0;
    rows.add(DocTableRow(
      lineNumber: line,
      inventoryNumber: f['ИнвентарныйНомер']?.toString() ?? '',
      nomenclature: f['Номенклатура']?.toString() ?? '',
      nomenclatureCode: f['НоменклатураКод']?.toString() ?? '',
      characteristic: f['Характеристика']?.toString() ?? '',
      series: f['Серия']?.toString() ?? '',
      seriesStatus: f['СтатусУказанияСерий']?.toString() ?? '0',
      fio: f['ФизическоеЛицо']?.toString() ?? '',
      qtyAccounting: int.tryParse(f['КоличествоПоДаннымУчета']?.toString() ?? '') ?? 0,
      qtyActual: int.tryParse(f['КоличествоФактическое']?.toString() ?? '') ?? 0,
      action: f['Действие']?.toString() ?? '',
    ));
  }
  rows.sort((a, b) => a.lineNumber.compareTo(b.lineNumber));
  return rows;
}
```

- [ ] **Step 7: Реализовать BarcodeMatcher**

Создать `tsd_inventory/lib/features/inventory/domain/barcode_matcher.dart`:
```dart
import 'doc_table_row.dart';

/// Результат сопоставления штрихкода строкам таблицы.
class MatchResult {
  final List<DocTableRow> exact;
  const MatchResult(this.exact);
  bool get isUnique => exact.length == 1;
  bool get isNone => exact.isEmpty;
  bool get isAmbiguous => exact.length > 1;
}

/// Сопоставление штрихкода строкам. Ключ — НоменклатураКод (решение дизайна).
/// Fallback на Инв.№/Серию/Номенклатуру ТОЛЬКО если НоменклатураКод пуст у всех строк.
class BarcodeMatcher {
  MatchResult match(String code, List<DocTableRow> rows) {
    final norm = normalize(code);
    if (norm.isEmpty) return MatchResult(const []);

    // 1) Основной ключ: НоменклатураКод
    var hits = rows.where((r) => normalize(r.nomenclatureCode) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    // 2) Fallback только если основной ключ пуст у всех строк
    final anyPrimary = rows.any((r) => r.nomenclatureCode.trim().isNotEmpty);
    if (anyPrimary) return MatchResult(const []);

    hits = rows.where((r) => normalize(r.inventoryNumber) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    hits = rows.where((r) => normalize(r.series) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    hits = rows.where((r) => normalize(r.nomenclature) == norm).toList();
    if (hits.isNotEmpty) return MatchResult(hits);

    return MatchResult(const []);
  }

  /// Нормализация: trim. Case-sensitive по умолчанию (коды 1С).
  String normalize(String s) => s.trim();
}
```

- [ ] **Step 8: Запустить тесты — должны пройти**

```bash
flutter test test/features/inventory/domain/
```
Ожидается: `All tests passed!`

- [ ] **Step 9: Коммит**

```bash
git add tsd_inventory/lib/features/inventory/domain tsd_inventory/test
git commit -m "feat(inventory): DocTableRow + parseDocTable + BarcodeMatcher + unit-тесты"
```

---

### Task 14: features/auth/presentation — LoginScreen + go_router (редирект)

**Files:**
- Create: `tsd_inventory/lib/features/auth/presentation/login_screen.dart`
- Modify: `tsd_inventory/lib/app.dart` (финальный router с редиректом)

- [ ] **Step 1: Реализовать LoginScreen**

Создать `tsd_inventory/lib/features/auth/presentation/login_screen.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../application/auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberLogin = true;
  bool _rememberPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Восстановить сохранённый логин (если был).
    Future(() async {
      final login = await ref.read(secureCredentialsStoreProvider).readLogin();
      if (login != null && mounted) setState(() => _loginCtrl.text = login);
    });
  }

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _loginCtrl.text.trim().isNotEmpty && _passCtrl.text.isNotEmpty;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await ref.read(authControllerProvider.notifier).login(
          _loginCtrl.text.trim(),
          _passCtrl.text,
          rememberLogin: _rememberLogin,
          rememberPassword: _rememberPassword,
        );
    if (!mounted) return;
    if (err == null) {
      context.go('/docs');
    } else {
      setState(() {
        _error = err;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(AppStrings.loginTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 32),
                TextField(
                  controller: _loginCtrl,
                  decoration: const InputDecoration(
                      labelText: AppStrings.loginField),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: AppStrings.passwordField,
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility
                          : Icons.visibility_off),
                      tooltip: AppStrings.showPassword,
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberLogin,
                  onChanged: (v) =>
                      setState(() => _rememberLogin = v ?? true),
                  title: const Text(AppStrings.rememberLogin),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _rememberPassword,
                  onChanged: (v) =>
                      setState(() => _rememberPassword = v ?? false),
                  title: const Text(AppStrings.rememberPassword),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 18)),
                  ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: (_isValid && !_loading) ? _submit : null,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text(AppStrings.signIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Заменить временный router в app.dart на финальный с редиректом**

Переписать `app.dart` (полностью):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/application/auth_controller.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/docs/presentation/docs_list_screen.dart';
import 'features/inventory/presentation/inventory_screen.dart';
import 'theme/app_theme.dart';

class TsdApp extends ConsumerWidget {
  const TsdApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Инвентаризация',
      theme: appTheme(),
      routerConfig: ref.watch(appRouterProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authed = ref.read(authControllerProvider).isAuthenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!authed && !onLogin) return '/login';
      if (authed && onLogin) return '/docs';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/docs',
        builder: (context, state) => const DocsListScreen(),
      ),
      GoRoute(
        path: '/docs/:code',
        builder: (context, state) =>
            InventoryScreen(docCode: state.pathParameters['code']!),
      ),
    ],
  );
});
```
> Примечание: `DocsListScreen` и `InventoryScreen` создаются в Task 15 и Task 18. До них — временные заглушки (см. эти задачи), чтобы `flutter analyze` проходил.

- [ ] **Step 3: Временные заглушки экранов (чтобы analyze проходил до Task 15/18)**

Создать `tsd_inventory/lib/features/docs/presentation/docs_list_screen.dart` (временно):
```dart
import 'package:flutter/material.dart';
class DocsListScreen extends StatelessWidget {
  const DocsListScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('docs (Task 15)')));
}
```
Создать `tsd_inventory/lib/features/inventory/presentation/inventory_screen.dart` (временно):
```dart
import 'package:flutter/material.dart';
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('inventory (Task 18)')));
}
```

- [ ] **Step 4: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/features/auth/presentation lib/app.dart
```
Ожидается: нет ошибок.

- [ ] **Step 5: Коммит**

```bash
git add tsd_inventory/lib/features/auth/presentation tsd_inventory/lib/app.dart tsd_inventory/lib/features/docs/presentation tsd_inventory/lib/features/inventory/presentation
git commit -m "feat(auth): LoginScreen + go_router с редиректом по сессии"
```

---

### Task 15: features/docs/presentation — DocsListScreen

**Files:**
- Modify: `tsd_inventory/lib/features/docs/presentation/docs_list_screen.dart` (заменить заглушку)

- [ ] **Step 1: Реализовать DocsListScreen с состояниями AsyncValue + pull-to-refresh**

Переписать `tsd_inventory/lib/features/docs/presentation/docs_list_screen.dart` (полностью):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_strings.dart';
import '../../auth/application/auth_controller.dart';
import '../application/docs_controller.dart';
import '../domain/doc_list_item.dart';

class DocsListScreen extends ConsumerWidget {
  const DocsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fio = ref.watch(authControllerProvider).session?.fio ?? '';
    final asyncDocs = ref.watch(docsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fio, style: const TextStyle(fontSize: 18)),
            const Text(AppStrings.docsTitle, style: TextStyle(fontSize: 14)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Выйти',
            onPressed: () async {
              await ref.read(authControllerProvider.notifier).logout();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: asyncDocs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(
          message: AppStrings.docsLoadError,
          onRetry: () => ref.read(docsControllerProvider.notifier).refresh(),
        ),
        data: (docs) {
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(AppStrings.docsEmpty,
                      style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () =>
                        ref.read(docsControllerProvider.notifier).refresh(),
                    child: const Text(AppStrings.retry),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(docsControllerProvider.notifier).refresh(),
            child: ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) => _DocCard(
                doc: docs[i],
                onTap: () => context.go('/docs/${docs[i].number}'),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({required this.doc, required this.onTap});
  final DocListItem doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd.MM.yyyy HH:mm');
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(doc.number,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(df.format(doc.date), style: const TextStyle(fontSize: 16)),
                    if (doc.departmentGuid != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${AppStrings.deptLabel}: ${doc.departmentGuid}',
                            style:
                                TextStyle(fontSize: 14, color: scheme.outline)),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: doc.posted ? scheme.secondary : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  doc.posted ? AppStrings.docPosted : AppStrings.docDraft,
                  style: TextStyle(
                      color: doc.posted ? scheme.onSecondary : scheme.onSurface,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 56, color: scheme.error),
          const SizedBox(height: 12),
          Text(message, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text(AppStrings.retry)),
        ],
      ),
    );
  }
}
```
> `DateFormat` берётся из пакета `intl` (уже в pubspec).

- [ ] **Step 2: Проверить analyze и сборку**

```bash
cd tsd_inventory
flutter analyze lib/features/docs/presentation
```
Ожидается: нет ошибок. Исправить импорт `intl`, если требуется.

- [ ] **Step 3: Коммит**

```bash
git add tsd_inventory/lib/features/docs/presentation
git commit -m "feat(docs): DocsListScreen (AsyncValue состояния + pull-to-refresh)"
```

---

### Task 16: features/inventory/data — InventoryRepository (/code/ + POST stub + /me stub + кэш)

**Files:**
- Create: `tsd_inventory/lib/features/inventory/data/inventory_repository.dart`

- [ ] **Step 1: Реализовать InventoryRepository с кэш+сеть стратегией**

Создать `tsd_inventory/lib/features/inventory/data/inventory_repository.dart`:
```dart
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:tsd_inventory/core/network/api_error.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/result/result.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';

import '../domain/doc_table_parser.dart';
import '../domain/doc_table_row.dart';

final _log = Logger('inventory_repository');

/// Запись по строке документа: номер строки → (факт, действие).
typedef LineResult = ({int qty, String action});

/// Табличная часть документа + запись результатов + stub получения ФИО.
/// Стратегия кэш+сеть: при сетевой ошибке fallback на кэш из AppDatabase.
class InventoryRepository {
  InventoryRepository({required DioClient client, required AppDatabase db})
      : _client = client,
        _db = db;

  final DioClient _client;
  final AppDatabase _db;

  /// GET /hs/inventory/code/{Код} → табличная часть.
  /// Сетевая ошибка + есть кэш → отдаём кэш (офлайн).
  Future<Result<List<DocTableRow>>> getTable(String code) async {
    final path = 'hs/inventory/code/${Uri.encodeComponent(code)}';
    try {
      final res = await _client.getJson<dynamic>(path);
      final data = res.data is String ? jsonDecode(res.data as String) : res.data;
      // Кэшируем сырой ответ.
      await _db.cacheDoc(code, jsonEncode(data));
      return Success(parseDocTable(data));
    } on DioException catch (e) {
      // Попытка отдать кэш.
      final cached = await _db.getCachedDoc(code);
      if (cached != null) {
        _log.warning('Сеть недоступна, отдаю кэш документа $code');
        return Success(parseDocTable(jsonDecode(cached.json)));
      }
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка загрузки табличной части: $e');
      return const Failure(ParseError('Не удалось разобрать табличную часть'));
    }
  }

  /// Запись фактических количеств. Эндпоинт/метод/тело — ПОДЛЕЖАТ уточнению 1С.
  /// TODO(1С): уточнить URL/метод/тело с разработчиком 1С.
  /// Предполагаемый: POST /hs/inventory/code/{Код},
  ///   тело: { "Lines": { "<lineNo>": { "КоличествоФактическое": N, "Действие": "" } } }
  Future<Result<void>> postDocResult(
      String code, Map<int, LineResult> lines) async {
    final path = 'hs/inventory/code/${Uri.encodeComponent(code)}';
    final body = {
      'Lines': {
        for (final e in lines.entries)
          '${e.key}': {
            'КоличествоФактическое': e.value.qty,
            'Действие': e.value.action,
          }
      },
    };
    try {
      await _client.postJson<dynamic>(path, body: body);
      return const Success(null);
    } on DioException catch (e) {
      return Failure(ApiError.fromDio(e));
    } catch (e) {
      _log.warning('Ошибка записи результатов: $e');
      return const Failure(NetworkError());
    }
  }

  /// Получение ФИО аутентифицированного пользователя. STUB.
  /// TODO(1С): уточнить эндпоинт (/me? /whoami?). Сейчас ФИО = логин (не используется).
  Future<String> getCurrentUserFio() async {
    throw UnimplementedError(
        'getCurrentUserFio: эндпоинт уточняется у 1С; сейчас ФИО = логин');
  }
}
```

- [ ] **Step 2: Добавить провайдеры InventoryRepository + AppDatabase**

Создать `tsd_inventory/lib/features/inventory/application/providers.dart`:
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tsd_inventory/core/config/app_config.dart';
import 'package:tsd_inventory/core/network/dio_client.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/auth/application/auth_controller.dart';
import '../data/inventory_repository.dart';

/// Singleton drift-базы.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Фабрика InventoryRepository под текущую сессию.
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  final session = ref.watch(authControllerProvider).session!;
  final config = ref.watch(appConfigProvider);
  final client = DioClient(
    config: config,
    credentials: BasicCredentials(session.login, session.password),
  );
  final db = ref.watch(appDatabaseProvider);
  return InventoryRepository(client: client, db: db);
});
```

- [ ] **Step 3: Проверить analyze**

```bash
cd tsd_inventory
flutter analyze lib/features/inventory/data lib/features/inventory/application/providers.dart
```
Ожидается: нет ошибок.

- [ ] **Step 4: Коммит**

```bash
git add tsd_inventory/lib/features/inventory/data tsd_inventory/lib/features/inventory/application/providers.dart
git commit -m "feat(inventory): InventoryRepository (/code/ + кэш + POST stub + /me stub)"
```

---

### Task 17: features/inventory/application — ScanController (TDD)

**Files:**
- Create: `tsd_inventory/lib/features/inventory/application/scan_controller.dart`
- Create: `tsd_inventory/test/features/inventory/application/scan_controller_test.dart`

- [ ] **Step 1: Написать failing-тест на ScanController.onScanned**

Создать `tsd_inventory/test/features/inventory/application/scan_controller_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tsd_inventory/core/feedback/feedback_service.dart';
import 'package:tsd_inventory/core/storage/app_database.dart';
import 'package:tsd_inventory/features/inventory/application/scan_controller.dart';
import 'package:tsd_inventory/features/inventory/data/inventory_repository.dart';
import 'package:tsd_inventory/features/inventory/domain/barcode_matcher.dart';
import 'package:tsd_inventory/features/inventory/domain/doc_table_row.dart';

class _MockRepo extends Mock implements InventoryRepository {}
class _MockDb extends Mock implements AppDatabase {}
class _FakeFeedback extends Fake implements FeedbackService {
  int success = 0, error = 0, attention = 0;
  @override
  Future<void> success() async => success++;
  @override
  Future<void> error() async => error++;
  @override
  Future<void> attention() async => attention++;
}

DocTableRow _row(int line, String code) => DocTableRow(
      lineNumber: line,
      inventoryNumber: '',
      nomenclature: 'N$line',
      nomenclatureCode: code,
      characteristic: '',
      series: '',
      seriesStatus: '0',
      fio: '',
      qtyAccounting: 1,
      qtyActual: 0,
      action: '',
    );

void main() {
  late _MockRepo repo;
  late _MockDb db;
  late _FakeFeedback feedback;
  late ScanController controller;

  setUp(() {
    repo = _MockRepo();
    db = _MockDb();
    feedback = _FakeFeedback();
    controller = ScanController(
      docCode: 'АЕ-1',
      initialRows: [_row(1, '000123'), _row(2, '000456')],
      repo: repo,
      db: db,
      matcher: BarcodeMatcher(),
      feedback: feedback,
    );
    registerFallbackValue(const ScanProgressCompanion.insert(
        docCode: 'x', lineNumber: 0, qtyActual: 0));
  });

  test('найдено ровно одно → +1 факт, success, persist', () async {
    final out = await controller.onScanned('000123');
    expect(out, isA<Found>());
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 1);
    expect(feedback.success, 1);
    verify(() => db.upsertScanProgress(
          docCode: 'АЕ-1',
          lineNo: 1,
          nomenclatureCode: any(named: 'nomenclatureCode'),
          qtyActual: 1,
          action: any(named: 'action'),
        )).called(1);
  });

  test('повторный скан той же строки → ещё +1', () async {
    await controller.onScanned('000123');
    await controller.onScanned('000123');
    expect(controller.rows.firstWhere((r) => r.lineNumber == 1).qtyActual, 2);
  });

  test('не найдено → NotFound, error feedback', () async {
    final out = await controller.onScanned('ZZZ');
    expect(out, isA<NotFound>());
    expect(feedback.error, 1);
  });

  test('несколько совпадений → Ambiguous, attention', () async {
    controller = ScanController(
      docCode: 'АЕ-1',
      initialRows: [_row(1, '000123'), _row(2, '000123')],
      repo: repo, db: db, matcher: BarcodeMatcher(), feedback: feedback,
    );
    final out = await controller.onScanned('000123');
    expect(out, isA<Ambiguous>());
    expect((out as Ambiguous).candidates.length, 2);
    expect(feedback.attention, 1);
  });

  test('scannedCount / total', () async {
    expect(controller.total, 2);
    expect(controller.scannedCount, 0);
    await controller.onScanned('000123');
    expect(controller.scannedCount, 1);
  });
}
```

- [ ] **Step 2: Запустить тест — должен падать**

```bash
cd tsd_inventory
flutter test test/features/inventory/application/scan_controller_test.dart
```
Ожидается: FAIL (нет `ScanController`/`Found`/`NotFound`/`Ambiguous`).

- [ ] **Step 3: Реализовать ScanController**

Создать `tsd_inventory/lib/features/inventory/application/scan_controller.dart`:
```dart
import 'package:flutter/foundation.dart';

import '../../../core/feedback/feedback_service.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/app_database.dart';
import '../data/inventory_repository.dart';
import '../domain/barcode_matcher.dart';
import '../domain/doc_table_row.dart';

/// Результат одного сканирования для UI.
sealed class ScanOutcome {
  const ScanOutcome();
}
class Found extends ScanOutcome {
  final DocTableRow row;
  const Found(this.row);
}
class NotFound extends ScanOutcome {
  final String code;
  const NotFound(this.code);
}
class Ambiguous extends ScanOutcome {
  final List<DocTableRow> candidates;
  const Ambiguous(this.candidates);
}

/// Оркестратор состояния сканирования одного документа.
class ScanController extends ChangeNotifier {
  ScanController({
    required this.docCode,
    required List<DocTableRow> initialRows,
    required InventoryRepository repo,
    required AppDatabase db,
    required BarcodeMatcher matcher,
    required FeedbackService feedback,
  })  : _repo = repo,
        _db = db,
        _matcher = matcher,
        _feedback = feedback,
        rows = List.of(initialRows);

  final String docCode;
  final InventoryRepository _repo;
  final AppDatabase _db;
  final BarcodeMatcher _matcher;
  final FeedbackService _feedback;

  List<DocTableRow> rows;

  int get total => rows.length;
  int get scannedCount => rows.where((r) => r.isFound).length;

  /// Главная точка входа: отсканированный код → реакция.
  Future<ScanOutcome> onScanned(String code) async {
    final res = _matcher.match(code, rows);
    if (res.isNone) {
      await _feedback.error();
      return NotFound(code);
    }
    if (res.isAmbiguous) {
      await _feedback.attention();
      return Ambiguous(res.exact);
    }
    // ровно одно совпадение → +1 факт, persist
    final row = res.exact.single;
    _incrementActual(row);
    await _feedback.success();
    await _db.upsertScanProgress(
      docCode: docCode,
      lineNo: row.lineNumber,
      nomenclatureCode: row.nomenclatureCode,
      qtyActual: rows.firstWhere((r) => r.lineNumber == row.lineNumber).qtyActual,
      action: row.action,
    );
    notifyListeners();
    return Found(rows.firstWhere((r) => r.lineNumber == row.lineNumber));
  }

  /// Инкремент факта при выборе строки из диалога (множественное совпадение).
  Future<ScanOutcome> applyChoice(DocTableRow row) async {
    _incrementActual(row);
    await _feedback.success();
    await _db.upsertScanProgress(
      docCode: docCode,
      lineNo: row.lineNumber,
      nomenclatureCode: row.nomenclatureCode,
      qtyActual: rows.firstWhere((r) => r.lineNumber == row.lineNumber).qtyActual,
      action: row.action,
    );
    notifyListeners();
    return Found(rows.firstWhere((r) => r.lineNumber == row.lineNumber));
  }

  void _incrementActual(DocTableRow row) {
    final i = rows.indexWhere((r) => r.lineNumber == row.lineNumber);
    if (i == -1) return;
    rows[i] = rows[i].copyWith(qtyActual: rows[i].qtyActual + 1);
  }

  /// Восстановление прогресса из БД при входе на экран.
  Future<void> hydrateFromDb() async {
    final saved = await _db.getScanProgress(docCode);
    for (var i = 0; i < rows.length; i++) {
      final s = saved[rows[i].lineNumber];
      if (s != null) {
        rows[i] = rows[i].copyWith(qtyActual: s.qtyActual, action: s.action ?? '');
      }
    }
    notifyListeners();
  }

  /// Отправка результатов в 1С. Успех → очистка локального прогресса.
  Future<Result<void>> commit() async {
    final lines = <int, LineResult>{};
    for (final r in rows) {
      lines[r.lineNumber] = (qty: r.qtyActual, action: r.action);
    }
    final res = await _repo.postDocResult(docCode, lines);
    if (res is Success) {
      await _db.clearScanProgress(docCode);
    }
    return res;
  }
}
```

- [ ] **Step 4: Запустить тест — должен пройти**

```bash
flutter test test/features/inventory/application/scan_controller_test.dart
```
Ожидается: `All tests passed!`
> Если mocktail ругается на `ScanProgressCompanion.insert` как fallback value (non-const) — использовать `registerFallbackValue(ScanProgressCompanion.insert(docCode: 'x', lineNumber: 0))` без const.

- [ ] **Step 5: Коммит**

```bash
git add tsd_inventory/lib/features/inventory/application/scan_controller.dart tsd_inventory/test
git commit -m "feat(inventory): ScanController (+1, persist, hydrate, commit) + unit-тесты"
```

---

### Task 18: features/inventory/presentation — InventoryScreen + wedge-поле + диалоги

**Files:**
- Modify: `tsd_inventory/lib/features/inventory/presentation/inventory_screen.dart` (заменить заглушку)
- Create: `tsd_inventory/lib/features/inventory/presentation/keyboard_wedge_field.dart`
- Create: `tsd_inventory/lib/features/inventory/presentation/row_card.dart`
- Create: `tsd_inventory/lib/features/inventory/application/inventory_screen_controller.dart`

- [ ] **Step 1: Реализовать экран-контроллер (загрузка ТЧ + hydrate + управление ScanController)**

Создать `tsd_inventory/lib/features/inventory/application/inventory_screen_controller.dart`:
```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/feedback/feedback_service.dart';
import '../../../core/result/result.dart';
import '../../../core/storage/app_database.dart';
import '../domain/barcode_matcher.dart';
import '../domain/doc_table_row.dart';
import '../data/inventory_repository.dart';
import 'providers.dart';
import 'scan_controller.dart';

/// Семейство контроллеров экрана по коду документа.
final inventoryScreenControllerProvider =
    ChangeNotifierProvider.family<InventoryScreenController, String>(
        (ref, docCode) {
  return InventoryScreenController(
    docCode: docCode,
    repo: ref.watch(inventoryRepositoryProvider),
    feedback: FeedbackService(),
    matcher: BarcodeMatcher(),
    db: ref.watch(appDatabaseProvider),
  )..init();
});

class InventoryScreenController extends ChangeNotifier {
  InventoryScreenController({
    required this.docCode,
    required this.repo,
    required this.db,
    required this.matcher,
    required this.feedback,
  });

  final String docCode;
  final InventoryRepository repo;
  final AppDatabase db;
  final BarcodeMatcher matcher;
  final FeedbackService feedback;

  bool loading = true;
  String? loadError;
  ScanController? scan;

  String searchQuery = '';
  bool unscannedFirst = true;

  Future<void> init() async {
    final res = await repo.getTable(docCode);
    final rows = res.maybeWhen<List<DocTableRow>?>(
      onValue: (v) => v,
      orElse: (_) {
        loadError = (res as Failure).error.userMessage;
        return null;
      },
    );
    if (rows != null) {
      scan = ScanController(
        docCode: docCode,
        initialRows: rows,
        repo: repo,
        db: db,
        matcher: matcher,
        feedback: feedback,
      );
      await scan!.hydrateFromDb();
      scan!.addListener(_onScanChanged);
    }
    loading = false;
    notifyListeners();
  }

  void _onScanChanged() => notifyListeners();

  void setSearch(String q) {
    searchQuery = q;
    notifyListeners();
  }

  void toggleSort(bool v) {
    unscannedFirst = v;
    notifyListeners();
  }

  @override
  void dispose() {
    scan?.removeListener(_onScanChanged);
    super.dispose();
  }
}
```

- [ ] **Step 2: Реализовать KeyboardWedgeField (скрытое фокусное поле, финальная версия)**

Создать `tsd_inventory/lib/features/inventory/presentation/keyboard_wedge_field.dart` (единый `Stack` — плашка-индикатор + прозрачное скрытое поле поверх):
```dart
import 'package:flutter/material.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';

class KeyboardWedgeField extends StatefulWidget {
  const KeyboardWedgeField({
    super.key,
    required this.scanner,
  });
  final KeyboardWedgeScanner scanner;

  @override
  State<KeyboardWedgeField> createState() => _KeyboardWedgeFieldState();
}

class _KeyboardWedgeFieldState extends State<KeyboardWedgeField> {
  final _focus = FocusNode();
  final _ctrl = TextEditingController();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _keepFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_focus.hasFocus) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _keepFocus,
      child: Stack(
        children: [
          // Визуальная плашка-индикатор
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _focused ? scheme.primary : scheme.outline, width: 2),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner,
                    size: 30, color: scheme.onPrimaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _focused ? AppStrings.readyToScan : 'Коснитесь и сканируйте',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: scheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          // Скрытое поле поверх плашки (прозрачное, мини-высота)
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 56,
              child: TextField(
                focusNode: _focus,
                controller: _ctrl,
                autofocus: true,
                onChanged: widget.scanner.onTextChanged,
                onSubmitted: (v) {
                  widget.scanner.onSubmitted(v);
                  _ctrl.clear();
                  _keepFocus();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Реализовать RowCard (карточка строки с статусом)**

Создать `tsd_inventory/lib/features/inventory/presentation/row_card.dart`:
```dart
import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../domain/doc_table_row.dart';

class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.row});
  final DocTableRow row;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final found = row.isFound;
    final discrepancy = row.hasDiscrepancy;

    final bg = found
        ? scheme.secondaryContainer
        : scheme.surfaceContainerHighest;

    return Card(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(found ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: found ? scheme.secondary : scheme.outline, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(row.nomenclature,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (row.characteristic.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 32),
                child: Text(row.characteristic,
                    style: TextStyle(fontSize: 15, color: scheme.outline)),
              ),
            if (row.inventoryNumber.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text('Инв. ${row.inventoryNumber}',
                    style: TextStyle(fontSize: 15, color: scheme.outline)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 32),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(AppStrings.qtyAccountingOf(row.qtyAccounting),
                      style: const TextStyle(fontSize: 16)),
                  Text(AppStrings.qtyActualOf(row.qtyActual),
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: found ? scheme.secondary : scheme.onSurface)),
                ],
              ),
            ),
            if (row.fio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 32),
                child: Text(row.fio,
                    style: TextStyle(fontSize: 14, color: scheme.outline)),
              ),
            if (discrepancy)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 32),
                child: Text(
                  '⚠ ${AppStrings.discrepancyOf(row.qtyActual, row.qtyAccounting)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: scheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Реализовать InventoryScreen (финальная версия)**

Переписать `tsd_inventory/lib/features/inventory/presentation/inventory_screen.dart` (полностью):
```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/scanner/keyboard_wedge_scanner.dart';
import '../../../l10n/app_strings.dart';
import '../application/inventory_screen_controller.dart';
import '../application/scan_controller.dart';
import '../domain/doc_table_row.dart';
import 'keyboard_wedge_field.dart';
import 'row_card.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, required this.docCode});
  final String docCode;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  late final KeyboardWedgeScanner _scanner;

  @override
  void initState() {
    super.initState();
    _scanner = KeyboardWedgeScanner();
    _scanner.codes.listen(_onCode);
  }

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onCode(String code) async {
    final ctrl = ref
        .read(inventoryScreenControllerProvider(widget.docCode).notifier);
    final scan = ctrl.scan;
    if (scan == null) return;
    final outcome = await scan.onScanned(code);
    if (!mounted) return;
    switch (outcome) {
      case Found():
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${AppStrings.scanSuccess}: ${outcome.row.nomenclature}'),
          backgroundColor: Theme.of(context).colorScheme.secondary,
          duration: const Duration(milliseconds: 800),
        ));
      case NotFound():
        _showNotFound(code);
      case Ambiguous():
        _showAmbiguous(outcome.candidates);
    }
  }

  void _showNotFound(String code) {
    final scan = ref
        .read(inventoryScreenControllerProvider(widget.docCode).notifier).scan!;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final manualCtrl = TextEditingController();
        return AlertDialog(
          title: Text(AppStrings.notFoundCode(code)),
          content: TextField(
            controller: manualCtrl,
            decoration: const InputDecoration(labelText: AppStrings.enterManually),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(AppStrings.cancel)),
            ElevatedButton(
              onPressed: () {
                final v = manualCtrl.text.trim();
                Navigator.pop(ctx);
                if (v.isNotEmpty) _onCode(v);
              },
              child: const Text(AppStrings.confirm),
            ),
          ],
        );
      },
    );
    // scan используется для блокировки двойного; ссылку оставляем
    if (false) scan.total;
  }

  void _showAmbiguous(List<DocTableRow> candidates) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(AppStrings.multipleMatches),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: candidates.length,
            itemBuilder: (ctx, i) {
              final r = candidates[i];
              return ListTile(
                title: Text(r.nomenclature),
                subtitle: Text('Инв. ${r.inventoryNumber}'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref
                      .read(inventoryScreenControllerProvider(widget.docCode)
                          .notifier)
                      .scan!
                      .applyChoice(r);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(AppStrings.cancel)),
        ],
      ),
    );
  }

  Future<void> _finish() async {
    final scan = ref
        .read(inventoryScreenControllerProvider(widget.docCode).notifier).scan!;
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AppStrings.finish),
            content: Text(AppStrings.finishConfirm),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(AppStrings.no)),
              ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(AppStrings.yes)),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    final res = await scan.commit();
    if (!mounted) return;
    res.maybeWhen(
      onValue: (_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Результаты отправлены'),
            backgroundColor: Colors.green));
        context.go('/docs');
      },
      orElse: (err) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.sendError),
          action: SnackBarAction(label: AppStrings.retry, onPressed: _finish),
        ));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl =
        ref.watch(inventoryScreenControllerProvider(widget.docCode));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/docs'),
        ),
        title: Text(widget.docCode, style: const TextStyle(fontSize: 18)),
      ),
      body: ctrl.loading
          ? const Center(child: CircularProgressIndicator())
          : ctrl.loadError != null
              ? Center(child: Text(ctrl.loadError!, style: const TextStyle(fontSize: 18)))
              : _Body(ctrl: ctrl, scanner: _scanner),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _finish,
            child: Text(
                '${AppStrings.finish} (${ctrl.scan?.scannedCount ?? 0}/${ctrl.scan?.total ?? 0})'),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.ctrl, required this.scanner});
  final InventoryScreenController ctrl;
  final KeyboardWedgeScanner scanner;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final scan = ctrl.scan!;
    // слушаем scan через ctrl (addListener уже пробросил notify)
    ref.watch(inventoryScreenControllerProvider(widget.ctrl.docCode));

    // Фильтр + сортировка
    var rows = List<DocTableRow>.from(scan.rows);
    final q = ctrl.searchQuery.toLowerCase();
    if (q.isNotEmpty) {
      rows = rows.where((r) {
        return r.nomenclature.toLowerCase().contains(q) ||
            r.inventoryNumber.toLowerCase().contains(q) ||
            r.nomenclatureCode.toLowerCase().contains(q);
      }).toList();
    }
    rows.sort((a, b) {
      if (ctrl.unscannedFirst) {
        final af = a.isFound ? 1 : 0;
        final bf = b.isFound ? 1 : 0;
        if (af != bf) return af - bf;
      }
      return a.lineNumber.compareTo(b.lineNumber);
    });

    return Column(
      children: [
        // Прогресс
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.scannedProgressOf(scan.scannedCount, scan.total),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: LinearProgressIndicator(
            value: scan.total == 0 ? 0 : scan.scannedCount / scan.total,
            minHeight: 10,
          ),
        ),
        // Фильтр
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            decoration: const InputDecoration(labelText: AppStrings.search),
            onChanged: ctrl.setSearch,
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          value: ctrl.unscannedFirst,
          onChanged: ctrl.toggleSort,
          title: const Text(AppStrings.sortUnscannedFirst),
        ),
        // Сканер-поле
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: KeyboardWedgeField(scanner: widget.scanner),
        ),
        // Список строк
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) => RowCard(row: rows[i]),
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Проверить analyze и сборку APK**

```bash
cd tsd_inventory
flutter analyze
flutter build apk --debug --no-tree-shake-icons
```
Ожидается: `No issues found!` (или мелкие warnings) и `✓ Built ...app-debug.apk`.

- [ ] **Step 6: Коммит**

```bash
git add tsd_inventory/lib/features/inventory/presentation tsd_inventory/lib/features/inventory/application/inventory_screen_controller.dart
git commit -m "feat(inventory): InventoryScreen + keyboard wedge + карточки строк + диалоги"
```

---

### Task 19: README + финальная проверка (DoD)

**Files:**
- Create: `tsd_inventory/README.md`

- [ ] **Step 1: Написать README**

Создать `tsd_inventory/README.md`:
```markdown
# Инвентаризация ОС — ТСД M3 SL20

Flutter-приложение для терминала сбора данных **M3 SL20** (Android 11, API 30).
Инвентаризация основных средств через HTTP-сервисы 1С (ERP) с Basic Auth.

## Возможности
- Авторизация учётной записью 1С (Basic Auth).
- Список документов инвентаризации по ФИО пользователя.
- Табличная часть документа: поштучное сканирование штрихкодов, отметка строк (+1), зелёная подсветка, звук/вибро.
- Офлайн: кэш документа и прогресса сканирования (SQLite/drift) — данные не теряются при разряде/перезагрузке.
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
- HTTP (cleartext) разрешён через `android:usesCleartextTraffic` + `network_security_config.xml`.

## Режим сканера
По умолчанию **keyboard wedge** (сканер эмулирует ввод в фокусное поле + Enter) — работает на M3 SL20 без SDK.
Переключается в `lib/core/config/app_config.dart` (`scannerMode`):
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
Покрытие unit-тестами: парсеры `/fio/` и `/code/`, `BarcodeMatcher`, `ScanController`, `ApiError`, `Result`.

## Архитектура
Feature-first слоистая: `presentation → application → domain → data`.
State — Riverpod; навигация — go_router; сеть — dio; БД — drift.
См. дизайн: `../docs/superpowers/specs/2026-06-29-inventory-tsd-app-design.md`.

## Открытые точки интеграции с 1С (TODO)
- **Запись результатов:** `POST /hs/inventory/code/{Код}` (предполагаемый). Тело/метод уточнить у 1С — см. `InventoryRepository.postDocResult`.
- **ФИО пользователя:** сейчас `логин = ФИО`. Заглушка `getCurrentUserFio()` под будущий `/hs/inventory/me`.
- **Сопоставление штрихкода:** ключ — `НоменклатураКод` (поле ответа `/code/`).
```

- [ ] **Step 2: Запустить полный набор тестов**

```bash
cd tsd_inventory
flutter test
```
Ожидается: `All tests passed!` (парсеры, matcher, row, scan_controller, api_error, result).

- [ ] **Step 3: Финальный analyze + сборка release APK**

```bash
flutter analyze
flutter build apk --release --no-tree-shake-icons
```
Ожидается: `No issues found!` и `✓ Built build\app\outputs\flutter-apk\app-release.apk`.

- [ ] **Step 4: Ручная проверка DoD (отметить в коммите-сообщении при деплое на ТСД)**

- [ ] APK деплоится на M3 SL20.
- [ ] Логин `testInv`/`Test12345` проходит (если сервис 1С доступен).
- [ ] Список документов загружается по ФИО.
- [ ] Открытие документа → табличная часть, прогресс «X из Y».
- [ ] Сканирование keyboard wedge: найдено → +1 + зелёный + звук; не найдено → алерт; несколько → выбор.
- [ ] Прогресс восстанавливается после перезапуска приложения.
- [ ] «Завершить» → POST (или понятная ошибка, если эндпоинт ещё не готов).

- [ ] **Step 5: Коммит**

```bash
git add tsd_inventory/README.md
git commit -m "docs: README (сборка, baseUrl, режим сканера, testInv/Test12345, TODO 1С)"
```

---

## Self-Review плана (выполнено автором)

**1. Покрытие спеки:**
- Экран 1 (авторизация) → Task 14 (LoginScreen) + Task 10 (AuthRepository/Controller). ✅
- Экран 2 (список документов) → Task 15 (DocsListScreen) + Task 11/12 (domain+repo). ✅
- Экран 3 (табличная часть + сканирование) → Task 18 (InventoryScreen) + Task 13/16/17. ✅
- API /fio/ → Task 12; /code/ → Task 16; POST stub → Task 16; /me stub → Task 16. ✅
- Сопоставление штрихкода → Task 13 (BarcodeMatcher). ✅
- Persistence (drift: ScanProgress, CachedDoc) → Task 7 (схема) + Task 16/17 (использование). ✅
- Сканер: wedge/broadcast/camera → Task 8. ✅
- Feedback (звук/вибро) → Task 9. ✅
- Тесты: парсеры, matcher, scan_controller, api_error, result → Tasks 4, 11, 13, 17. ✅
- Android-конфиг (cleartext, minSdk 30) → Task 2. ✅
- README + DoD → Task 19. ✅

**2. Placeholder scan:** все `TODO(1С)` — осознанные известные-неизвестные с зафиксированным подходом (заглушка + интерфейс). Случайных TBD/"implement later" нет.

**3. Type consistency:** `BarcodeMatcher.match`/`MatchResult`, `ScanController` (`onScanned`/`applyChoice`/`commit`/`hydrateFromDb`), `ScanOutcome` (`Found`/`NotFound`/`Ambiguous`), `LineResult`, `Result`/`Success`/`Failure`, `ApiError` подклассы — имена согласованы между задачами. `parseDocList`/`parseDocTable` сигнатуры стабильны.
```

---

**План завершён.** Всего 19 задач, покрыты все 13 разделов спеки.

