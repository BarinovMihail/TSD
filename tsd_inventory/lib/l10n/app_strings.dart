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
  static const loginTitle = 'Инвентаризация ТМЦ';
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
  // Недоступность удалённой базы ERP при логине → выбор локальной базы.
  static const errRemoteUnreachableTitle = 'Нет связи с удалённой базой ERP';
  static const errRemoteUnreachableBody =
      'Удалённая база ERP недоступна. Подключиться к локальной базе (ERP_Local)?';
  static const useLocalBase = 'Подключиться к ERP_Local';
  static const retryRemote = 'Повторить';

  // Список документов
  static const docsTitle = 'Документы инвентаризации';
  static const docsEmpty = 'Документов не найдено';
  static const docsEmptyHint = 'Новые документы появятся здесь';
  static const refreshDocs = 'Обновить список';
  static const docsLoadError = 'Ошибка загрузки документов';
  static const searchDocument = 'Поиск по номеру документа';
  static const clearSearch = 'Очистить поиск';
  static const newestFirst = 'Сначала новые';
  static const oldestFirst = 'Сначала старые';
  static const docsSearchEmpty = 'Документы не найдены';
  static const docPosted = 'Проведён';
  static const docDraft = 'Черновик';
  static const orgLabel = 'Организация';
  static const deptLabel = 'Подразделение';
  static const linesCount = 'строк';

  // Табличная часть
  static const search = 'Поиск…';
  static const sortUnscannedFirst = 'Неотсканированные ↑';
  static const onlyWithoutBarcode = 'Без ШК';
  static const readyToScan = 'ГОТОВ К СКАНИРОВАНИЮ';
  static const scanByCamera = 'Сканировать камерой';
  static const finish = 'Завершить';
  static const found = 'найдено';
  static const multipleMatches = 'Несколько совпадений. Выберите строку:';
  static const enterManually = 'Ввести код вручную';
  static const scanSuccess = 'Найдено';
  static const finishConfirm =
      'Завершить инвентаризацию и отправить результаты?';
  static const sendError =
      'Не удалось отправить. Сохранено локально. Повторить?';
  static const noOfflineCopy =
      'Нет сохранённой копии документа и нет связи с сервером';
  static const accounting = 'Кол-во по учёту';
  static const actual = 'Кол-во факт.';

  // Методы-фабрики для параметризованных строк
  static String scannedProgressOf(int count, int total) =>
      'Отсканировано: $count из $total';
  static String qtyAccountingOf(int n) => 'Учёт: $n';
  static String qtyActualOf(int n) => 'Факт: $n';
  static String discrepancyOf(int actual, int accounting) =>
      'расхождение: факт $actual, учёт $accounting';
  static String notFoundCode(String code) =>
      'Штрихкод $code не найден в документе';
  static String errServerCode(int code) => 'Ошибка сервера. Код: $code';

  // Контроль версий / автообновление
  static String updateAvailableTitle(String version) =>
      'Доступна новая версия $version';
  static const updateNow = 'Обновить';
  static const updateLater = 'Позже';
  static const skipUpdate = 'Пропустить';
  static const downloadingUpdate = 'Скачивание обновления…';
  static String updatePercent(int p) => '$p%';
  static const updateDownloadError = 'Не удалось скачать обновление';
  static const updateInstallError = 'Не удалось запустить установку';
  static const updateInstallingReady =
      'Подтвердите установку в системном диалоге';

  // Сканирование: сообщения по штрихкоду
  static const barcodeNotFoundInDoc = 'Штрихкод не найден в текущем документе';

  // Добавление / просмотр штрихкодов позиции
  static const addBarcodeTitle = 'Добавление штрихкода';
  static const viewBarcodesTitle = 'Штрихкоды позиции';
  static const addBarcode = 'Добавить штрихкод';
  static const barcodeAddedSuccess = 'Штрихкод успешно добавлен';
  static const barcodeDeletedSuccess = 'Штрихкод успешно удалён';
  static const addNewBarcode = 'Добавить новый штрихкод';
  static const scanBarcodeFromItem = 'Сканировать ШК номенклатуры';
  static const scanBarcodeTitle = 'Сканирование штрихкода';
  static const scanBarcodePrompt = 'Отсканируйте штрихкод на товаре';
  static const close = 'Закрыть';
  static const characteristicLabel = 'Характеристика';
  static const withoutCharacteristic = 'Без характеристики';
  static const loadingCharacteristics = 'Загрузка характеристик…';
  static const addingBarcode = 'Добавление…';
  static const barcodeSentReloadFailed =
      'Штрихкод отправлен в 1С, но данные документа не удалось обновить';
  static const noBarcodesYet = 'У позиции пока нет штрихкодов';
  static const checkingBarcodeAfterTimeout =
      'Нет ответа 1С. Проверяю, записан ли штрихкод…';
  static const barcodeAlreadyAssignedTitle = 'Штрихкод уже используется';
  static const barcodeAlreadyAssignedHere =
      'Штрихкод уже привязан к этой позиции';
  static const barcodeAssignmentCheckFailed =
      'Не удалось проверить, используется ли штрихкод';
  static const transferBarcode = 'Перенести';
  static String barcodeTransferConfirm({
    required String barcode,
    required String currentNomenclature,
    required String currentCharacteristic,
    required String newNomenclature,
    required String newCharacteristic,
  }) {
    String position(String nomenclature, String characteristic) =>
        '$nomenclature\nХарактеристика: '
        '${characteristic.isEmpty ? withoutCharacteristic : characteristic}';

    return 'Штрихкод $barcode уже привязан к позиции:\n'
        '${position(currentNomenclature, currentCharacteristic)}\n\n'
        'При продолжении он будет удалён у этой позиции и привязан к:\n'
        '${position(newNomenclature, newCharacteristic)}\n\n'
        'Перенести штрихкод?';
  }
  static const deleteBarcodeTitle = 'Удаление штрихкода';
  static String deleteBarcodeConfirm(String barcode) =>
      'Удалить штрихкод $barcode?';
  static const deleteBarcode = 'Удалить';
  static String deleteBarcodeTooltip(String barcode) =>
      'Удалить штрихкод $barcode';
  static const deleteBarcodeInconclusive =
      'Не удалось подтвердить удаление штрихкода';

  // Снятие факта сканирования (долгое нажатие на отсканированной позиции)
  static const unscanTitle = 'Управление фактом';
  static const unscanDecrement = 'Убрать единицу (−1)';
  static const unscanReset = 'Сбросить факт (=0)';
}
