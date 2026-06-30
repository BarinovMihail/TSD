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
  static const search = 'Поиск…';
  static const sortUnscannedFirst = 'Сначала неотсканированные';
  static const readyToScan = 'ГОТОВ К СКАНИРОВАНИЮ';
  static const scanByCamera = 'Сканировать камерой';
  static const finish = 'Завершить';
  static const found = 'найдено';
  static const multipleMatches = 'Несколько совпадений. Выберите строку:';
  static const enterManually = 'Ввести код вручную';
  static const scanSuccess = 'Найдено';
  static const finishConfirm = 'Завершить инвентаризацию и отправить результаты?';
  static const sendError = 'Не удалось отправить. Сохранено локально. Повторить?';
  static const noOfflineCopy = 'Нет сохранённой копии документа и нет связи с сервером';
  static const accounting = 'Кол-во по учёту';
  static const actual = 'Кол-во факт.';

  // Методы-фабрики для параметризованных строк
  static String scannedProgressOf(int count, int total) =>
      'Отсканировано: $count из $total';
  static String qtyAccountingOf(int n) => 'Учёт: $n';
  static String qtyActualOf(int n) => 'Факт: $n';
  static String discrepancyOf(int actual, int accounting) =>
      'расхождение: факт $actual, учёт $accounting';
  static String notFoundCode(String code) => 'Штрихкод $code не найден в документе';
  static String errServerCode(int code) => 'Ошибка сервера. Код: $code';
}
