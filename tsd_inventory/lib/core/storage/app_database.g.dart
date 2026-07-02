// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ScanProgressTable extends ScanProgress
    with TableInfo<$ScanProgressTable, ScanProgressData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ScanProgressTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _docCodeMeta = const VerificationMeta(
    'docCode',
  );
  @override
  late final GeneratedColumn<String> docCode = GeneratedColumn<String>(
    'doc_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lineNumberMeta = const VerificationMeta(
    'lineNumber',
  );
  @override
  late final GeneratedColumn<int> lineNumber = GeneratedColumn<int>(
    'line_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nomenclatureCodeMeta = const VerificationMeta(
    'nomenclatureCode',
  );
  @override
  late final GeneratedColumn<String> nomenclatureCode = GeneratedColumn<String>(
    'nomenclature_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qtyActualMeta = const VerificationMeta(
    'qtyActual',
  );
  @override
  late final GeneratedColumn<int> qtyActual = GeneratedColumn<int>(
    'qty_actual',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    docCode,
    lineNumber,
    nomenclatureCode,
    qtyActual,
    action,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'scan_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<ScanProgressData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('doc_code')) {
      context.handle(
        _docCodeMeta,
        docCode.isAcceptableOrUnknown(data['doc_code']!, _docCodeMeta),
      );
    } else if (isInserting) {
      context.missing(_docCodeMeta);
    }
    if (data.containsKey('line_number')) {
      context.handle(
        _lineNumberMeta,
        lineNumber.isAcceptableOrUnknown(data['line_number']!, _lineNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_lineNumberMeta);
    }
    if (data.containsKey('nomenclature_code')) {
      context.handle(
        _nomenclatureCodeMeta,
        nomenclatureCode.isAcceptableOrUnknown(
          data['nomenclature_code']!,
          _nomenclatureCodeMeta,
        ),
      );
    }
    if (data.containsKey('qty_actual')) {
      context.handle(
        _qtyActualMeta,
        qtyActual.isAcceptableOrUnknown(data['qty_actual']!, _qtyActualMeta),
      );
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {docCode, lineNumber};
  @override
  ScanProgressData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ScanProgressData(
      docCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}doc_code'],
      )!,
      lineNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}line_number'],
      )!,
      nomenclatureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nomenclature_code'],
      ),
      qtyActual: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}qty_actual'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ScanProgressTable createAlias(String alias) {
    return $ScanProgressTable(attachedDatabase, alias);
  }
}

class ScanProgressData extends DataClass
    implements Insertable<ScanProgressData> {
  final String docCode;
  final int lineNumber;
  final String? nomenclatureCode;
  final int qtyActual;
  final String? action;
  final DateTime updatedAt;
  const ScanProgressData({
    required this.docCode,
    required this.lineNumber,
    this.nomenclatureCode,
    required this.qtyActual,
    this.action,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['doc_code'] = Variable<String>(docCode);
    map['line_number'] = Variable<int>(lineNumber);
    if (!nullToAbsent || nomenclatureCode != null) {
      map['nomenclature_code'] = Variable<String>(nomenclatureCode);
    }
    map['qty_actual'] = Variable<int>(qtyActual);
    if (!nullToAbsent || action != null) {
      map['action'] = Variable<String>(action);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ScanProgressCompanion toCompanion(bool nullToAbsent) {
    return ScanProgressCompanion(
      docCode: Value(docCode),
      lineNumber: Value(lineNumber),
      nomenclatureCode: nomenclatureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(nomenclatureCode),
      qtyActual: Value(qtyActual),
      action: action == null && nullToAbsent
          ? const Value.absent()
          : Value(action),
      updatedAt: Value(updatedAt),
    );
  }

  factory ScanProgressData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ScanProgressData(
      docCode: serializer.fromJson<String>(json['docCode']),
      lineNumber: serializer.fromJson<int>(json['lineNumber']),
      nomenclatureCode: serializer.fromJson<String?>(json['nomenclatureCode']),
      qtyActual: serializer.fromJson<int>(json['qtyActual']),
      action: serializer.fromJson<String?>(json['action']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'docCode': serializer.toJson<String>(docCode),
      'lineNumber': serializer.toJson<int>(lineNumber),
      'nomenclatureCode': serializer.toJson<String?>(nomenclatureCode),
      'qtyActual': serializer.toJson<int>(qtyActual),
      'action': serializer.toJson<String?>(action),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ScanProgressData copyWith({
    String? docCode,
    int? lineNumber,
    Value<String?> nomenclatureCode = const Value.absent(),
    int? qtyActual,
    Value<String?> action = const Value.absent(),
    DateTime? updatedAt,
  }) => ScanProgressData(
    docCode: docCode ?? this.docCode,
    lineNumber: lineNumber ?? this.lineNumber,
    nomenclatureCode: nomenclatureCode.present
        ? nomenclatureCode.value
        : this.nomenclatureCode,
    qtyActual: qtyActual ?? this.qtyActual,
    action: action.present ? action.value : this.action,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ScanProgressData copyWithCompanion(ScanProgressCompanion data) {
    return ScanProgressData(
      docCode: data.docCode.present ? data.docCode.value : this.docCode,
      lineNumber: data.lineNumber.present
          ? data.lineNumber.value
          : this.lineNumber,
      nomenclatureCode: data.nomenclatureCode.present
          ? data.nomenclatureCode.value
          : this.nomenclatureCode,
      qtyActual: data.qtyActual.present ? data.qtyActual.value : this.qtyActual,
      action: data.action.present ? data.action.value : this.action,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ScanProgressData(')
          ..write('docCode: $docCode, ')
          ..write('lineNumber: $lineNumber, ')
          ..write('nomenclatureCode: $nomenclatureCode, ')
          ..write('qtyActual: $qtyActual, ')
          ..write('action: $action, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    docCode,
    lineNumber,
    nomenclatureCode,
    qtyActual,
    action,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ScanProgressData &&
          other.docCode == this.docCode &&
          other.lineNumber == this.lineNumber &&
          other.nomenclatureCode == this.nomenclatureCode &&
          other.qtyActual == this.qtyActual &&
          other.action == this.action &&
          other.updatedAt == this.updatedAt);
}

class ScanProgressCompanion extends UpdateCompanion<ScanProgressData> {
  final Value<String> docCode;
  final Value<int> lineNumber;
  final Value<String?> nomenclatureCode;
  final Value<int> qtyActual;
  final Value<String?> action;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ScanProgressCompanion({
    this.docCode = const Value.absent(),
    this.lineNumber = const Value.absent(),
    this.nomenclatureCode = const Value.absent(),
    this.qtyActual = const Value.absent(),
    this.action = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ScanProgressCompanion.insert({
    required String docCode,
    required int lineNumber,
    this.nomenclatureCode = const Value.absent(),
    this.qtyActual = const Value.absent(),
    this.action = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : docCode = Value(docCode),
       lineNumber = Value(lineNumber);
  static Insertable<ScanProgressData> custom({
    Expression<String>? docCode,
    Expression<int>? lineNumber,
    Expression<String>? nomenclatureCode,
    Expression<int>? qtyActual,
    Expression<String>? action,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (docCode != null) 'doc_code': docCode,
      if (lineNumber != null) 'line_number': lineNumber,
      if (nomenclatureCode != null) 'nomenclature_code': nomenclatureCode,
      if (qtyActual != null) 'qty_actual': qtyActual,
      if (action != null) 'action': action,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ScanProgressCompanion copyWith({
    Value<String>? docCode,
    Value<int>? lineNumber,
    Value<String?>? nomenclatureCode,
    Value<int>? qtyActual,
    Value<String?>? action,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ScanProgressCompanion(
      docCode: docCode ?? this.docCode,
      lineNumber: lineNumber ?? this.lineNumber,
      nomenclatureCode: nomenclatureCode ?? this.nomenclatureCode,
      qtyActual: qtyActual ?? this.qtyActual,
      action: action ?? this.action,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (docCode.present) {
      map['doc_code'] = Variable<String>(docCode.value);
    }
    if (lineNumber.present) {
      map['line_number'] = Variable<int>(lineNumber.value);
    }
    if (nomenclatureCode.present) {
      map['nomenclature_code'] = Variable<String>(nomenclatureCode.value);
    }
    if (qtyActual.present) {
      map['qty_actual'] = Variable<int>(qtyActual.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ScanProgressCompanion(')
          ..write('docCode: $docCode, ')
          ..write('lineNumber: $lineNumber, ')
          ..write('nomenclatureCode: $nomenclatureCode, ')
          ..write('qtyActual: $qtyActual, ')
          ..write('action: $action, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedDocTable extends CachedDoc
    with TableInfo<$CachedDocTable, CachedDocData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedDocTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
    'json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [code, json, fetchedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_doc';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedDocData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CachedDocData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedDocData(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $CachedDocTable createAlias(String alias) {
    return $CachedDocTable(attachedDatabase, alias);
  }
}

class CachedDocData extends DataClass implements Insertable<CachedDocData> {
  final String code;
  final String json;
  final DateTime fetchedAt;
  const CachedDocData({
    required this.code,
    required this.json,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['json'] = Variable<String>(json);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  CachedDocCompanion toCompanion(bool nullToAbsent) {
    return CachedDocCompanion(
      code: Value(code),
      json: Value(json),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory CachedDocData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedDocData(
      code: serializer.fromJson<String>(json['code']),
      json: serializer.fromJson<String>(json['json']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'json': serializer.toJson<String>(json),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  CachedDocData copyWith({String? code, String? json, DateTime? fetchedAt}) =>
      CachedDocData(
        code: code ?? this.code,
        json: json ?? this.json,
        fetchedAt: fetchedAt ?? this.fetchedAt,
      );
  CachedDocData copyWithCompanion(CachedDocCompanion data) {
    return CachedDocData(
      code: data.code.present ? data.code.value : this.code,
      json: data.json.present ? data.json.value : this.json,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocData(')
          ..write('code: $code, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, json, fetchedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedDocData &&
          other.code == this.code &&
          other.json == this.json &&
          other.fetchedAt == this.fetchedAt);
}

class CachedDocCompanion extends UpdateCompanion<CachedDocData> {
  final Value<String> code;
  final Value<String> json;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const CachedDocCompanion({
    this.code = const Value.absent(),
    this.json = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedDocCompanion.insert({
    required String code,
    required String json,
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : code = Value(code),
       json = Value(json),
       fetchedAt = Value(fetchedAt);
  static Insertable<CachedDocData> custom({
    Expression<String>? code,
    Expression<String>? json,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (json != null) 'json': json,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedDocCompanion copyWith({
    Value<String>? code,
    Value<String>? json,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return CachedDocCompanion(
      code: code ?? this.code,
      json: json ?? this.json,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedDocCompanion(')
          ..write('code: $code, ')
          ..write('json: $json, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CompletedDocTable extends CompletedDoc
    with TableInfo<$CompletedDocTable, CompletedDocData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CompletedDocTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [code, completedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'completed_doc';
  @override
  VerificationContext validateIntegrity(
    Insertable<CompletedDocData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    } else if (isInserting) {
      context.missing(_codeMeta);
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {code};
  @override
  CompletedDocData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CompletedDocData(
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      )!,
    );
  }

  @override
  $CompletedDocTable createAlias(String alias) {
    return $CompletedDocTable(attachedDatabase, alias);
  }
}

class CompletedDocData extends DataClass
    implements Insertable<CompletedDocData> {
  final String code;
  final DateTime completedAt;
  const CompletedDocData({required this.code, required this.completedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['code'] = Variable<String>(code);
    map['completed_at'] = Variable<DateTime>(completedAt);
    return map;
  }

  CompletedDocCompanion toCompanion(bool nullToAbsent) {
    return CompletedDocCompanion(
      code: Value(code),
      completedAt: Value(completedAt),
    );
  }

  factory CompletedDocData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CompletedDocData(
      code: serializer.fromJson<String>(json['code']),
      completedAt: serializer.fromJson<DateTime>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'code': serializer.toJson<String>(code),
      'completedAt': serializer.toJson<DateTime>(completedAt),
    };
  }

  CompletedDocData copyWith({String? code, DateTime? completedAt}) =>
      CompletedDocData(
        code: code ?? this.code,
        completedAt: completedAt ?? this.completedAt,
      );
  CompletedDocData copyWithCompanion(CompletedDocCompanion data) {
    return CompletedDocData(
      code: data.code.present ? data.code.value : this.code,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CompletedDocData(')
          ..write('code: $code, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(code, completedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CompletedDocData &&
          other.code == this.code &&
          other.completedAt == this.completedAt);
}

class CompletedDocCompanion extends UpdateCompanion<CompletedDocData> {
  final Value<String> code;
  final Value<DateTime> completedAt;
  final Value<int> rowid;
  const CompletedDocCompanion({
    this.code = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CompletedDocCompanion.insert({
    required String code,
    this.completedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : code = Value(code);
  static Insertable<CompletedDocData> custom({
    Expression<String>? code,
    Expression<DateTime>? completedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (code != null) 'code': code,
      if (completedAt != null) 'completed_at': completedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CompletedDocCompanion copyWith({
    Value<String>? code,
    Value<DateTime>? completedAt,
    Value<int>? rowid,
  }) {
    return CompletedDocCompanion(
      code: code ?? this.code,
      completedAt: completedAt ?? this.completedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CompletedDocCompanion(')
          ..write('code: $code, ')
          ..write('completedAt: $completedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ScanProgressTable scanProgress = $ScanProgressTable(this);
  late final $CachedDocTable cachedDoc = $CachedDocTable(this);
  late final $CompletedDocTable completedDoc = $CompletedDocTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    scanProgress,
    cachedDoc,
    completedDoc,
  ];
}

typedef $$ScanProgressTableCreateCompanionBuilder =
    ScanProgressCompanion Function({
      required String docCode,
      required int lineNumber,
      Value<String?> nomenclatureCode,
      Value<int> qtyActual,
      Value<String?> action,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$ScanProgressTableUpdateCompanionBuilder =
    ScanProgressCompanion Function({
      Value<String> docCode,
      Value<int> lineNumber,
      Value<String?> nomenclatureCode,
      Value<int> qtyActual,
      Value<String?> action,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ScanProgressTableFilterComposer
    extends Composer<_$AppDatabase, $ScanProgressTable> {
  $$ScanProgressTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get docCode => $composableBuilder(
    column: $table.docCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nomenclatureCode => $composableBuilder(
    column: $table.nomenclatureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get qtyActual => $composableBuilder(
    column: $table.qtyActual,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ScanProgressTableOrderingComposer
    extends Composer<_$AppDatabase, $ScanProgressTable> {
  $$ScanProgressTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get docCode => $composableBuilder(
    column: $table.docCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nomenclatureCode => $composableBuilder(
    column: $table.nomenclatureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get qtyActual => $composableBuilder(
    column: $table.qtyActual,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ScanProgressTableAnnotationComposer
    extends Composer<_$AppDatabase, $ScanProgressTable> {
  $$ScanProgressTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get docCode =>
      $composableBuilder(column: $table.docCode, builder: (column) => column);

  GeneratedColumn<int> get lineNumber => $composableBuilder(
    column: $table.lineNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nomenclatureCode => $composableBuilder(
    column: $table.nomenclatureCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get qtyActual =>
      $composableBuilder(column: $table.qtyActual, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ScanProgressTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ScanProgressTable,
          ScanProgressData,
          $$ScanProgressTableFilterComposer,
          $$ScanProgressTableOrderingComposer,
          $$ScanProgressTableAnnotationComposer,
          $$ScanProgressTableCreateCompanionBuilder,
          $$ScanProgressTableUpdateCompanionBuilder,
          (
            ScanProgressData,
            BaseReferences<_$AppDatabase, $ScanProgressTable, ScanProgressData>,
          ),
          ScanProgressData,
          PrefetchHooks Function()
        > {
  $$ScanProgressTableTableManager(_$AppDatabase db, $ScanProgressTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ScanProgressTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ScanProgressTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ScanProgressTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> docCode = const Value.absent(),
                Value<int> lineNumber = const Value.absent(),
                Value<String?> nomenclatureCode = const Value.absent(),
                Value<int> qtyActual = const Value.absent(),
                Value<String?> action = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanProgressCompanion(
                docCode: docCode,
                lineNumber: lineNumber,
                nomenclatureCode: nomenclatureCode,
                qtyActual: qtyActual,
                action: action,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String docCode,
                required int lineNumber,
                Value<String?> nomenclatureCode = const Value.absent(),
                Value<int> qtyActual = const Value.absent(),
                Value<String?> action = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ScanProgressCompanion.insert(
                docCode: docCode,
                lineNumber: lineNumber,
                nomenclatureCode: nomenclatureCode,
                qtyActual: qtyActual,
                action: action,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ScanProgressTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ScanProgressTable,
      ScanProgressData,
      $$ScanProgressTableFilterComposer,
      $$ScanProgressTableOrderingComposer,
      $$ScanProgressTableAnnotationComposer,
      $$ScanProgressTableCreateCompanionBuilder,
      $$ScanProgressTableUpdateCompanionBuilder,
      (
        ScanProgressData,
        BaseReferences<_$AppDatabase, $ScanProgressTable, ScanProgressData>,
      ),
      ScanProgressData,
      PrefetchHooks Function()
    >;
typedef $$CachedDocTableCreateCompanionBuilder =
    CachedDocCompanion Function({
      required String code,
      required String json,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$CachedDocTableUpdateCompanionBuilder =
    CachedDocCompanion Function({
      Value<String> code,
      Value<String> json,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$CachedDocTableFilterComposer
    extends Composer<_$AppDatabase, $CachedDocTable> {
  $$CachedDocTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedDocTableOrderingComposer
    extends Composer<_$AppDatabase, $CachedDocTable> {
  $$CachedDocTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedDocTableAnnotationComposer
    extends Composer<_$AppDatabase, $CachedDocTable> {
  $$CachedDocTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$CachedDocTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CachedDocTable,
          CachedDocData,
          $$CachedDocTableFilterComposer,
          $$CachedDocTableOrderingComposer,
          $$CachedDocTableAnnotationComposer,
          $$CachedDocTableCreateCompanionBuilder,
          $$CachedDocTableUpdateCompanionBuilder,
          (
            CachedDocData,
            BaseReferences<_$AppDatabase, $CachedDocTable, CachedDocData>,
          ),
          CachedDocData,
          PrefetchHooks Function()
        > {
  $$CachedDocTableTableManager(_$AppDatabase db, $CachedDocTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedDocTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedDocTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CachedDocTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedDocCompanion(
                code: code,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                required String json,
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedDocCompanion.insert(
                code: code,
                json: json,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedDocTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CachedDocTable,
      CachedDocData,
      $$CachedDocTableFilterComposer,
      $$CachedDocTableOrderingComposer,
      $$CachedDocTableAnnotationComposer,
      $$CachedDocTableCreateCompanionBuilder,
      $$CachedDocTableUpdateCompanionBuilder,
      (
        CachedDocData,
        BaseReferences<_$AppDatabase, $CachedDocTable, CachedDocData>,
      ),
      CachedDocData,
      PrefetchHooks Function()
    >;
typedef $$CompletedDocTableCreateCompanionBuilder =
    CompletedDocCompanion Function({
      required String code,
      Value<DateTime> completedAt,
      Value<int> rowid,
    });
typedef $$CompletedDocTableUpdateCompanionBuilder =
    CompletedDocCompanion Function({
      Value<String> code,
      Value<DateTime> completedAt,
      Value<int> rowid,
    });

class $$CompletedDocTableFilterComposer
    extends Composer<_$AppDatabase, $CompletedDocTable> {
  $$CompletedDocTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CompletedDocTableOrderingComposer
    extends Composer<_$AppDatabase, $CompletedDocTable> {
  $$CompletedDocTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CompletedDocTableAnnotationComposer
    extends Composer<_$AppDatabase, $CompletedDocTable> {
  $$CompletedDocTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$CompletedDocTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CompletedDocTable,
          CompletedDocData,
          $$CompletedDocTableFilterComposer,
          $$CompletedDocTableOrderingComposer,
          $$CompletedDocTableAnnotationComposer,
          $$CompletedDocTableCreateCompanionBuilder,
          $$CompletedDocTableUpdateCompanionBuilder,
          (
            CompletedDocData,
            BaseReferences<_$AppDatabase, $CompletedDocTable, CompletedDocData>,
          ),
          CompletedDocData,
          PrefetchHooks Function()
        > {
  $$CompletedDocTableTableManager(_$AppDatabase db, $CompletedDocTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CompletedDocTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CompletedDocTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CompletedDocTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> code = const Value.absent(),
                Value<DateTime> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompletedDocCompanion(
                code: code,
                completedAt: completedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String code,
                Value<DateTime> completedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CompletedDocCompanion.insert(
                code: code,
                completedAt: completedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CompletedDocTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CompletedDocTable,
      CompletedDocData,
      $$CompletedDocTableFilterComposer,
      $$CompletedDocTableOrderingComposer,
      $$CompletedDocTableAnnotationComposer,
      $$CompletedDocTableCreateCompanionBuilder,
      $$CompletedDocTableUpdateCompanionBuilder,
      (
        CompletedDocData,
        BaseReferences<_$AppDatabase, $CompletedDocTable, CompletedDocData>,
      ),
      CompletedDocData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ScanProgressTableTableManager get scanProgress =>
      $$ScanProgressTableTableManager(_db, _db.scanProgress);
  $$CachedDocTableTableManager get cachedDoc =>
      $$CachedDocTableTableManager(_db, _db.cachedDoc);
  $$CompletedDocTableTableManager get completedDoc =>
      $$CompletedDocTableTableManager(_db, _db.completedDoc);
}
