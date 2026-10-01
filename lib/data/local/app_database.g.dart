// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ProfilesTable extends Profiles
    with TableInfo<$ProfilesTable, ProfileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profiles';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProfilesTable createAlias(String alias) {
    return $ProfilesTable(attachedDatabase, alias);
  }
}

class ProfileRow extends DataClass implements Insertable<ProfileRow> {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  const ProfileRow({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProfilesCompanion toCompanion(bool nullToAbsent) {
    return ProfilesCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProfileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProfileRow copyWith({String? id, DateTime? createdAt, DateTime? updatedAt}) =>
      ProfileRow(
        id: id ?? this.id,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  ProfileRow copyWithCompanion(ProfilesCompanion data) {
    return ProfileRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProfilesCompanion extends UpdateCompanion<ProfileRow> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProfilesCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfilesCompanion.insert({
    required String id,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<ProfileRow> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfilesCompanion copyWith({
    Value<String>? id,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProfilesCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('ProfilesCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserPreferencesTable extends UserPreferences
    with TableInfo<$UserPreferencesTable, UserPreferenceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserPreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileElementIdMeta = const VerificationMeta(
    'profileElementId',
  );
  @override
  late final GeneratedColumn<String> profileElementId = GeneratedColumn<String>(
    'profile_element_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generalValueMeta = const VerificationMeta(
    'generalValue',
  );
  @override
  late final GeneratedColumn<int> generalValue = GeneratedColumn<int>(
    'general_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _faireValueMeta = const VerificationMeta(
    'faireValue',
  );
  @override
  late final GeneratedColumn<int> faireValue = GeneratedColumn<int>(
    'faire_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recevoirValueMeta = const VerificationMeta(
    'recevoirValue',
  );
  @override
  late final GeneratedColumn<int> recevoirValue = GeneratedColumn<int>(
    'recevoir_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    profileElementId,
    status,
    generalValue,
    faireValue,
    recevoirValue,
    updatedAt,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<UserPreferenceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('profile_element_id')) {
      context.handle(
        _profileElementIdMeta,
        profileElementId.isAcceptableOrUnknown(
          data['profile_element_id']!,
          _profileElementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profileElementIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('general_value')) {
      context.handle(
        _generalValueMeta,
        generalValue.isAcceptableOrUnknown(
          data['general_value']!,
          _generalValueMeta,
        ),
      );
    }
    if (data.containsKey('faire_value')) {
      context.handle(
        _faireValueMeta,
        faireValue.isAcceptableOrUnknown(data['faire_value']!, _faireValueMeta),
      );
    }
    if (data.containsKey('recevoir_value')) {
      context.handle(
        _recevoirValueMeta,
        recevoirValue.isAcceptableOrUnknown(
          data['recevoir_value']!,
          _recevoirValueMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, profileElementId};
  @override
  UserPreferenceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserPreferenceRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      profileElementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_element_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      generalValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}general_value'],
      ),
      faireValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}faire_value'],
      ),
      recevoirValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recevoir_value'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $UserPreferencesTable createAlias(String alias) {
    return $UserPreferencesTable(attachedDatabase, alias);
  }
}

class UserPreferenceRow extends DataClass
    implements Insertable<UserPreferenceRow> {
  final String profileId;
  final String profileElementId;
  final String status;
  final int? generalValue;
  final int? faireValue;
  final int? recevoirValue;
  final DateTime updatedAt;
  final String source;
  const UserPreferenceRow({
    required this.profileId,
    required this.profileElementId,
    required this.status,
    this.generalValue,
    this.faireValue,
    this.recevoirValue,
    required this.updatedAt,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['profile_element_id'] = Variable<String>(profileElementId);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || generalValue != null) {
      map['general_value'] = Variable<int>(generalValue);
    }
    if (!nullToAbsent || faireValue != null) {
      map['faire_value'] = Variable<int>(faireValue);
    }
    if (!nullToAbsent || recevoirValue != null) {
      map['recevoir_value'] = Variable<int>(recevoirValue);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['source'] = Variable<String>(source);
    return map;
  }

  UserPreferencesCompanion toCompanion(bool nullToAbsent) {
    return UserPreferencesCompanion(
      profileId: Value(profileId),
      profileElementId: Value(profileElementId),
      status: Value(status),
      generalValue: generalValue == null && nullToAbsent
          ? const Value.absent()
          : Value(generalValue),
      faireValue: faireValue == null && nullToAbsent
          ? const Value.absent()
          : Value(faireValue),
      recevoirValue: recevoirValue == null && nullToAbsent
          ? const Value.absent()
          : Value(recevoirValue),
      updatedAt: Value(updatedAt),
      source: Value(source),
    );
  }

  factory UserPreferenceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserPreferenceRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      profileElementId: serializer.fromJson<String>(json['profileElementId']),
      status: serializer.fromJson<String>(json['status']),
      generalValue: serializer.fromJson<int?>(json['generalValue']),
      faireValue: serializer.fromJson<int?>(json['faireValue']),
      recevoirValue: serializer.fromJson<int?>(json['recevoirValue']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'profileElementId': serializer.toJson<String>(profileElementId),
      'status': serializer.toJson<String>(status),
      'generalValue': serializer.toJson<int?>(generalValue),
      'faireValue': serializer.toJson<int?>(faireValue),
      'recevoirValue': serializer.toJson<int?>(recevoirValue),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'source': serializer.toJson<String>(source),
    };
  }

  UserPreferenceRow copyWith({
    String? profileId,
    String? profileElementId,
    String? status,
    Value<int?> generalValue = const Value.absent(),
    Value<int?> faireValue = const Value.absent(),
    Value<int?> recevoirValue = const Value.absent(),
    DateTime? updatedAt,
    String? source,
  }) => UserPreferenceRow(
    profileId: profileId ?? this.profileId,
    profileElementId: profileElementId ?? this.profileElementId,
    status: status ?? this.status,
    generalValue: generalValue.present ? generalValue.value : this.generalValue,
    faireValue: faireValue.present ? faireValue.value : this.faireValue,
    recevoirValue: recevoirValue.present
        ? recevoirValue.value
        : this.recevoirValue,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source ?? this.source,
  );
  UserPreferenceRow copyWithCompanion(UserPreferencesCompanion data) {
    return UserPreferenceRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      profileElementId: data.profileElementId.present
          ? data.profileElementId.value
          : this.profileElementId,
      status: data.status.present ? data.status.value : this.status,
      generalValue: data.generalValue.present
          ? data.generalValue.value
          : this.generalValue,
      faireValue: data.faireValue.present
          ? data.faireValue.value
          : this.faireValue,
      recevoirValue: data.recevoirValue.present
          ? data.recevoirValue.value
          : this.recevoirValue,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferenceRow(')
          ..write('profileId: $profileId, ')
          ..write('profileElementId: $profileElementId, ')
          ..write('status: $status, ')
          ..write('generalValue: $generalValue, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    profileElementId,
    status,
    generalValue,
    faireValue,
    recevoirValue,
    updatedAt,
    source,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserPreferenceRow &&
          other.profileId == this.profileId &&
          other.profileElementId == this.profileElementId &&
          other.status == this.status &&
          other.generalValue == this.generalValue &&
          other.faireValue == this.faireValue &&
          other.recevoirValue == this.recevoirValue &&
          other.updatedAt == this.updatedAt &&
          other.source == this.source);
}

class UserPreferencesCompanion extends UpdateCompanion<UserPreferenceRow> {
  final Value<String> profileId;
  final Value<String> profileElementId;
  final Value<String> status;
  final Value<int?> generalValue;
  final Value<int?> faireValue;
  final Value<int?> recevoirValue;
  final Value<DateTime> updatedAt;
  final Value<String> source;
  final Value<int> rowid;
  const UserPreferencesCompanion({
    this.profileId = const Value.absent(),
    this.profileElementId = const Value.absent(),
    this.status = const Value.absent(),
    this.generalValue = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserPreferencesCompanion.insert({
    required String profileId,
    required String profileElementId,
    required String status,
    this.generalValue = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    required DateTime updatedAt,
    required String source,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       profileElementId = Value(profileElementId),
       status = Value(status),
       updatedAt = Value(updatedAt),
       source = Value(source);
  static Insertable<UserPreferenceRow> custom({
    Expression<String>? profileId,
    Expression<String>? profileElementId,
    Expression<String>? status,
    Expression<int>? generalValue,
    Expression<int>? faireValue,
    Expression<int>? recevoirValue,
    Expression<DateTime>? updatedAt,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (profileElementId != null) 'profile_element_id': profileElementId,
      if (status != null) 'status': status,
      if (generalValue != null) 'general_value': generalValue,
      if (faireValue != null) 'faire_value': faireValue,
      if (recevoirValue != null) 'recevoir_value': recevoirValue,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserPreferencesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? profileElementId,
    Value<String>? status,
    Value<int?>? generalValue,
    Value<int?>? faireValue,
    Value<int?>? recevoirValue,
    Value<DateTime>? updatedAt,
    Value<String>? source,
    Value<int>? rowid,
  }) {
    return UserPreferencesCompanion(
      profileId: profileId ?? this.profileId,
      profileElementId: profileElementId ?? this.profileElementId,
      status: status ?? this.status,
      generalValue: generalValue ?? this.generalValue,
      faireValue: faireValue ?? this.faireValue,
      recevoirValue: recevoirValue ?? this.recevoirValue,
      updatedAt: updatedAt ?? this.updatedAt,
      source: source ?? this.source,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (profileElementId.present) {
      map['profile_element_id'] = Variable<String>(profileElementId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (generalValue.present) {
      map['general_value'] = Variable<int>(generalValue.value);
    }
    if (faireValue.present) {
      map['faire_value'] = Variable<int>(faireValue.value);
    }
    if (recevoirValue.present) {
      map['recevoir_value'] = Variable<int>(recevoirValue.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserPreferencesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('profileElementId: $profileElementId, ')
          ..write('status: $status, ')
          ..write('generalValue: $generalValue, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardPreferenceOverridesTable extends CardPreferenceOverrides
    with TableInfo<$CardPreferenceOverridesTable, CardPreferenceOverrideRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardPreferenceOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardOrVariantIdMeta = const VerificationMeta(
    'cardOrVariantId',
  );
  @override
  late final GeneratedColumn<String> cardOrVariantId = GeneratedColumn<String>(
    'card_or_variant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _faireValueMeta = const VerificationMeta(
    'faireValue',
  );
  @override
  late final GeneratedColumn<int> faireValue = GeneratedColumn<int>(
    'faire_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recevoirValueMeta = const VerificationMeta(
    'recevoirValue',
  );
  @override
  late final GeneratedColumn<int> recevoirValue = GeneratedColumn<int>(
    'recevoir_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    profileId,
    cardOrVariantId,
    status,
    faireValue,
    recevoirValue,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'card_preference_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardPreferenceOverrideRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('card_or_variant_id')) {
      context.handle(
        _cardOrVariantIdMeta,
        cardOrVariantId.isAcceptableOrUnknown(
          data['card_or_variant_id']!,
          _cardOrVariantIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cardOrVariantIdMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('faire_value')) {
      context.handle(
        _faireValueMeta,
        faireValue.isAcceptableOrUnknown(data['faire_value']!, _faireValueMeta),
      );
    }
    if (data.containsKey('recevoir_value')) {
      context.handle(
        _recevoirValueMeta,
        recevoirValue.isAcceptableOrUnknown(
          data['recevoir_value']!,
          _recevoirValueMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId, cardOrVariantId};
  @override
  CardPreferenceOverrideRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardPreferenceOverrideRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      cardOrVariantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_or_variant_id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      faireValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}faire_value'],
      ),
      recevoirValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recevoir_value'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CardPreferenceOverridesTable createAlias(String alias) {
    return $CardPreferenceOverridesTable(attachedDatabase, alias);
  }
}

class CardPreferenceOverrideRow extends DataClass
    implements Insertable<CardPreferenceOverrideRow> {
  final String profileId;
  final String cardOrVariantId;
  final String? status;
  final int? faireValue;
  final int? recevoirValue;
  final DateTime updatedAt;
  const CardPreferenceOverrideRow({
    required this.profileId,
    required this.cardOrVariantId,
    this.status,
    this.faireValue,
    this.recevoirValue,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['card_or_variant_id'] = Variable<String>(cardOrVariantId);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || faireValue != null) {
      map['faire_value'] = Variable<int>(faireValue);
    }
    if (!nullToAbsent || recevoirValue != null) {
      map['recevoir_value'] = Variable<int>(recevoirValue);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CardPreferenceOverridesCompanion toCompanion(bool nullToAbsent) {
    return CardPreferenceOverridesCompanion(
      profileId: Value(profileId),
      cardOrVariantId: Value(cardOrVariantId),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      faireValue: faireValue == null && nullToAbsent
          ? const Value.absent()
          : Value(faireValue),
      recevoirValue: recevoirValue == null && nullToAbsent
          ? const Value.absent()
          : Value(recevoirValue),
      updatedAt: Value(updatedAt),
    );
  }

  factory CardPreferenceOverrideRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardPreferenceOverrideRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      cardOrVariantId: serializer.fromJson<String>(json['cardOrVariantId']),
      status: serializer.fromJson<String?>(json['status']),
      faireValue: serializer.fromJson<int?>(json['faireValue']),
      recevoirValue: serializer.fromJson<int?>(json['recevoirValue']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'cardOrVariantId': serializer.toJson<String>(cardOrVariantId),
      'status': serializer.toJson<String?>(status),
      'faireValue': serializer.toJson<int?>(faireValue),
      'recevoirValue': serializer.toJson<int?>(recevoirValue),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CardPreferenceOverrideRow copyWith({
    String? profileId,
    String? cardOrVariantId,
    Value<String?> status = const Value.absent(),
    Value<int?> faireValue = const Value.absent(),
    Value<int?> recevoirValue = const Value.absent(),
    DateTime? updatedAt,
  }) => CardPreferenceOverrideRow(
    profileId: profileId ?? this.profileId,
    cardOrVariantId: cardOrVariantId ?? this.cardOrVariantId,
    status: status.present ? status.value : this.status,
    faireValue: faireValue.present ? faireValue.value : this.faireValue,
    recevoirValue: recevoirValue.present
        ? recevoirValue.value
        : this.recevoirValue,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CardPreferenceOverrideRow copyWithCompanion(
    CardPreferenceOverridesCompanion data,
  ) {
    return CardPreferenceOverrideRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      cardOrVariantId: data.cardOrVariantId.present
          ? data.cardOrVariantId.value
          : this.cardOrVariantId,
      status: data.status.present ? data.status.value : this.status,
      faireValue: data.faireValue.present
          ? data.faireValue.value
          : this.faireValue,
      recevoirValue: data.recevoirValue.present
          ? data.recevoirValue.value
          : this.recevoirValue,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardPreferenceOverrideRow(')
          ..write('profileId: $profileId, ')
          ..write('cardOrVariantId: $cardOrVariantId, ')
          ..write('status: $status, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    profileId,
    cardOrVariantId,
    status,
    faireValue,
    recevoirValue,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardPreferenceOverrideRow &&
          other.profileId == this.profileId &&
          other.cardOrVariantId == this.cardOrVariantId &&
          other.status == this.status &&
          other.faireValue == this.faireValue &&
          other.recevoirValue == this.recevoirValue &&
          other.updatedAt == this.updatedAt);
}

class CardPreferenceOverridesCompanion
    extends UpdateCompanion<CardPreferenceOverrideRow> {
  final Value<String> profileId;
  final Value<String> cardOrVariantId;
  final Value<String?> status;
  final Value<int?> faireValue;
  final Value<int?> recevoirValue;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CardPreferenceOverridesCompanion({
    this.profileId = const Value.absent(),
    this.cardOrVariantId = const Value.absent(),
    this.status = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardPreferenceOverridesCompanion.insert({
    required String profileId,
    required String cardOrVariantId,
    this.status = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       cardOrVariantId = Value(cardOrVariantId),
       updatedAt = Value(updatedAt);
  static Insertable<CardPreferenceOverrideRow> custom({
    Expression<String>? profileId,
    Expression<String>? cardOrVariantId,
    Expression<String>? status,
    Expression<int>? faireValue,
    Expression<int>? recevoirValue,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (cardOrVariantId != null) 'card_or_variant_id': cardOrVariantId,
      if (status != null) 'status': status,
      if (faireValue != null) 'faire_value': faireValue,
      if (recevoirValue != null) 'recevoir_value': recevoirValue,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardPreferenceOverridesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? cardOrVariantId,
    Value<String?>? status,
    Value<int?>? faireValue,
    Value<int?>? recevoirValue,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CardPreferenceOverridesCompanion(
      profileId: profileId ?? this.profileId,
      cardOrVariantId: cardOrVariantId ?? this.cardOrVariantId,
      status: status ?? this.status,
      faireValue: faireValue ?? this.faireValue,
      recevoirValue: recevoirValue ?? this.recevoirValue,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (cardOrVariantId.present) {
      map['card_or_variant_id'] = Variable<String>(cardOrVariantId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (faireValue.present) {
      map['faire_value'] = Variable<int>(faireValue.value);
    }
    if (recevoirValue.present) {
      map['recevoir_value'] = Variable<int>(recevoirValue.value);
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
    return (StringBuffer('CardPreferenceOverridesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('cardOrVariantId: $cardOrVariantId, ')
          ..write('status: $status, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileEvolutionEntriesTable extends ProfileEvolutionEntries
    with TableInfo<$ProfileEvolutionEntriesTable, ProfileEvolutionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileEvolutionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileElementIdMeta = const VerificationMeta(
    'profileElementId',
  );
  @override
  late final GeneratedColumn<String> profileElementId = GeneratedColumn<String>(
    'profile_element_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _generalValueMeta = const VerificationMeta(
    'generalValue',
  );
  @override
  late final GeneratedColumn<int> generalValue = GeneratedColumn<int>(
    'general_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _faireValueMeta = const VerificationMeta(
    'faireValue',
  );
  @override
  late final GeneratedColumn<int> faireValue = GeneratedColumn<int>(
    'faire_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recevoirValueMeta = const VerificationMeta(
    'recevoirValue',
  );
  @override
  late final GeneratedColumn<int> recevoirValue = GeneratedColumn<int>(
    'recevoir_value',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _evidenceJsonMeta = const VerificationMeta(
    'evidenceJson',
  );
  @override
  late final GeneratedColumn<String> evidenceJson = GeneratedColumn<String>(
    'evidence_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    profileId,
    profileElementId,
    generalValue,
    faireValue,
    recevoirValue,
    evidenceJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_evolution_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileEvolutionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('profile_element_id')) {
      context.handle(
        _profileElementIdMeta,
        profileElementId.isAcceptableOrUnknown(
          data['profile_element_id']!,
          _profileElementIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_profileElementIdMeta);
    }
    if (data.containsKey('general_value')) {
      context.handle(
        _generalValueMeta,
        generalValue.isAcceptableOrUnknown(
          data['general_value']!,
          _generalValueMeta,
        ),
      );
    }
    if (data.containsKey('faire_value')) {
      context.handle(
        _faireValueMeta,
        faireValue.isAcceptableOrUnknown(data['faire_value']!, _faireValueMeta),
      );
    }
    if (data.containsKey('recevoir_value')) {
      context.handle(
        _recevoirValueMeta,
        recevoirValue.isAcceptableOrUnknown(
          data['recevoir_value']!,
          _recevoirValueMeta,
        ),
      );
    }
    if (data.containsKey('evidence_json')) {
      context.handle(
        _evidenceJsonMeta,
        evidenceJson.isAcceptableOrUnknown(
          data['evidence_json']!,
          _evidenceJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_evidenceJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProfileEvolutionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileEvolutionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      profileElementId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_element_id'],
      )!,
      generalValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}general_value'],
      ),
      faireValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}faire_value'],
      ),
      recevoirValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recevoir_value'],
      ),
      evidenceJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}evidence_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ProfileEvolutionEntriesTable createAlias(String alias) {
    return $ProfileEvolutionEntriesTable(attachedDatabase, alias);
  }
}

class ProfileEvolutionRow extends DataClass
    implements Insertable<ProfileEvolutionRow> {
  final int id;
  final String profileId;
  final String profileElementId;
  final int? generalValue;
  final int? faireValue;
  final int? recevoirValue;
  final String evidenceJson;
  final DateTime createdAt;
  const ProfileEvolutionRow({
    required this.id,
    required this.profileId,
    required this.profileElementId,
    this.generalValue,
    this.faireValue,
    this.recevoirValue,
    required this.evidenceJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['profile_id'] = Variable<String>(profileId);
    map['profile_element_id'] = Variable<String>(profileElementId);
    if (!nullToAbsent || generalValue != null) {
      map['general_value'] = Variable<int>(generalValue);
    }
    if (!nullToAbsent || faireValue != null) {
      map['faire_value'] = Variable<int>(faireValue);
    }
    if (!nullToAbsent || recevoirValue != null) {
      map['recevoir_value'] = Variable<int>(recevoirValue);
    }
    map['evidence_json'] = Variable<String>(evidenceJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ProfileEvolutionEntriesCompanion toCompanion(bool nullToAbsent) {
    return ProfileEvolutionEntriesCompanion(
      id: Value(id),
      profileId: Value(profileId),
      profileElementId: Value(profileElementId),
      generalValue: generalValue == null && nullToAbsent
          ? const Value.absent()
          : Value(generalValue),
      faireValue: faireValue == null && nullToAbsent
          ? const Value.absent()
          : Value(faireValue),
      recevoirValue: recevoirValue == null && nullToAbsent
          ? const Value.absent()
          : Value(recevoirValue),
      evidenceJson: Value(evidenceJson),
      createdAt: Value(createdAt),
    );
  }

  factory ProfileEvolutionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileEvolutionRow(
      id: serializer.fromJson<int>(json['id']),
      profileId: serializer.fromJson<String>(json['profileId']),
      profileElementId: serializer.fromJson<String>(json['profileElementId']),
      generalValue: serializer.fromJson<int?>(json['generalValue']),
      faireValue: serializer.fromJson<int?>(json['faireValue']),
      recevoirValue: serializer.fromJson<int?>(json['recevoirValue']),
      evidenceJson: serializer.fromJson<String>(json['evidenceJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'profileId': serializer.toJson<String>(profileId),
      'profileElementId': serializer.toJson<String>(profileElementId),
      'generalValue': serializer.toJson<int?>(generalValue),
      'faireValue': serializer.toJson<int?>(faireValue),
      'recevoirValue': serializer.toJson<int?>(recevoirValue),
      'evidenceJson': serializer.toJson<String>(evidenceJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ProfileEvolutionRow copyWith({
    int? id,
    String? profileId,
    String? profileElementId,
    Value<int?> generalValue = const Value.absent(),
    Value<int?> faireValue = const Value.absent(),
    Value<int?> recevoirValue = const Value.absent(),
    String? evidenceJson,
    DateTime? createdAt,
  }) => ProfileEvolutionRow(
    id: id ?? this.id,
    profileId: profileId ?? this.profileId,
    profileElementId: profileElementId ?? this.profileElementId,
    generalValue: generalValue.present ? generalValue.value : this.generalValue,
    faireValue: faireValue.present ? faireValue.value : this.faireValue,
    recevoirValue: recevoirValue.present
        ? recevoirValue.value
        : this.recevoirValue,
    evidenceJson: evidenceJson ?? this.evidenceJson,
    createdAt: createdAt ?? this.createdAt,
  );
  ProfileEvolutionRow copyWithCompanion(ProfileEvolutionEntriesCompanion data) {
    return ProfileEvolutionRow(
      id: data.id.present ? data.id.value : this.id,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      profileElementId: data.profileElementId.present
          ? data.profileElementId.value
          : this.profileElementId,
      generalValue: data.generalValue.present
          ? data.generalValue.value
          : this.generalValue,
      faireValue: data.faireValue.present
          ? data.faireValue.value
          : this.faireValue,
      recevoirValue: data.recevoirValue.present
          ? data.recevoirValue.value
          : this.recevoirValue,
      evidenceJson: data.evidenceJson.present
          ? data.evidenceJson.value
          : this.evidenceJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileEvolutionRow(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('profileElementId: $profileElementId, ')
          ..write('generalValue: $generalValue, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    profileId,
    profileElementId,
    generalValue,
    faireValue,
    recevoirValue,
    evidenceJson,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileEvolutionRow &&
          other.id == this.id &&
          other.profileId == this.profileId &&
          other.profileElementId == this.profileElementId &&
          other.generalValue == this.generalValue &&
          other.faireValue == this.faireValue &&
          other.recevoirValue == this.recevoirValue &&
          other.evidenceJson == this.evidenceJson &&
          other.createdAt == this.createdAt);
}

class ProfileEvolutionEntriesCompanion
    extends UpdateCompanion<ProfileEvolutionRow> {
  final Value<int> id;
  final Value<String> profileId;
  final Value<String> profileElementId;
  final Value<int?> generalValue;
  final Value<int?> faireValue;
  final Value<int?> recevoirValue;
  final Value<String> evidenceJson;
  final Value<DateTime> createdAt;
  const ProfileEvolutionEntriesCompanion({
    this.id = const Value.absent(),
    this.profileId = const Value.absent(),
    this.profileElementId = const Value.absent(),
    this.generalValue = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    this.evidenceJson = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  ProfileEvolutionEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String profileId,
    required String profileElementId,
    this.generalValue = const Value.absent(),
    this.faireValue = const Value.absent(),
    this.recevoirValue = const Value.absent(),
    required String evidenceJson,
    required DateTime createdAt,
  }) : profileId = Value(profileId),
       profileElementId = Value(profileElementId),
       evidenceJson = Value(evidenceJson),
       createdAt = Value(createdAt);
  static Insertable<ProfileEvolutionRow> custom({
    Expression<int>? id,
    Expression<String>? profileId,
    Expression<String>? profileElementId,
    Expression<int>? generalValue,
    Expression<int>? faireValue,
    Expression<int>? recevoirValue,
    Expression<String>? evidenceJson,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (profileId != null) 'profile_id': profileId,
      if (profileElementId != null) 'profile_element_id': profileElementId,
      if (generalValue != null) 'general_value': generalValue,
      if (faireValue != null) 'faire_value': faireValue,
      if (recevoirValue != null) 'recevoir_value': recevoirValue,
      if (evidenceJson != null) 'evidence_json': evidenceJson,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  ProfileEvolutionEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? profileId,
    Value<String>? profileElementId,
    Value<int?>? generalValue,
    Value<int?>? faireValue,
    Value<int?>? recevoirValue,
    Value<String>? evidenceJson,
    Value<DateTime>? createdAt,
  }) {
    return ProfileEvolutionEntriesCompanion(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      profileElementId: profileElementId ?? this.profileElementId,
      generalValue: generalValue ?? this.generalValue,
      faireValue: faireValue ?? this.faireValue,
      recevoirValue: recevoirValue ?? this.recevoirValue,
      evidenceJson: evidenceJson ?? this.evidenceJson,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (profileElementId.present) {
      map['profile_element_id'] = Variable<String>(profileElementId.value);
    }
    if (generalValue.present) {
      map['general_value'] = Variable<int>(generalValue.value);
    }
    if (faireValue.present) {
      map['faire_value'] = Variable<int>(faireValue.value);
    }
    if (recevoirValue.present) {
      map['recevoir_value'] = Variable<int>(recevoirValue.value);
    }
    if (evidenceJson.present) {
      map['evidence_json'] = Variable<String>(evidenceJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileEvolutionEntriesCompanion(')
          ..write('id: $id, ')
          ..write('profileId: $profileId, ')
          ..write('profileElementId: $profileElementId, ')
          ..write('generalValue: $generalValue, ')
          ..write('faireValue: $faireValue, ')
          ..write('recevoirValue: $recevoirValue, ')
          ..write('evidenceJson: $evidenceJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $ProfileLearningStatesTable extends ProfileLearningStates
    with TableInfo<$ProfileLearningStatesTable, ProfileLearningStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileLearningStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateJsonMeta = const VerificationMeta(
    'stateJson',
  );
  @override
  late final GeneratedColumn<String> stateJson = GeneratedColumn<String>(
    'state_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [profileId, stateJson, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_learning_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProfileLearningStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_profileIdMeta);
    }
    if (data.containsKey('state_json')) {
      context.handle(
        _stateJsonMeta,
        stateJson.isAcceptableOrUnknown(data['state_json']!, _stateJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_stateJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {profileId};
  @override
  ProfileLearningStateRow map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProfileLearningStateRow(
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      )!,
      stateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $ProfileLearningStatesTable createAlias(String alias) {
    return $ProfileLearningStatesTable(attachedDatabase, alias);
  }
}

class ProfileLearningStateRow extends DataClass
    implements Insertable<ProfileLearningStateRow> {
  final String profileId;
  final String stateJson;
  final DateTime updatedAt;
  const ProfileLearningStateRow({
    required this.profileId,
    required this.stateJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['profile_id'] = Variable<String>(profileId);
    map['state_json'] = Variable<String>(stateJson);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProfileLearningStatesCompanion toCompanion(bool nullToAbsent) {
    return ProfileLearningStatesCompanion(
      profileId: Value(profileId),
      stateJson: Value(stateJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory ProfileLearningStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProfileLearningStateRow(
      profileId: serializer.fromJson<String>(json['profileId']),
      stateJson: serializer.fromJson<String>(json['stateJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'profileId': serializer.toJson<String>(profileId),
      'stateJson': serializer.toJson<String>(stateJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  ProfileLearningStateRow copyWith({
    String? profileId,
    String? stateJson,
    DateTime? updatedAt,
  }) => ProfileLearningStateRow(
    profileId: profileId ?? this.profileId,
    stateJson: stateJson ?? this.stateJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  ProfileLearningStateRow copyWithCompanion(
    ProfileLearningStatesCompanion data,
  ) {
    return ProfileLearningStateRow(
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      stateJson: data.stateJson.present ? data.stateJson.value : this.stateJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProfileLearningStateRow(')
          ..write('profileId: $profileId, ')
          ..write('stateJson: $stateJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(profileId, stateJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileLearningStateRow &&
          other.profileId == this.profileId &&
          other.stateJson == this.stateJson &&
          other.updatedAt == this.updatedAt);
}

class ProfileLearningStatesCompanion
    extends UpdateCompanion<ProfileLearningStateRow> {
  final Value<String> profileId;
  final Value<String> stateJson;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProfileLearningStatesCompanion({
    this.profileId = const Value.absent(),
    this.stateJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProfileLearningStatesCompanion.insert({
    required String profileId,
    required String stateJson,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : profileId = Value(profileId),
       stateJson = Value(stateJson),
       updatedAt = Value(updatedAt);
  static Insertable<ProfileLearningStateRow> custom({
    Expression<String>? profileId,
    Expression<String>? stateJson,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (profileId != null) 'profile_id': profileId,
      if (stateJson != null) 'state_json': stateJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProfileLearningStatesCompanion copyWith({
    Value<String>? profileId,
    Value<String>? stateJson,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return ProfileLearningStatesCompanion(
      profileId: profileId ?? this.profileId,
      stateJson: stateJson ?? this.stateJson,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (stateJson.present) {
      map['state_json'] = Variable<String>(stateJson.value);
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
    return (StringBuffer('ProfileLearningStatesCompanion(')
          ..write('profileId: $profileId, ')
          ..write('stateJson: $stateJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions
    with TableInfo<$SessionsTable, SessionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _interruptedRoundIdMeta =
      const VerificationMeta('interruptedRoundId');
  @override
  late final GeneratedColumn<String> interruptedRoundId =
      GeneratedColumn<String>(
        'interrupted_round_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    mode,
    status,
    interruptedRoundId,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('interrupted_round_id')) {
      context.handle(
        _interruptedRoundIdMeta,
        interruptedRoundId.isAcceptableOrUnknown(
          data['interrupted_round_id']!,
          _interruptedRoundIdMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      interruptedRoundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}interrupted_round_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class SessionRow extends DataClass implements Insertable<SessionRow> {
  final String id;
  final String mode;
  final String status;
  final String? interruptedRoundId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SessionRow({
    required this.id,
    required this.mode,
    required this.status,
    this.interruptedRoundId,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['mode'] = Variable<String>(mode);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || interruptedRoundId != null) {
      map['interrupted_round_id'] = Variable<String>(interruptedRoundId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      mode: Value(mode),
      status: Value(status),
      interruptedRoundId: interruptedRoundId == null && nullToAbsent
          ? const Value.absent()
          : Value(interruptedRoundId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SessionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionRow(
      id: serializer.fromJson<String>(json['id']),
      mode: serializer.fromJson<String>(json['mode']),
      status: serializer.fromJson<String>(json['status']),
      interruptedRoundId: serializer.fromJson<String?>(
        json['interruptedRoundId'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'mode': serializer.toJson<String>(mode),
      'status': serializer.toJson<String>(status),
      'interruptedRoundId': serializer.toJson<String?>(interruptedRoundId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SessionRow copyWith({
    String? id,
    String? mode,
    String? status,
    Value<String?> interruptedRoundId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SessionRow(
    id: id ?? this.id,
    mode: mode ?? this.mode,
    status: status ?? this.status,
    interruptedRoundId: interruptedRoundId.present
        ? interruptedRoundId.value
        : this.interruptedRoundId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SessionRow copyWithCompanion(SessionsCompanion data) {
    return SessionRow(
      id: data.id.present ? data.id.value : this.id,
      mode: data.mode.present ? data.mode.value : this.mode,
      status: data.status.present ? data.status.value : this.status,
      interruptedRoundId: data.interruptedRoundId.present
          ? data.interruptedRoundId.value
          : this.interruptedRoundId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionRow(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('status: $status, ')
          ..write('interruptedRoundId: $interruptedRoundId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, mode, status, interruptedRoundId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionRow &&
          other.id == this.id &&
          other.mode == this.mode &&
          other.status == this.status &&
          other.interruptedRoundId == this.interruptedRoundId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SessionsCompanion extends UpdateCompanion<SessionRow> {
  final Value<String> id;
  final Value<String> mode;
  final Value<String> status;
  final Value<String?> interruptedRoundId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.mode = const Value.absent(),
    this.status = const Value.absent(),
    this.interruptedRoundId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String mode,
    required String status,
    this.interruptedRoundId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       mode = Value(mode),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SessionRow> custom({
    Expression<String>? id,
    Expression<String>? mode,
    Expression<String>? status,
    Expression<String>? interruptedRoundId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (mode != null) 'mode': mode,
      if (status != null) 'status': status,
      if (interruptedRoundId != null)
        'interrupted_round_id': interruptedRoundId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? mode,
    Value<String>? status,
    Value<String?>? interruptedRoundId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      interruptedRoundId: interruptedRoundId ?? this.interruptedRoundId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (interruptedRoundId.present) {
      map['interrupted_round_id'] = Variable<String>(interruptedRoundId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
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
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('mode: $mode, ')
          ..write('status: $status, ')
          ..write('interruptedRoundId: $interruptedRoundId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionPlayersTable extends SessionPlayers
    with TableInfo<$SessionPlayersTable, SessionPlayerRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionPlayersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playerIdMeta = const VerificationMeta(
    'playerId',
  );
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
    'player_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _profileIdMeta = const VerificationMeta(
    'profileId',
  );
  @override
  late final GeneratedColumn<String> profileId = GeneratedColumn<String>(
    'profile_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actionPointsMeta = const VerificationMeta(
    'actionPoints',
  );
  @override
  late final GeneratedColumn<int> actionPoints = GeneratedColumn<int>(
    'action_points',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _chiliLevelMeta = const VerificationMeta(
    'chiliLevel',
  );
  @override
  late final GeneratedColumn<int> chiliLevel = GeneratedColumn<int>(
    'chili_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _styleMeta = const VerificationMeta('style');
  @override
  late final GeneratedColumn<String> style = GeneratedColumn<String>(
    'style',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    playerId,
    profileId,
    actionPoints,
    chiliLevel,
    style,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_players';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionPlayerRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('player_id')) {
      context.handle(
        _playerIdMeta,
        playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('profile_id')) {
      context.handle(
        _profileIdMeta,
        profileId.isAcceptableOrUnknown(data['profile_id']!, _profileIdMeta),
      );
    }
    if (data.containsKey('action_points')) {
      context.handle(
        _actionPointsMeta,
        actionPoints.isAcceptableOrUnknown(
          data['action_points']!,
          _actionPointsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actionPointsMeta);
    }
    if (data.containsKey('chili_level')) {
      context.handle(
        _chiliLevelMeta,
        chiliLevel.isAcceptableOrUnknown(data['chili_level']!, _chiliLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_chiliLevelMeta);
    }
    if (data.containsKey('style')) {
      context.handle(
        _styleMeta,
        style.isAcceptableOrUnknown(data['style']!, _styleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, playerId};
  @override
  SessionPlayerRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionPlayerRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      playerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}player_id'],
      )!,
      profileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}profile_id'],
      ),
      actionPoints: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}action_points'],
      )!,
      chiliLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chili_level'],
      )!,
      style: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}style'],
      ),
    );
  }

  @override
  $SessionPlayersTable createAlias(String alias) {
    return $SessionPlayersTable(attachedDatabase, alias);
  }
}

class SessionPlayerRow extends DataClass
    implements Insertable<SessionPlayerRow> {
  final String sessionId;
  final String playerId;
  final String? profileId;
  final int actionPoints;
  final int chiliLevel;
  final String? style;
  const SessionPlayerRow({
    required this.sessionId,
    required this.playerId,
    this.profileId,
    required this.actionPoints,
    required this.chiliLevel,
    this.style,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['player_id'] = Variable<String>(playerId);
    if (!nullToAbsent || profileId != null) {
      map['profile_id'] = Variable<String>(profileId);
    }
    map['action_points'] = Variable<int>(actionPoints);
    map['chili_level'] = Variable<int>(chiliLevel);
    if (!nullToAbsent || style != null) {
      map['style'] = Variable<String>(style);
    }
    return map;
  }

  SessionPlayersCompanion toCompanion(bool nullToAbsent) {
    return SessionPlayersCompanion(
      sessionId: Value(sessionId),
      playerId: Value(playerId),
      profileId: profileId == null && nullToAbsent
          ? const Value.absent()
          : Value(profileId),
      actionPoints: Value(actionPoints),
      chiliLevel: Value(chiliLevel),
      style: style == null && nullToAbsent
          ? const Value.absent()
          : Value(style),
    );
  }

  factory SessionPlayerRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionPlayerRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      playerId: serializer.fromJson<String>(json['playerId']),
      profileId: serializer.fromJson<String?>(json['profileId']),
      actionPoints: serializer.fromJson<int>(json['actionPoints']),
      chiliLevel: serializer.fromJson<int>(json['chiliLevel']),
      style: serializer.fromJson<String?>(json['style']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'playerId': serializer.toJson<String>(playerId),
      'profileId': serializer.toJson<String?>(profileId),
      'actionPoints': serializer.toJson<int>(actionPoints),
      'chiliLevel': serializer.toJson<int>(chiliLevel),
      'style': serializer.toJson<String?>(style),
    };
  }

  SessionPlayerRow copyWith({
    String? sessionId,
    String? playerId,
    Value<String?> profileId = const Value.absent(),
    int? actionPoints,
    int? chiliLevel,
    Value<String?> style = const Value.absent(),
  }) => SessionPlayerRow(
    sessionId: sessionId ?? this.sessionId,
    playerId: playerId ?? this.playerId,
    profileId: profileId.present ? profileId.value : this.profileId,
    actionPoints: actionPoints ?? this.actionPoints,
    chiliLevel: chiliLevel ?? this.chiliLevel,
    style: style.present ? style.value : this.style,
  );
  SessionPlayerRow copyWithCompanion(SessionPlayersCompanion data) {
    return SessionPlayerRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      profileId: data.profileId.present ? data.profileId.value : this.profileId,
      actionPoints: data.actionPoints.present
          ? data.actionPoints.value
          : this.actionPoints,
      chiliLevel: data.chiliLevel.present
          ? data.chiliLevel.value
          : this.chiliLevel,
      style: data.style.present ? data.style.value : this.style,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionPlayerRow(')
          ..write('sessionId: $sessionId, ')
          ..write('playerId: $playerId, ')
          ..write('profileId: $profileId, ')
          ..write('actionPoints: $actionPoints, ')
          ..write('chiliLevel: $chiliLevel, ')
          ..write('style: $style')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    playerId,
    profileId,
    actionPoints,
    chiliLevel,
    style,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionPlayerRow &&
          other.sessionId == this.sessionId &&
          other.playerId == this.playerId &&
          other.profileId == this.profileId &&
          other.actionPoints == this.actionPoints &&
          other.chiliLevel == this.chiliLevel &&
          other.style == this.style);
}

class SessionPlayersCompanion extends UpdateCompanion<SessionPlayerRow> {
  final Value<String> sessionId;
  final Value<String> playerId;
  final Value<String?> profileId;
  final Value<int> actionPoints;
  final Value<int> chiliLevel;
  final Value<String?> style;
  final Value<int> rowid;
  const SessionPlayersCompanion({
    this.sessionId = const Value.absent(),
    this.playerId = const Value.absent(),
    this.profileId = const Value.absent(),
    this.actionPoints = const Value.absent(),
    this.chiliLevel = const Value.absent(),
    this.style = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionPlayersCompanion.insert({
    required String sessionId,
    required String playerId,
    this.profileId = const Value.absent(),
    required int actionPoints,
    required int chiliLevel,
    this.style = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       playerId = Value(playerId),
       actionPoints = Value(actionPoints),
       chiliLevel = Value(chiliLevel);
  static Insertable<SessionPlayerRow> custom({
    Expression<String>? sessionId,
    Expression<String>? playerId,
    Expression<String>? profileId,
    Expression<int>? actionPoints,
    Expression<int>? chiliLevel,
    Expression<String>? style,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (playerId != null) 'player_id': playerId,
      if (profileId != null) 'profile_id': profileId,
      if (actionPoints != null) 'action_points': actionPoints,
      if (chiliLevel != null) 'chili_level': chiliLevel,
      if (style != null) 'style': style,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionPlayersCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? playerId,
    Value<String?>? profileId,
    Value<int>? actionPoints,
    Value<int>? chiliLevel,
    Value<String?>? style,
    Value<int>? rowid,
  }) {
    return SessionPlayersCompanion(
      sessionId: sessionId ?? this.sessionId,
      playerId: playerId ?? this.playerId,
      profileId: profileId ?? this.profileId,
      actionPoints: actionPoints ?? this.actionPoints,
      chiliLevel: chiliLevel ?? this.chiliLevel,
      style: style ?? this.style,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (profileId.present) {
      map['profile_id'] = Variable<String>(profileId.value);
    }
    if (actionPoints.present) {
      map['action_points'] = Variable<int>(actionPoints.value);
    }
    if (chiliLevel.present) {
      map['chili_level'] = Variable<int>(chiliLevel.value);
    }
    if (style.present) {
      map['style'] = Variable<String>(style.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionPlayersCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('playerId: $playerId, ')
          ..write('profileId: $profileId, ')
          ..write('actionPoints: $actionPoints, ')
          ..write('chiliLevel: $chiliLevel, ')
          ..write('style: $style, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionCardsTable extends SessionCards
    with TableInfo<$SessionCardsTable, SessionCardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playerIdMeta = const VerificationMeta(
    'playerId',
  );
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
    'player_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<String> variantId = GeneratedColumn<String>(
    'variant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _zoneMeta = const VerificationMeta('zone');
  @override
  late final GeneratedColumn<String> zone = GeneratedColumn<String>(
    'zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lockedMeta = const VerificationMeta('locked');
  @override
  late final GeneratedColumn<bool> locked = GeneratedColumn<bool>(
    'locked',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("locked" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    playerId,
    cardId,
    variantId,
    zone,
    ordinal,
    locked,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionCardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('player_id')) {
      context.handle(
        _playerIdMeta,
        playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    }
    if (data.containsKey('zone')) {
      context.handle(
        _zoneMeta,
        zone.isAcceptableOrUnknown(data['zone']!, _zoneMeta),
      );
    } else if (isInserting) {
      context.missing(_zoneMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('locked')) {
      context.handle(
        _lockedMeta,
        locked.isAcceptableOrUnknown(data['locked']!, _lockedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, playerId, cardId};
  @override
  SessionCardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionCardRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      playerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}player_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_id'],
      ),
      zone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zone'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      locked: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}locked'],
      )!,
    );
  }

  @override
  $SessionCardsTable createAlias(String alias) {
    return $SessionCardsTable(attachedDatabase, alias);
  }
}

class SessionCardRow extends DataClass implements Insertable<SessionCardRow> {
  final String sessionId;
  final String playerId;
  final String cardId;
  final String? variantId;
  final String zone;
  final int ordinal;
  final bool locked;
  const SessionCardRow({
    required this.sessionId,
    required this.playerId,
    required this.cardId,
    this.variantId,
    required this.zone,
    required this.ordinal,
    required this.locked,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['player_id'] = Variable<String>(playerId);
    map['card_id'] = Variable<String>(cardId);
    if (!nullToAbsent || variantId != null) {
      map['variant_id'] = Variable<String>(variantId);
    }
    map['zone'] = Variable<String>(zone);
    map['ordinal'] = Variable<int>(ordinal);
    map['locked'] = Variable<bool>(locked);
    return map;
  }

  SessionCardsCompanion toCompanion(bool nullToAbsent) {
    return SessionCardsCompanion(
      sessionId: Value(sessionId),
      playerId: Value(playerId),
      cardId: Value(cardId),
      variantId: variantId == null && nullToAbsent
          ? const Value.absent()
          : Value(variantId),
      zone: Value(zone),
      ordinal: Value(ordinal),
      locked: Value(locked),
    );
  }

  factory SessionCardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionCardRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      playerId: serializer.fromJson<String>(json['playerId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      variantId: serializer.fromJson<String?>(json['variantId']),
      zone: serializer.fromJson<String>(json['zone']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      locked: serializer.fromJson<bool>(json['locked']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'playerId': serializer.toJson<String>(playerId),
      'cardId': serializer.toJson<String>(cardId),
      'variantId': serializer.toJson<String?>(variantId),
      'zone': serializer.toJson<String>(zone),
      'ordinal': serializer.toJson<int>(ordinal),
      'locked': serializer.toJson<bool>(locked),
    };
  }

  SessionCardRow copyWith({
    String? sessionId,
    String? playerId,
    String? cardId,
    Value<String?> variantId = const Value.absent(),
    String? zone,
    int? ordinal,
    bool? locked,
  }) => SessionCardRow(
    sessionId: sessionId ?? this.sessionId,
    playerId: playerId ?? this.playerId,
    cardId: cardId ?? this.cardId,
    variantId: variantId.present ? variantId.value : this.variantId,
    zone: zone ?? this.zone,
    ordinal: ordinal ?? this.ordinal,
    locked: locked ?? this.locked,
  );
  SessionCardRow copyWithCompanion(SessionCardsCompanion data) {
    return SessionCardRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      zone: data.zone.present ? data.zone.value : this.zone,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      locked: data.locked.present ? data.locked.value : this.locked,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionCardRow(')
          ..write('sessionId: $sessionId, ')
          ..write('playerId: $playerId, ')
          ..write('cardId: $cardId, ')
          ..write('variantId: $variantId, ')
          ..write('zone: $zone, ')
          ..write('ordinal: $ordinal, ')
          ..write('locked: $locked')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    playerId,
    cardId,
    variantId,
    zone,
    ordinal,
    locked,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionCardRow &&
          other.sessionId == this.sessionId &&
          other.playerId == this.playerId &&
          other.cardId == this.cardId &&
          other.variantId == this.variantId &&
          other.zone == this.zone &&
          other.ordinal == this.ordinal &&
          other.locked == this.locked);
}

class SessionCardsCompanion extends UpdateCompanion<SessionCardRow> {
  final Value<String> sessionId;
  final Value<String> playerId;
  final Value<String> cardId;
  final Value<String?> variantId;
  final Value<String> zone;
  final Value<int> ordinal;
  final Value<bool> locked;
  final Value<int> rowid;
  const SessionCardsCompanion({
    this.sessionId = const Value.absent(),
    this.playerId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.zone = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.locked = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionCardsCompanion.insert({
    required String sessionId,
    required String playerId,
    required String cardId,
    this.variantId = const Value.absent(),
    required String zone,
    required int ordinal,
    this.locked = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       playerId = Value(playerId),
       cardId = Value(cardId),
       zone = Value(zone),
       ordinal = Value(ordinal);
  static Insertable<SessionCardRow> custom({
    Expression<String>? sessionId,
    Expression<String>? playerId,
    Expression<String>? cardId,
    Expression<String>? variantId,
    Expression<String>? zone,
    Expression<int>? ordinal,
    Expression<bool>? locked,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (playerId != null) 'player_id': playerId,
      if (cardId != null) 'card_id': cardId,
      if (variantId != null) 'variant_id': variantId,
      if (zone != null) 'zone': zone,
      if (ordinal != null) 'ordinal': ordinal,
      if (locked != null) 'locked': locked,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionCardsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? playerId,
    Value<String>? cardId,
    Value<String?>? variantId,
    Value<String>? zone,
    Value<int>? ordinal,
    Value<bool>? locked,
    Value<int>? rowid,
  }) {
    return SessionCardsCompanion(
      sessionId: sessionId ?? this.sessionId,
      playerId: playerId ?? this.playerId,
      cardId: cardId ?? this.cardId,
      variantId: variantId ?? this.variantId,
      zone: zone ?? this.zone,
      ordinal: ordinal ?? this.ordinal,
      locked: locked ?? this.locked,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<String>(variantId.value);
    }
    if (zone.present) {
      map['zone'] = Variable<String>(zone.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (locked.present) {
      map['locked'] = Variable<bool>(locked.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionCardsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('playerId: $playerId, ')
          ..write('cardId: $cardId, ')
          ..write('variantId: $variantId, ')
          ..write('zone: $zone, ')
          ..write('ordinal: $ordinal, ')
          ..write('locked: $locked, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoundsTable extends Rounds with TableInfo<$RoundsTable, RoundRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoundsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roundIdMeta = const VerificationMeta(
    'roundId',
  );
  @override
  late final GeneratedColumn<String> roundId = GeneratedColumn<String>(
    'round_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateJsonMeta = const VerificationMeta(
    'stateJson',
  );
  @override
  late final GeneratedColumn<String> stateJson = GeneratedColumn<String>(
    'state_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    roundId,
    ordinal,
    status,
    stateJson,
    startedAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rounds';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoundRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('round_id')) {
      context.handle(
        _roundIdMeta,
        roundId.isAcceptableOrUnknown(data['round_id']!, _roundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roundIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('state_json')) {
      context.handle(
        _stateJsonMeta,
        stateJson.isAcceptableOrUnknown(data['state_json']!, _stateJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_stateJsonMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, roundId};
  @override
  RoundRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoundRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      roundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}round_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      stateJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state_json'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RoundsTable createAlias(String alias) {
    return $RoundsTable(attachedDatabase, alias);
  }
}

class RoundRow extends DataClass implements Insertable<RoundRow> {
  final String sessionId;
  final String roundId;
  final int ordinal;
  final String status;
  final String stateJson;
  final DateTime startedAt;
  final DateTime updatedAt;
  const RoundRow({
    required this.sessionId,
    required this.roundId,
    required this.ordinal,
    required this.status,
    required this.stateJson,
    required this.startedAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['round_id'] = Variable<String>(roundId);
    map['ordinal'] = Variable<int>(ordinal);
    map['status'] = Variable<String>(status);
    map['state_json'] = Variable<String>(stateJson);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RoundsCompanion toCompanion(bool nullToAbsent) {
    return RoundsCompanion(
      sessionId: Value(sessionId),
      roundId: Value(roundId),
      ordinal: Value(ordinal),
      status: Value(status),
      stateJson: Value(stateJson),
      startedAt: Value(startedAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory RoundRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoundRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      roundId: serializer.fromJson<String>(json['roundId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      status: serializer.fromJson<String>(json['status']),
      stateJson: serializer.fromJson<String>(json['stateJson']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'roundId': serializer.toJson<String>(roundId),
      'ordinal': serializer.toJson<int>(ordinal),
      'status': serializer.toJson<String>(status),
      'stateJson': serializer.toJson<String>(stateJson),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RoundRow copyWith({
    String? sessionId,
    String? roundId,
    int? ordinal,
    String? status,
    String? stateJson,
    DateTime? startedAt,
    DateTime? updatedAt,
  }) => RoundRow(
    sessionId: sessionId ?? this.sessionId,
    roundId: roundId ?? this.roundId,
    ordinal: ordinal ?? this.ordinal,
    status: status ?? this.status,
    stateJson: stateJson ?? this.stateJson,
    startedAt: startedAt ?? this.startedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RoundRow copyWithCompanion(RoundsCompanion data) {
    return RoundRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      roundId: data.roundId.present ? data.roundId.value : this.roundId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      status: data.status.present ? data.status.value : this.status,
      stateJson: data.stateJson.present ? data.stateJson.value : this.stateJson,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoundRow(')
          ..write('sessionId: $sessionId, ')
          ..write('roundId: $roundId, ')
          ..write('ordinal: $ordinal, ')
          ..write('status: $status, ')
          ..write('stateJson: $stateJson, ')
          ..write('startedAt: $startedAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    roundId,
    ordinal,
    status,
    stateJson,
    startedAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoundRow &&
          other.sessionId == this.sessionId &&
          other.roundId == this.roundId &&
          other.ordinal == this.ordinal &&
          other.status == this.status &&
          other.stateJson == this.stateJson &&
          other.startedAt == this.startedAt &&
          other.updatedAt == this.updatedAt);
}

class RoundsCompanion extends UpdateCompanion<RoundRow> {
  final Value<String> sessionId;
  final Value<String> roundId;
  final Value<int> ordinal;
  final Value<String> status;
  final Value<String> stateJson;
  final Value<DateTime> startedAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RoundsCompanion({
    this.sessionId = const Value.absent(),
    this.roundId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.status = const Value.absent(),
    this.stateJson = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoundsCompanion.insert({
    required String sessionId,
    required String roundId,
    required int ordinal,
    required String status,
    required String stateJson,
    required DateTime startedAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       roundId = Value(roundId),
       ordinal = Value(ordinal),
       status = Value(status),
       stateJson = Value(stateJson),
       startedAt = Value(startedAt),
       updatedAt = Value(updatedAt);
  static Insertable<RoundRow> custom({
    Expression<String>? sessionId,
    Expression<String>? roundId,
    Expression<int>? ordinal,
    Expression<String>? status,
    Expression<String>? stateJson,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (roundId != null) 'round_id': roundId,
      if (ordinal != null) 'ordinal': ordinal,
      if (status != null) 'status': status,
      if (stateJson != null) 'state_json': stateJson,
      if (startedAt != null) 'started_at': startedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoundsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? roundId,
    Value<int>? ordinal,
    Value<String>? status,
    Value<String>? stateJson,
    Value<DateTime>? startedAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RoundsCompanion(
      sessionId: sessionId ?? this.sessionId,
      roundId: roundId ?? this.roundId,
      ordinal: ordinal ?? this.ordinal,
      status: status ?? this.status,
      stateJson: stateJson ?? this.stateJson,
      startedAt: startedAt ?? this.startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (roundId.present) {
      map['round_id'] = Variable<String>(roundId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (stateJson.present) {
      map['state_json'] = Variable<String>(stateJson.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
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
    return (StringBuffer('RoundsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('roundId: $roundId, ')
          ..write('ordinal: $ordinal, ')
          ..write('status: $status, ')
          ..write('stateJson: $stateJson, ')
          ..write('startedAt: $startedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CombatValueSnapshotsTable extends CombatValueSnapshots
    with TableInfo<$CombatValueSnapshotsTable, CombatValueSnapshotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CombatValueSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roundIdMeta = const VerificationMeta(
    'roundId',
  );
  @override
  late final GeneratedColumn<String> roundId = GeneratedColumn<String>(
    'round_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playerIdMeta = const VerificationMeta(
    'playerId',
  );
  @override
  late final GeneratedColumn<String> playerId = GeneratedColumn<String>(
    'player_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _variantIdMeta = const VerificationMeta(
    'variantId',
  );
  @override
  late final GeneratedColumn<String> variantId = GeneratedColumn<String>(
    'variant_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleAtCommitMeta = const VerificationMeta(
    'roleAtCommit',
  );
  @override
  late final GeneratedColumn<String> roleAtCommit = GeneratedColumn<String>(
    'role_at_commit',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personalValueMeta = const VerificationMeta(
    'personalValue',
  );
  @override
  late final GeneratedColumn<int> personalValue = GeneratedColumn<int>(
    'personal_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _committedAtMeta = const VerificationMeta(
    'committedAt',
  );
  @override
  late final GeneratedColumn<DateTime> committedAt = GeneratedColumn<DateTime>(
    'committed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    roundId,
    playerId,
    cardId,
    variantId,
    roleAtCommit,
    personalValue,
    committedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'combat_value_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CombatValueSnapshotRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('round_id')) {
      context.handle(
        _roundIdMeta,
        roundId.isAcceptableOrUnknown(data['round_id']!, _roundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roundIdMeta);
    }
    if (data.containsKey('player_id')) {
      context.handle(
        _playerIdMeta,
        playerId.isAcceptableOrUnknown(data['player_id']!, _playerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playerIdMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('variant_id')) {
      context.handle(
        _variantIdMeta,
        variantId.isAcceptableOrUnknown(data['variant_id']!, _variantIdMeta),
      );
    } else if (isInserting) {
      context.missing(_variantIdMeta);
    }
    if (data.containsKey('role_at_commit')) {
      context.handle(
        _roleAtCommitMeta,
        roleAtCommit.isAcceptableOrUnknown(
          data['role_at_commit']!,
          _roleAtCommitMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_roleAtCommitMeta);
    }
    if (data.containsKey('personal_value')) {
      context.handle(
        _personalValueMeta,
        personalValue.isAcceptableOrUnknown(
          data['personal_value']!,
          _personalValueMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_personalValueMeta);
    }
    if (data.containsKey('committed_at')) {
      context.handle(
        _committedAtMeta,
        committedAt.isAcceptableOrUnknown(
          data['committed_at']!,
          _committedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_committedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, roundId, playerId};
  @override
  CombatValueSnapshotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CombatValueSnapshotRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      roundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}round_id'],
      )!,
      playerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}player_id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      variantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}variant_id'],
      )!,
      roleAtCommit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role_at_commit'],
      )!,
      personalValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}personal_value'],
      )!,
      committedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}committed_at'],
      )!,
    );
  }

  @override
  $CombatValueSnapshotsTable createAlias(String alias) {
    return $CombatValueSnapshotsTable(attachedDatabase, alias);
  }
}

class CombatValueSnapshotRow extends DataClass
    implements Insertable<CombatValueSnapshotRow> {
  final String sessionId;
  final String roundId;
  final String playerId;
  final String cardId;
  final String variantId;
  final String roleAtCommit;
  final int personalValue;
  final DateTime committedAt;
  const CombatValueSnapshotRow({
    required this.sessionId,
    required this.roundId,
    required this.playerId,
    required this.cardId,
    required this.variantId,
    required this.roleAtCommit,
    required this.personalValue,
    required this.committedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['round_id'] = Variable<String>(roundId);
    map['player_id'] = Variable<String>(playerId);
    map['card_id'] = Variable<String>(cardId);
    map['variant_id'] = Variable<String>(variantId);
    map['role_at_commit'] = Variable<String>(roleAtCommit);
    map['personal_value'] = Variable<int>(personalValue);
    map['committed_at'] = Variable<DateTime>(committedAt);
    return map;
  }

  CombatValueSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return CombatValueSnapshotsCompanion(
      sessionId: Value(sessionId),
      roundId: Value(roundId),
      playerId: Value(playerId),
      cardId: Value(cardId),
      variantId: Value(variantId),
      roleAtCommit: Value(roleAtCommit),
      personalValue: Value(personalValue),
      committedAt: Value(committedAt),
    );
  }

  factory CombatValueSnapshotRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CombatValueSnapshotRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      roundId: serializer.fromJson<String>(json['roundId']),
      playerId: serializer.fromJson<String>(json['playerId']),
      cardId: serializer.fromJson<String>(json['cardId']),
      variantId: serializer.fromJson<String>(json['variantId']),
      roleAtCommit: serializer.fromJson<String>(json['roleAtCommit']),
      personalValue: serializer.fromJson<int>(json['personalValue']),
      committedAt: serializer.fromJson<DateTime>(json['committedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'roundId': serializer.toJson<String>(roundId),
      'playerId': serializer.toJson<String>(playerId),
      'cardId': serializer.toJson<String>(cardId),
      'variantId': serializer.toJson<String>(variantId),
      'roleAtCommit': serializer.toJson<String>(roleAtCommit),
      'personalValue': serializer.toJson<int>(personalValue),
      'committedAt': serializer.toJson<DateTime>(committedAt),
    };
  }

  CombatValueSnapshotRow copyWith({
    String? sessionId,
    String? roundId,
    String? playerId,
    String? cardId,
    String? variantId,
    String? roleAtCommit,
    int? personalValue,
    DateTime? committedAt,
  }) => CombatValueSnapshotRow(
    sessionId: sessionId ?? this.sessionId,
    roundId: roundId ?? this.roundId,
    playerId: playerId ?? this.playerId,
    cardId: cardId ?? this.cardId,
    variantId: variantId ?? this.variantId,
    roleAtCommit: roleAtCommit ?? this.roleAtCommit,
    personalValue: personalValue ?? this.personalValue,
    committedAt: committedAt ?? this.committedAt,
  );
  CombatValueSnapshotRow copyWithCompanion(CombatValueSnapshotsCompanion data) {
    return CombatValueSnapshotRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      roundId: data.roundId.present ? data.roundId.value : this.roundId,
      playerId: data.playerId.present ? data.playerId.value : this.playerId,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      variantId: data.variantId.present ? data.variantId.value : this.variantId,
      roleAtCommit: data.roleAtCommit.present
          ? data.roleAtCommit.value
          : this.roleAtCommit,
      personalValue: data.personalValue.present
          ? data.personalValue.value
          : this.personalValue,
      committedAt: data.committedAt.present
          ? data.committedAt.value
          : this.committedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CombatValueSnapshotRow(')
          ..write('sessionId: $sessionId, ')
          ..write('roundId: $roundId, ')
          ..write('playerId: $playerId, ')
          ..write('cardId: $cardId, ')
          ..write('variantId: $variantId, ')
          ..write('roleAtCommit: $roleAtCommit, ')
          ..write('personalValue: $personalValue, ')
          ..write('committedAt: $committedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    roundId,
    playerId,
    cardId,
    variantId,
    roleAtCommit,
    personalValue,
    committedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CombatValueSnapshotRow &&
          other.sessionId == this.sessionId &&
          other.roundId == this.roundId &&
          other.playerId == this.playerId &&
          other.cardId == this.cardId &&
          other.variantId == this.variantId &&
          other.roleAtCommit == this.roleAtCommit &&
          other.personalValue == this.personalValue &&
          other.committedAt == this.committedAt);
}

class CombatValueSnapshotsCompanion
    extends UpdateCompanion<CombatValueSnapshotRow> {
  final Value<String> sessionId;
  final Value<String> roundId;
  final Value<String> playerId;
  final Value<String> cardId;
  final Value<String> variantId;
  final Value<String> roleAtCommit;
  final Value<int> personalValue;
  final Value<DateTime> committedAt;
  final Value<int> rowid;
  const CombatValueSnapshotsCompanion({
    this.sessionId = const Value.absent(),
    this.roundId = const Value.absent(),
    this.playerId = const Value.absent(),
    this.cardId = const Value.absent(),
    this.variantId = const Value.absent(),
    this.roleAtCommit = const Value.absent(),
    this.personalValue = const Value.absent(),
    this.committedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CombatValueSnapshotsCompanion.insert({
    required String sessionId,
    required String roundId,
    required String playerId,
    required String cardId,
    required String variantId,
    required String roleAtCommit,
    required int personalValue,
    required DateTime committedAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       roundId = Value(roundId),
       playerId = Value(playerId),
       cardId = Value(cardId),
       variantId = Value(variantId),
       roleAtCommit = Value(roleAtCommit),
       personalValue = Value(personalValue),
       committedAt = Value(committedAt);
  static Insertable<CombatValueSnapshotRow> custom({
    Expression<String>? sessionId,
    Expression<String>? roundId,
    Expression<String>? playerId,
    Expression<String>? cardId,
    Expression<String>? variantId,
    Expression<String>? roleAtCommit,
    Expression<int>? personalValue,
    Expression<DateTime>? committedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (roundId != null) 'round_id': roundId,
      if (playerId != null) 'player_id': playerId,
      if (cardId != null) 'card_id': cardId,
      if (variantId != null) 'variant_id': variantId,
      if (roleAtCommit != null) 'role_at_commit': roleAtCommit,
      if (personalValue != null) 'personal_value': personalValue,
      if (committedAt != null) 'committed_at': committedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CombatValueSnapshotsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? roundId,
    Value<String>? playerId,
    Value<String>? cardId,
    Value<String>? variantId,
    Value<String>? roleAtCommit,
    Value<int>? personalValue,
    Value<DateTime>? committedAt,
    Value<int>? rowid,
  }) {
    return CombatValueSnapshotsCompanion(
      sessionId: sessionId ?? this.sessionId,
      roundId: roundId ?? this.roundId,
      playerId: playerId ?? this.playerId,
      cardId: cardId ?? this.cardId,
      variantId: variantId ?? this.variantId,
      roleAtCommit: roleAtCommit ?? this.roleAtCommit,
      personalValue: personalValue ?? this.personalValue,
      committedAt: committedAt ?? this.committedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (roundId.present) {
      map['round_id'] = Variable<String>(roundId.value);
    }
    if (playerId.present) {
      map['player_id'] = Variable<String>(playerId.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (variantId.present) {
      map['variant_id'] = Variable<String>(variantId.value);
    }
    if (roleAtCommit.present) {
      map['role_at_commit'] = Variable<String>(roleAtCommit.value);
    }
    if (personalValue.present) {
      map['personal_value'] = Variable<int>(personalValue.value);
    }
    if (committedAt.present) {
      map['committed_at'] = Variable<DateTime>(committedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CombatValueSnapshotsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('roundId: $roundId, ')
          ..write('playerId: $playerId, ')
          ..write('cardId: $cardId, ')
          ..write('variantId: $variantId, ')
          ..write('roleAtCommit: $roleAtCommit, ')
          ..write('personalValue: $personalValue, ')
          ..write('committedAt: $committedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventLogsTable extends EventLogs
    with TableInfo<$EventLogsTable, EventLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    eventId,
    sequence,
    type,
    payloadJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, eventId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId, sequence},
  ];
  @override
  EventLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventLogRow(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $EventLogsTable createAlias(String alias) {
    return $EventLogsTable(attachedDatabase, alias);
  }
}

class EventLogRow extends DataClass implements Insertable<EventLogRow> {
  final String sessionId;
  final String eventId;
  final int sequence;
  final String type;
  final String payloadJson;
  final DateTime createdAt;
  const EventLogRow({
    required this.sessionId,
    required this.eventId,
    required this.sequence,
    required this.type,
    required this.payloadJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['event_id'] = Variable<String>(eventId);
    map['sequence'] = Variable<int>(sequence);
    map['type'] = Variable<String>(type);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  EventLogsCompanion toCompanion(bool nullToAbsent) {
    return EventLogsCompanion(
      sessionId: Value(sessionId),
      eventId: Value(eventId),
      sequence: Value(sequence),
      type: Value(type),
      payloadJson: Value(payloadJson),
      createdAt: Value(createdAt),
    );
  }

  factory EventLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventLogRow(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      eventId: serializer.fromJson<String>(json['eventId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      type: serializer.fromJson<String>(json['type']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'eventId': serializer.toJson<String>(eventId),
      'sequence': serializer.toJson<int>(sequence),
      'type': serializer.toJson<String>(type),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  EventLogRow copyWith({
    String? sessionId,
    String? eventId,
    int? sequence,
    String? type,
    String? payloadJson,
    DateTime? createdAt,
  }) => EventLogRow(
    sessionId: sessionId ?? this.sessionId,
    eventId: eventId ?? this.eventId,
    sequence: sequence ?? this.sequence,
    type: type ?? this.type,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAt: createdAt ?? this.createdAt,
  );
  EventLogRow copyWithCompanion(EventLogsCompanion data) {
    return EventLogRow(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      type: data.type.present ? data.type.value : this.type,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventLogRow(')
          ..write('sessionId: $sessionId, ')
          ..write('eventId: $eventId, ')
          ..write('sequence: $sequence, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, eventId, sequence, type, payloadJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventLogRow &&
          other.sessionId == this.sessionId &&
          other.eventId == this.eventId &&
          other.sequence == this.sequence &&
          other.type == this.type &&
          other.payloadJson == this.payloadJson &&
          other.createdAt == this.createdAt);
}

class EventLogsCompanion extends UpdateCompanion<EventLogRow> {
  final Value<String> sessionId;
  final Value<String> eventId;
  final Value<int> sequence;
  final Value<String> type;
  final Value<String> payloadJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const EventLogsCompanion({
    this.sessionId = const Value.absent(),
    this.eventId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.type = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventLogsCompanion.insert({
    required String sessionId,
    required String eventId,
    required int sequence,
    required String type,
    required String payloadJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       eventId = Value(eventId),
       sequence = Value(sequence),
       type = Value(type),
       payloadJson = Value(payloadJson),
       createdAt = Value(createdAt);
  static Insertable<EventLogRow> custom({
    Expression<String>? sessionId,
    Expression<String>? eventId,
    Expression<int>? sequence,
    Expression<String>? type,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (eventId != null) 'event_id': eventId,
      if (sequence != null) 'sequence': sequence,
      if (type != null) 'type': type,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventLogsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? eventId,
    Value<int>? sequence,
    Value<String>? type,
    Value<String>? payloadJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return EventLogsCompanion(
      sessionId: sessionId ?? this.sessionId,
      eventId: eventId ?? this.eventId,
      sequence: sequence ?? this.sequence,
      type: type ?? this.type,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventLogsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('eventId: $eventId, ')
          ..write('sequence: $sequence, ')
          ..write('type: $type, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatalogDocumentsTable extends CatalogDocuments
    with TableInfo<$CatalogDocumentsTable, CatalogDocumentRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatalogDocumentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _documentIdMeta = const VerificationMeta(
    'documentId',
  );
  @override
  late final GeneratedColumn<String> documentId = GeneratedColumn<String>(
    'document_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _schemaVersionMeta = const VerificationMeta(
    'schemaVersion',
  );
  @override
  late final GeneratedColumn<int> schemaVersion = GeneratedColumn<int>(
    'schema_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _catalogVersionMeta = const VerificationMeta(
    'catalogVersion',
  );
  @override
  late final GeneratedColumn<String> catalogVersion = GeneratedColumn<String>(
    'catalog_version',
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
  static const VerificationMeta _installedAtMeta = const VerificationMeta(
    'installedAt',
  );
  @override
  late final GeneratedColumn<DateTime> installedAt = GeneratedColumn<DateTime>(
    'installed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    documentId,
    schemaVersion,
    catalogVersion,
    json,
    installedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'catalog_documents';
  @override
  VerificationContext validateIntegrity(
    Insertable<CatalogDocumentRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('document_id')) {
      context.handle(
        _documentIdMeta,
        documentId.isAcceptableOrUnknown(data['document_id']!, _documentIdMeta),
      );
    } else if (isInserting) {
      context.missing(_documentIdMeta);
    }
    if (data.containsKey('schema_version')) {
      context.handle(
        _schemaVersionMeta,
        schemaVersion.isAcceptableOrUnknown(
          data['schema_version']!,
          _schemaVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_schemaVersionMeta);
    }
    if (data.containsKey('catalog_version')) {
      context.handle(
        _catalogVersionMeta,
        catalogVersion.isAcceptableOrUnknown(
          data['catalog_version']!,
          _catalogVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_catalogVersionMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
        _jsonMeta,
        json.isAcceptableOrUnknown(data['json']!, _jsonMeta),
      );
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    if (data.containsKey('installed_at')) {
      context.handle(
        _installedAtMeta,
        installedAt.isAcceptableOrUnknown(
          data['installed_at']!,
          _installedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {documentId};
  @override
  CatalogDocumentRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatalogDocumentRow(
      documentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}document_id'],
      )!,
      schemaVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}schema_version'],
      )!,
      catalogVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}catalog_version'],
      )!,
      json: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}json'],
      )!,
      installedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at'],
      )!,
    );
  }

  @override
  $CatalogDocumentsTable createAlias(String alias) {
    return $CatalogDocumentsTable(attachedDatabase, alias);
  }
}

class CatalogDocumentRow extends DataClass
    implements Insertable<CatalogDocumentRow> {
  final String documentId;
  final int schemaVersion;
  final String catalogVersion;
  final String json;
  final DateTime installedAt;
  const CatalogDocumentRow({
    required this.documentId,
    required this.schemaVersion,
    required this.catalogVersion,
    required this.json,
    required this.installedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['document_id'] = Variable<String>(documentId);
    map['schema_version'] = Variable<int>(schemaVersion);
    map['catalog_version'] = Variable<String>(catalogVersion);
    map['json'] = Variable<String>(json);
    map['installed_at'] = Variable<DateTime>(installedAt);
    return map;
  }

  CatalogDocumentsCompanion toCompanion(bool nullToAbsent) {
    return CatalogDocumentsCompanion(
      documentId: Value(documentId),
      schemaVersion: Value(schemaVersion),
      catalogVersion: Value(catalogVersion),
      json: Value(json),
      installedAt: Value(installedAt),
    );
  }

  factory CatalogDocumentRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatalogDocumentRow(
      documentId: serializer.fromJson<String>(json['documentId']),
      schemaVersion: serializer.fromJson<int>(json['schemaVersion']),
      catalogVersion: serializer.fromJson<String>(json['catalogVersion']),
      json: serializer.fromJson<String>(json['json']),
      installedAt: serializer.fromJson<DateTime>(json['installedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'documentId': serializer.toJson<String>(documentId),
      'schemaVersion': serializer.toJson<int>(schemaVersion),
      'catalogVersion': serializer.toJson<String>(catalogVersion),
      'json': serializer.toJson<String>(json),
      'installedAt': serializer.toJson<DateTime>(installedAt),
    };
  }

  CatalogDocumentRow copyWith({
    String? documentId,
    int? schemaVersion,
    String? catalogVersion,
    String? json,
    DateTime? installedAt,
  }) => CatalogDocumentRow(
    documentId: documentId ?? this.documentId,
    schemaVersion: schemaVersion ?? this.schemaVersion,
    catalogVersion: catalogVersion ?? this.catalogVersion,
    json: json ?? this.json,
    installedAt: installedAt ?? this.installedAt,
  );
  CatalogDocumentRow copyWithCompanion(CatalogDocumentsCompanion data) {
    return CatalogDocumentRow(
      documentId: data.documentId.present
          ? data.documentId.value
          : this.documentId,
      schemaVersion: data.schemaVersion.present
          ? data.schemaVersion.value
          : this.schemaVersion,
      catalogVersion: data.catalogVersion.present
          ? data.catalogVersion.value
          : this.catalogVersion,
      json: data.json.present ? data.json.value : this.json,
      installedAt: data.installedAt.present
          ? data.installedAt.value
          : this.installedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatalogDocumentRow(')
          ..write('documentId: $documentId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('json: $json, ')
          ..write('installedAt: $installedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(documentId, schemaVersion, catalogVersion, json, installedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CatalogDocumentRow &&
          other.documentId == this.documentId &&
          other.schemaVersion == this.schemaVersion &&
          other.catalogVersion == this.catalogVersion &&
          other.json == this.json &&
          other.installedAt == this.installedAt);
}

class CatalogDocumentsCompanion extends UpdateCompanion<CatalogDocumentRow> {
  final Value<String> documentId;
  final Value<int> schemaVersion;
  final Value<String> catalogVersion;
  final Value<String> json;
  final Value<DateTime> installedAt;
  final Value<int> rowid;
  const CatalogDocumentsCompanion({
    this.documentId = const Value.absent(),
    this.schemaVersion = const Value.absent(),
    this.catalogVersion = const Value.absent(),
    this.json = const Value.absent(),
    this.installedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatalogDocumentsCompanion.insert({
    required String documentId,
    required int schemaVersion,
    required String catalogVersion,
    required String json,
    required DateTime installedAt,
    this.rowid = const Value.absent(),
  }) : documentId = Value(documentId),
       schemaVersion = Value(schemaVersion),
       catalogVersion = Value(catalogVersion),
       json = Value(json),
       installedAt = Value(installedAt);
  static Insertable<CatalogDocumentRow> custom({
    Expression<String>? documentId,
    Expression<int>? schemaVersion,
    Expression<String>? catalogVersion,
    Expression<String>? json,
    Expression<DateTime>? installedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (documentId != null) 'document_id': documentId,
      if (schemaVersion != null) 'schema_version': schemaVersion,
      if (catalogVersion != null) 'catalog_version': catalogVersion,
      if (json != null) 'json': json,
      if (installedAt != null) 'installed_at': installedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatalogDocumentsCompanion copyWith({
    Value<String>? documentId,
    Value<int>? schemaVersion,
    Value<String>? catalogVersion,
    Value<String>? json,
    Value<DateTime>? installedAt,
    Value<int>? rowid,
  }) {
    return CatalogDocumentsCompanion(
      documentId: documentId ?? this.documentId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      catalogVersion: catalogVersion ?? this.catalogVersion,
      json: json ?? this.json,
      installedAt: installedAt ?? this.installedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (documentId.present) {
      map['document_id'] = Variable<String>(documentId.value);
    }
    if (schemaVersion.present) {
      map['schema_version'] = Variable<int>(schemaVersion.value);
    }
    if (catalogVersion.present) {
      map['catalog_version'] = Variable<String>(catalogVersion.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (installedAt.present) {
      map['installed_at'] = Variable<DateTime>(installedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatalogDocumentsCompanion(')
          ..write('documentId: $documentId, ')
          ..write('schemaVersion: $schemaVersion, ')
          ..write('catalogVersion: $catalogVersion, ')
          ..write('json: $json, ')
          ..write('installedAt: $installedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ProfilesTable profiles = $ProfilesTable(this);
  late final $UserPreferencesTable userPreferences = $UserPreferencesTable(
    this,
  );
  late final $CardPreferenceOverridesTable cardPreferenceOverrides =
      $CardPreferenceOverridesTable(this);
  late final $ProfileEvolutionEntriesTable profileEvolutionEntries =
      $ProfileEvolutionEntriesTable(this);
  late final $ProfileLearningStatesTable profileLearningStates =
      $ProfileLearningStatesTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $SessionPlayersTable sessionPlayers = $SessionPlayersTable(this);
  late final $SessionCardsTable sessionCards = $SessionCardsTable(this);
  late final $RoundsTable rounds = $RoundsTable(this);
  late final $CombatValueSnapshotsTable combatValueSnapshots =
      $CombatValueSnapshotsTable(this);
  late final $EventLogsTable eventLogs = $EventLogsTable(this);
  late final $CatalogDocumentsTable catalogDocuments = $CatalogDocumentsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    profiles,
    userPreferences,
    cardPreferenceOverrides,
    profileEvolutionEntries,
    profileLearningStates,
    sessions,
    sessionPlayers,
    sessionCards,
    rounds,
    combatValueSnapshots,
    eventLogs,
    catalogDocuments,
  ];
}

typedef $$ProfilesTableCreateCompanionBuilder =
    ProfilesCompanion Function({
      required String id,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProfilesTableUpdateCompanionBuilder =
    ProfilesCompanion Function({
      Value<String> id,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ProfilesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfilesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfilesTable> {
  $$ProfilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProfilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfilesTable,
          ProfileRow,
          $$ProfilesTableFilterComposer,
          $$ProfilesTableOrderingComposer,
          $$ProfilesTableAnnotationComposer,
          $$ProfilesTableCreateCompanionBuilder,
          $$ProfilesTableUpdateCompanionBuilder,
          (
            ProfileRow,
            BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>,
          ),
          ProfileRow,
          PrefetchHooks Function()
        > {
  $$ProfilesTableTableManager(_$AppDatabase db, $ProfilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion(
                id: id,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProfilesCompanion.insert(
                id: id,
                createdAt: createdAt,
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

typedef $$ProfilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfilesTable,
      ProfileRow,
      $$ProfilesTableFilterComposer,
      $$ProfilesTableOrderingComposer,
      $$ProfilesTableAnnotationComposer,
      $$ProfilesTableCreateCompanionBuilder,
      $$ProfilesTableUpdateCompanionBuilder,
      (ProfileRow, BaseReferences<_$AppDatabase, $ProfilesTable, ProfileRow>),
      ProfileRow,
      PrefetchHooks Function()
    >;
typedef $$UserPreferencesTableCreateCompanionBuilder =
    UserPreferencesCompanion Function({
      required String profileId,
      required String profileElementId,
      required String status,
      Value<int?> generalValue,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      required DateTime updatedAt,
      required String source,
      Value<int> rowid,
    });
typedef $$UserPreferencesTableUpdateCompanionBuilder =
    UserPreferencesCompanion Function({
      Value<String> profileId,
      Value<String> profileElementId,
      Value<String> status,
      Value<int?> generalValue,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      Value<DateTime> updatedAt,
      Value<String> source,
      Value<int> rowid,
    });

class $$UserPreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserPreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserPreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserPreferencesTable> {
  $$UserPreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$UserPreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserPreferencesTable,
          UserPreferenceRow,
          $$UserPreferencesTableFilterComposer,
          $$UserPreferencesTableOrderingComposer,
          $$UserPreferencesTableAnnotationComposer,
          $$UserPreferencesTableCreateCompanionBuilder,
          $$UserPreferencesTableUpdateCompanionBuilder,
          (
            UserPreferenceRow,
            BaseReferences<
              _$AppDatabase,
              $UserPreferencesTable,
              UserPreferenceRow
            >,
          ),
          UserPreferenceRow,
          PrefetchHooks Function()
        > {
  $$UserPreferencesTableTableManager(
    _$AppDatabase db,
    $UserPreferencesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserPreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserPreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserPreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> profileElementId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> generalValue = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UserPreferencesCompanion(
                profileId: profileId,
                profileElementId: profileElementId,
                status: status,
                generalValue: generalValue,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
                updatedAt: updatedAt,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String profileElementId,
                required String status,
                Value<int?> generalValue = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                required DateTime updatedAt,
                required String source,
                Value<int> rowid = const Value.absent(),
              }) => UserPreferencesCompanion.insert(
                profileId: profileId,
                profileElementId: profileElementId,
                status: status,
                generalValue: generalValue,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
                updatedAt: updatedAt,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UserPreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserPreferencesTable,
      UserPreferenceRow,
      $$UserPreferencesTableFilterComposer,
      $$UserPreferencesTableOrderingComposer,
      $$UserPreferencesTableAnnotationComposer,
      $$UserPreferencesTableCreateCompanionBuilder,
      $$UserPreferencesTableUpdateCompanionBuilder,
      (
        UserPreferenceRow,
        BaseReferences<_$AppDatabase, $UserPreferencesTable, UserPreferenceRow>,
      ),
      UserPreferenceRow,
      PrefetchHooks Function()
    >;
typedef $$CardPreferenceOverridesTableCreateCompanionBuilder =
    CardPreferenceOverridesCompanion Function({
      required String profileId,
      required String cardOrVariantId,
      Value<String?> status,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CardPreferenceOverridesTableUpdateCompanionBuilder =
    CardPreferenceOverridesCompanion Function({
      Value<String> profileId,
      Value<String> cardOrVariantId,
      Value<String?> status,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CardPreferenceOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $CardPreferenceOverridesTable> {
  $$CardPreferenceOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardOrVariantId => $composableBuilder(
    column: $table.cardOrVariantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CardPreferenceOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $CardPreferenceOverridesTable> {
  $$CardPreferenceOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardOrVariantId => $composableBuilder(
    column: $table.cardOrVariantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CardPreferenceOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardPreferenceOverridesTable> {
  $$CardPreferenceOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get cardOrVariantId => $composableBuilder(
    column: $table.cardOrVariantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CardPreferenceOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardPreferenceOverridesTable,
          CardPreferenceOverrideRow,
          $$CardPreferenceOverridesTableFilterComposer,
          $$CardPreferenceOverridesTableOrderingComposer,
          $$CardPreferenceOverridesTableAnnotationComposer,
          $$CardPreferenceOverridesTableCreateCompanionBuilder,
          $$CardPreferenceOverridesTableUpdateCompanionBuilder,
          (
            CardPreferenceOverrideRow,
            BaseReferences<
              _$AppDatabase,
              $CardPreferenceOverridesTable,
              CardPreferenceOverrideRow
            >,
          ),
          CardPreferenceOverrideRow,
          PrefetchHooks Function()
        > {
  $$CardPreferenceOverridesTableTableManager(
    _$AppDatabase db,
    $CardPreferenceOverridesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardPreferenceOverridesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CardPreferenceOverridesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CardPreferenceOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> cardOrVariantId = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardPreferenceOverridesCompanion(
                profileId: profileId,
                cardOrVariantId: cardOrVariantId,
                status: status,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String cardOrVariantId,
                Value<String?> status = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CardPreferenceOverridesCompanion.insert(
                profileId: profileId,
                cardOrVariantId: cardOrVariantId,
                status: status,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
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

typedef $$CardPreferenceOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardPreferenceOverridesTable,
      CardPreferenceOverrideRow,
      $$CardPreferenceOverridesTableFilterComposer,
      $$CardPreferenceOverridesTableOrderingComposer,
      $$CardPreferenceOverridesTableAnnotationComposer,
      $$CardPreferenceOverridesTableCreateCompanionBuilder,
      $$CardPreferenceOverridesTableUpdateCompanionBuilder,
      (
        CardPreferenceOverrideRow,
        BaseReferences<
          _$AppDatabase,
          $CardPreferenceOverridesTable,
          CardPreferenceOverrideRow
        >,
      ),
      CardPreferenceOverrideRow,
      PrefetchHooks Function()
    >;
typedef $$ProfileEvolutionEntriesTableCreateCompanionBuilder =
    ProfileEvolutionEntriesCompanion Function({
      Value<int> id,
      required String profileId,
      required String profileElementId,
      Value<int?> generalValue,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      required String evidenceJson,
      required DateTime createdAt,
    });
typedef $$ProfileEvolutionEntriesTableUpdateCompanionBuilder =
    ProfileEvolutionEntriesCompanion Function({
      Value<int> id,
      Value<String> profileId,
      Value<String> profileElementId,
      Value<int?> generalValue,
      Value<int?> faireValue,
      Value<int?> recevoirValue,
      Value<String> evidenceJson,
      Value<DateTime> createdAt,
    });

class $$ProfileEvolutionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfileEvolutionEntriesTable> {
  $$ProfileEvolutionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfileEvolutionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfileEvolutionEntriesTable> {
  $$ProfileEvolutionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfileEvolutionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfileEvolutionEntriesTable> {
  $$ProfileEvolutionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get profileElementId => $composableBuilder(
    column: $table.profileElementId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get generalValue => $composableBuilder(
    column: $table.generalValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get faireValue => $composableBuilder(
    column: $table.faireValue,
    builder: (column) => column,
  );

  GeneratedColumn<int> get recevoirValue => $composableBuilder(
    column: $table.recevoirValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get evidenceJson => $composableBuilder(
    column: $table.evidenceJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$ProfileEvolutionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfileEvolutionEntriesTable,
          ProfileEvolutionRow,
          $$ProfileEvolutionEntriesTableFilterComposer,
          $$ProfileEvolutionEntriesTableOrderingComposer,
          $$ProfileEvolutionEntriesTableAnnotationComposer,
          $$ProfileEvolutionEntriesTableCreateCompanionBuilder,
          $$ProfileEvolutionEntriesTableUpdateCompanionBuilder,
          (
            ProfileEvolutionRow,
            BaseReferences<
              _$AppDatabase,
              $ProfileEvolutionEntriesTable,
              ProfileEvolutionRow
            >,
          ),
          ProfileEvolutionRow,
          PrefetchHooks Function()
        > {
  $$ProfileEvolutionEntriesTableTableManager(
    _$AppDatabase db,
    $ProfileEvolutionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileEvolutionEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProfileEvolutionEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProfileEvolutionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> profileId = const Value.absent(),
                Value<String> profileElementId = const Value.absent(),
                Value<int?> generalValue = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                Value<String> evidenceJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => ProfileEvolutionEntriesCompanion(
                id: id,
                profileId: profileId,
                profileElementId: profileElementId,
                generalValue: generalValue,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
                evidenceJson: evidenceJson,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String profileId,
                required String profileElementId,
                Value<int?> generalValue = const Value.absent(),
                Value<int?> faireValue = const Value.absent(),
                Value<int?> recevoirValue = const Value.absent(),
                required String evidenceJson,
                required DateTime createdAt,
              }) => ProfileEvolutionEntriesCompanion.insert(
                id: id,
                profileId: profileId,
                profileElementId: profileElementId,
                generalValue: generalValue,
                faireValue: faireValue,
                recevoirValue: recevoirValue,
                evidenceJson: evidenceJson,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfileEvolutionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfileEvolutionEntriesTable,
      ProfileEvolutionRow,
      $$ProfileEvolutionEntriesTableFilterComposer,
      $$ProfileEvolutionEntriesTableOrderingComposer,
      $$ProfileEvolutionEntriesTableAnnotationComposer,
      $$ProfileEvolutionEntriesTableCreateCompanionBuilder,
      $$ProfileEvolutionEntriesTableUpdateCompanionBuilder,
      (
        ProfileEvolutionRow,
        BaseReferences<
          _$AppDatabase,
          $ProfileEvolutionEntriesTable,
          ProfileEvolutionRow
        >,
      ),
      ProfileEvolutionRow,
      PrefetchHooks Function()
    >;
typedef $$ProfileLearningStatesTableCreateCompanionBuilder =
    ProfileLearningStatesCompanion Function({
      required String profileId,
      required String stateJson,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$ProfileLearningStatesTableUpdateCompanionBuilder =
    ProfileLearningStatesCompanion Function({
      Value<String> profileId,
      Value<String> stateJson,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$ProfileLearningStatesTableFilterComposer
    extends Composer<_$AppDatabase, $ProfileLearningStatesTable> {
  $$ProfileLearningStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stateJson => $composableBuilder(
    column: $table.stateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfileLearningStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProfileLearningStatesTable> {
  $$ProfileLearningStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stateJson => $composableBuilder(
    column: $table.stateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfileLearningStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProfileLearningStatesTable> {
  $$ProfileLearningStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<String> get stateJson =>
      $composableBuilder(column: $table.stateJson, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$ProfileLearningStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProfileLearningStatesTable,
          ProfileLearningStateRow,
          $$ProfileLearningStatesTableFilterComposer,
          $$ProfileLearningStatesTableOrderingComposer,
          $$ProfileLearningStatesTableAnnotationComposer,
          $$ProfileLearningStatesTableCreateCompanionBuilder,
          $$ProfileLearningStatesTableUpdateCompanionBuilder,
          (
            ProfileLearningStateRow,
            BaseReferences<
              _$AppDatabase,
              $ProfileLearningStatesTable,
              ProfileLearningStateRow
            >,
          ),
          ProfileLearningStateRow,
          PrefetchHooks Function()
        > {
  $$ProfileLearningStatesTableTableManager(
    _$AppDatabase db,
    $ProfileLearningStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileLearningStatesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProfileLearningStatesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProfileLearningStatesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> profileId = const Value.absent(),
                Value<String> stateJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProfileLearningStatesCompanion(
                profileId: profileId,
                stateJson: stateJson,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String profileId,
                required String stateJson,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => ProfileLearningStatesCompanion.insert(
                profileId: profileId,
                stateJson: stateJson,
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

typedef $$ProfileLearningStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProfileLearningStatesTable,
      ProfileLearningStateRow,
      $$ProfileLearningStatesTableFilterComposer,
      $$ProfileLearningStatesTableOrderingComposer,
      $$ProfileLearningStatesTableAnnotationComposer,
      $$ProfileLearningStatesTableCreateCompanionBuilder,
      $$ProfileLearningStatesTableUpdateCompanionBuilder,
      (
        ProfileLearningStateRow,
        BaseReferences<
          _$AppDatabase,
          $ProfileLearningStatesTable,
          ProfileLearningStateRow
        >,
      ),
      ProfileLearningStateRow,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String mode,
      required String status,
      Value<String?> interruptedRoundId,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> mode,
      Value<String> status,
      Value<String?> interruptedRoundId,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get interruptedRoundId => $composableBuilder(
    column: $table.interruptedRoundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get interruptedRoundId => $composableBuilder(
    column: $table.interruptedRoundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get interruptedRoundId => $composableBuilder(
    column: $table.interruptedRoundId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          SessionRow,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (
            SessionRow,
            BaseReferences<_$AppDatabase, $SessionsTable, SessionRow>,
          ),
          SessionRow,
          PrefetchHooks Function()
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> interruptedRoundId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                mode: mode,
                status: status,
                interruptedRoundId: interruptedRoundId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String mode,
                required String status,
                Value<String?> interruptedRoundId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                mode: mode,
                status: status,
                interruptedRoundId: interruptedRoundId,
                createdAt: createdAt,
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

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      SessionRow,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (SessionRow, BaseReferences<_$AppDatabase, $SessionsTable, SessionRow>),
      SessionRow,
      PrefetchHooks Function()
    >;
typedef $$SessionPlayersTableCreateCompanionBuilder =
    SessionPlayersCompanion Function({
      required String sessionId,
      required String playerId,
      Value<String?> profileId,
      required int actionPoints,
      required int chiliLevel,
      Value<String?> style,
      Value<int> rowid,
    });
typedef $$SessionPlayersTableUpdateCompanionBuilder =
    SessionPlayersCompanion Function({
      Value<String> sessionId,
      Value<String> playerId,
      Value<String?> profileId,
      Value<int> actionPoints,
      Value<int> chiliLevel,
      Value<String?> style,
      Value<int> rowid,
    });

class $$SessionPlayersTableFilterComposer
    extends Composer<_$AppDatabase, $SessionPlayersTable> {
  $$SessionPlayersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get actionPoints => $composableBuilder(
    column: $table.actionPoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chiliLevel => $composableBuilder(
    column: $table.chiliLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionPlayersTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionPlayersTable> {
  $$SessionPlayersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get profileId => $composableBuilder(
    column: $table.profileId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get actionPoints => $composableBuilder(
    column: $table.actionPoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chiliLevel => $composableBuilder(
    column: $table.chiliLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get style => $composableBuilder(
    column: $table.style,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionPlayersTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionPlayersTable> {
  $$SessionPlayersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get profileId =>
      $composableBuilder(column: $table.profileId, builder: (column) => column);

  GeneratedColumn<int> get actionPoints => $composableBuilder(
    column: $table.actionPoints,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chiliLevel => $composableBuilder(
    column: $table.chiliLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get style =>
      $composableBuilder(column: $table.style, builder: (column) => column);
}

class $$SessionPlayersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionPlayersTable,
          SessionPlayerRow,
          $$SessionPlayersTableFilterComposer,
          $$SessionPlayersTableOrderingComposer,
          $$SessionPlayersTableAnnotationComposer,
          $$SessionPlayersTableCreateCompanionBuilder,
          $$SessionPlayersTableUpdateCompanionBuilder,
          (
            SessionPlayerRow,
            BaseReferences<
              _$AppDatabase,
              $SessionPlayersTable,
              SessionPlayerRow
            >,
          ),
          SessionPlayerRow,
          PrefetchHooks Function()
        > {
  $$SessionPlayersTableTableManager(
    _$AppDatabase db,
    $SessionPlayersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionPlayersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionPlayersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionPlayersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> playerId = const Value.absent(),
                Value<String?> profileId = const Value.absent(),
                Value<int> actionPoints = const Value.absent(),
                Value<int> chiliLevel = const Value.absent(),
                Value<String?> style = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionPlayersCompanion(
                sessionId: sessionId,
                playerId: playerId,
                profileId: profileId,
                actionPoints: actionPoints,
                chiliLevel: chiliLevel,
                style: style,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String playerId,
                Value<String?> profileId = const Value.absent(),
                required int actionPoints,
                required int chiliLevel,
                Value<String?> style = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionPlayersCompanion.insert(
                sessionId: sessionId,
                playerId: playerId,
                profileId: profileId,
                actionPoints: actionPoints,
                chiliLevel: chiliLevel,
                style: style,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionPlayersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionPlayersTable,
      SessionPlayerRow,
      $$SessionPlayersTableFilterComposer,
      $$SessionPlayersTableOrderingComposer,
      $$SessionPlayersTableAnnotationComposer,
      $$SessionPlayersTableCreateCompanionBuilder,
      $$SessionPlayersTableUpdateCompanionBuilder,
      (
        SessionPlayerRow,
        BaseReferences<_$AppDatabase, $SessionPlayersTable, SessionPlayerRow>,
      ),
      SessionPlayerRow,
      PrefetchHooks Function()
    >;
typedef $$SessionCardsTableCreateCompanionBuilder =
    SessionCardsCompanion Function({
      required String sessionId,
      required String playerId,
      required String cardId,
      Value<String?> variantId,
      required String zone,
      required int ordinal,
      Value<bool> locked,
      Value<int> rowid,
    });
typedef $$SessionCardsTableUpdateCompanionBuilder =
    SessionCardsCompanion Function({
      Value<String> sessionId,
      Value<String> playerId,
      Value<String> cardId,
      Value<String?> variantId,
      Value<String> zone,
      Value<int> ordinal,
      Value<bool> locked,
      Value<int> rowid,
    });

class $$SessionCardsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionCardsTable> {
  $$SessionCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get locked => $composableBuilder(
    column: $table.locked,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionCardsTable> {
  $$SessionCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zone => $composableBuilder(
    column: $table.zone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get locked => $composableBuilder(
    column: $table.locked,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionCardsTable> {
  $$SessionCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<String> get zone =>
      $composableBuilder(column: $table.zone, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<bool> get locked =>
      $composableBuilder(column: $table.locked, builder: (column) => column);
}

class $$SessionCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionCardsTable,
          SessionCardRow,
          $$SessionCardsTableFilterComposer,
          $$SessionCardsTableOrderingComposer,
          $$SessionCardsTableAnnotationComposer,
          $$SessionCardsTableCreateCompanionBuilder,
          $$SessionCardsTableUpdateCompanionBuilder,
          (
            SessionCardRow,
            BaseReferences<_$AppDatabase, $SessionCardsTable, SessionCardRow>,
          ),
          SessionCardRow,
          PrefetchHooks Function()
        > {
  $$SessionCardsTableTableManager(_$AppDatabase db, $SessionCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> playerId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<String?> variantId = const Value.absent(),
                Value<String> zone = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<bool> locked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionCardsCompanion(
                sessionId: sessionId,
                playerId: playerId,
                cardId: cardId,
                variantId: variantId,
                zone: zone,
                ordinal: ordinal,
                locked: locked,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String playerId,
                required String cardId,
                Value<String?> variantId = const Value.absent(),
                required String zone,
                required int ordinal,
                Value<bool> locked = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionCardsCompanion.insert(
                sessionId: sessionId,
                playerId: playerId,
                cardId: cardId,
                variantId: variantId,
                zone: zone,
                ordinal: ordinal,
                locked: locked,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionCardsTable,
      SessionCardRow,
      $$SessionCardsTableFilterComposer,
      $$SessionCardsTableOrderingComposer,
      $$SessionCardsTableAnnotationComposer,
      $$SessionCardsTableCreateCompanionBuilder,
      $$SessionCardsTableUpdateCompanionBuilder,
      (
        SessionCardRow,
        BaseReferences<_$AppDatabase, $SessionCardsTable, SessionCardRow>,
      ),
      SessionCardRow,
      PrefetchHooks Function()
    >;
typedef $$RoundsTableCreateCompanionBuilder =
    RoundsCompanion Function({
      required String sessionId,
      required String roundId,
      required int ordinal,
      required String status,
      required String stateJson,
      required DateTime startedAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RoundsTableUpdateCompanionBuilder =
    RoundsCompanion Function({
      Value<String> sessionId,
      Value<String> roundId,
      Value<int> ordinal,
      Value<String> status,
      Value<String> stateJson,
      Value<DateTime> startedAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RoundsTableFilterComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roundId => $composableBuilder(
    column: $table.roundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get stateJson => $composableBuilder(
    column: $table.stateJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoundsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roundId => $composableBuilder(
    column: $table.roundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get stateJson => $composableBuilder(
    column: $table.stateJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoundsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get roundId =>
      $composableBuilder(column: $table.roundId, builder: (column) => column);

  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get stateJson =>
      $composableBuilder(column: $table.stateJson, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RoundsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoundsTable,
          RoundRow,
          $$RoundsTableFilterComposer,
          $$RoundsTableOrderingComposer,
          $$RoundsTableAnnotationComposer,
          $$RoundsTableCreateCompanionBuilder,
          $$RoundsTableUpdateCompanionBuilder,
          (RoundRow, BaseReferences<_$AppDatabase, $RoundsTable, RoundRow>),
          RoundRow,
          PrefetchHooks Function()
        > {
  $$RoundsTableTableManager(_$AppDatabase db, $RoundsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoundsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> roundId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> stateJson = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoundsCompanion(
                sessionId: sessionId,
                roundId: roundId,
                ordinal: ordinal,
                status: status,
                stateJson: stateJson,
                startedAt: startedAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String roundId,
                required int ordinal,
                required String status,
                required String stateJson,
                required DateTime startedAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RoundsCompanion.insert(
                sessionId: sessionId,
                roundId: roundId,
                ordinal: ordinal,
                status: status,
                stateJson: stateJson,
                startedAt: startedAt,
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

typedef $$RoundsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoundsTable,
      RoundRow,
      $$RoundsTableFilterComposer,
      $$RoundsTableOrderingComposer,
      $$RoundsTableAnnotationComposer,
      $$RoundsTableCreateCompanionBuilder,
      $$RoundsTableUpdateCompanionBuilder,
      (RoundRow, BaseReferences<_$AppDatabase, $RoundsTable, RoundRow>),
      RoundRow,
      PrefetchHooks Function()
    >;
typedef $$CombatValueSnapshotsTableCreateCompanionBuilder =
    CombatValueSnapshotsCompanion Function({
      required String sessionId,
      required String roundId,
      required String playerId,
      required String cardId,
      required String variantId,
      required String roleAtCommit,
      required int personalValue,
      required DateTime committedAt,
      Value<int> rowid,
    });
typedef $$CombatValueSnapshotsTableUpdateCompanionBuilder =
    CombatValueSnapshotsCompanion Function({
      Value<String> sessionId,
      Value<String> roundId,
      Value<String> playerId,
      Value<String> cardId,
      Value<String> variantId,
      Value<String> roleAtCommit,
      Value<int> personalValue,
      Value<DateTime> committedAt,
      Value<int> rowid,
    });

class $$CombatValueSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $CombatValueSnapshotsTable> {
  $$CombatValueSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roundId => $composableBuilder(
    column: $table.roundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roleAtCommit => $composableBuilder(
    column: $table.roleAtCommit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get personalValue => $composableBuilder(
    column: $table.personalValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CombatValueSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $CombatValueSnapshotsTable> {
  $$CombatValueSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roundId => $composableBuilder(
    column: $table.roundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get playerId => $composableBuilder(
    column: $table.playerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get variantId => $composableBuilder(
    column: $table.variantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roleAtCommit => $composableBuilder(
    column: $table.roleAtCommit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get personalValue => $composableBuilder(
    column: $table.personalValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CombatValueSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CombatValueSnapshotsTable> {
  $$CombatValueSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get roundId =>
      $composableBuilder(column: $table.roundId, builder: (column) => column);

  GeneratedColumn<String> get playerId =>
      $composableBuilder(column: $table.playerId, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get variantId =>
      $composableBuilder(column: $table.variantId, builder: (column) => column);

  GeneratedColumn<String> get roleAtCommit => $composableBuilder(
    column: $table.roleAtCommit,
    builder: (column) => column,
  );

  GeneratedColumn<int> get personalValue => $composableBuilder(
    column: $table.personalValue,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get committedAt => $composableBuilder(
    column: $table.committedAt,
    builder: (column) => column,
  );
}

class $$CombatValueSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CombatValueSnapshotsTable,
          CombatValueSnapshotRow,
          $$CombatValueSnapshotsTableFilterComposer,
          $$CombatValueSnapshotsTableOrderingComposer,
          $$CombatValueSnapshotsTableAnnotationComposer,
          $$CombatValueSnapshotsTableCreateCompanionBuilder,
          $$CombatValueSnapshotsTableUpdateCompanionBuilder,
          (
            CombatValueSnapshotRow,
            BaseReferences<
              _$AppDatabase,
              $CombatValueSnapshotsTable,
              CombatValueSnapshotRow
            >,
          ),
          CombatValueSnapshotRow,
          PrefetchHooks Function()
        > {
  $$CombatValueSnapshotsTableTableManager(
    _$AppDatabase db,
    $CombatValueSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CombatValueSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CombatValueSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CombatValueSnapshotsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> roundId = const Value.absent(),
                Value<String> playerId = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<String> variantId = const Value.absent(),
                Value<String> roleAtCommit = const Value.absent(),
                Value<int> personalValue = const Value.absent(),
                Value<DateTime> committedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CombatValueSnapshotsCompanion(
                sessionId: sessionId,
                roundId: roundId,
                playerId: playerId,
                cardId: cardId,
                variantId: variantId,
                roleAtCommit: roleAtCommit,
                personalValue: personalValue,
                committedAt: committedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String roundId,
                required String playerId,
                required String cardId,
                required String variantId,
                required String roleAtCommit,
                required int personalValue,
                required DateTime committedAt,
                Value<int> rowid = const Value.absent(),
              }) => CombatValueSnapshotsCompanion.insert(
                sessionId: sessionId,
                roundId: roundId,
                playerId: playerId,
                cardId: cardId,
                variantId: variantId,
                roleAtCommit: roleAtCommit,
                personalValue: personalValue,
                committedAt: committedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CombatValueSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CombatValueSnapshotsTable,
      CombatValueSnapshotRow,
      $$CombatValueSnapshotsTableFilterComposer,
      $$CombatValueSnapshotsTableOrderingComposer,
      $$CombatValueSnapshotsTableAnnotationComposer,
      $$CombatValueSnapshotsTableCreateCompanionBuilder,
      $$CombatValueSnapshotsTableUpdateCompanionBuilder,
      (
        CombatValueSnapshotRow,
        BaseReferences<
          _$AppDatabase,
          $CombatValueSnapshotsTable,
          CombatValueSnapshotRow
        >,
      ),
      CombatValueSnapshotRow,
      PrefetchHooks Function()
    >;
typedef $$EventLogsTableCreateCompanionBuilder =
    EventLogsCompanion Function({
      required String sessionId,
      required String eventId,
      required int sequence,
      required String type,
      required String payloadJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$EventLogsTableUpdateCompanionBuilder =
    EventLogsCompanion Function({
      Value<String> sessionId,
      Value<String> eventId,
      Value<int> sequence,
      Value<String> type,
      Value<String> payloadJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$EventLogsTableFilterComposer
    extends Composer<_$AppDatabase, $EventLogsTable> {
  $$EventLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventLogsTable> {
  $$EventLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventLogsTable> {
  $$EventLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$EventLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventLogsTable,
          EventLogRow,
          $$EventLogsTableFilterComposer,
          $$EventLogsTableOrderingComposer,
          $$EventLogsTableAnnotationComposer,
          $$EventLogsTableCreateCompanionBuilder,
          $$EventLogsTableUpdateCompanionBuilder,
          (
            EventLogRow,
            BaseReferences<_$AppDatabase, $EventLogsTable, EventLogRow>,
          ),
          EventLogRow,
          PrefetchHooks Function()
        > {
  $$EventLogsTableTableManager(_$AppDatabase db, $EventLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> eventId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventLogsCompanion(
                sessionId: sessionId,
                eventId: eventId,
                sequence: sequence,
                type: type,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String eventId,
                required int sequence,
                required String type,
                required String payloadJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => EventLogsCompanion.insert(
                sessionId: sessionId,
                eventId: eventId,
                sequence: sequence,
                type: type,
                payloadJson: payloadJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventLogsTable,
      EventLogRow,
      $$EventLogsTableFilterComposer,
      $$EventLogsTableOrderingComposer,
      $$EventLogsTableAnnotationComposer,
      $$EventLogsTableCreateCompanionBuilder,
      $$EventLogsTableUpdateCompanionBuilder,
      (
        EventLogRow,
        BaseReferences<_$AppDatabase, $EventLogsTable, EventLogRow>,
      ),
      EventLogRow,
      PrefetchHooks Function()
    >;
typedef $$CatalogDocumentsTableCreateCompanionBuilder =
    CatalogDocumentsCompanion Function({
      required String documentId,
      required int schemaVersion,
      required String catalogVersion,
      required String json,
      required DateTime installedAt,
      Value<int> rowid,
    });
typedef $$CatalogDocumentsTableUpdateCompanionBuilder =
    CatalogDocumentsCompanion Function({
      Value<String> documentId,
      Value<int> schemaVersion,
      Value<String> catalogVersion,
      Value<String> json,
      Value<DateTime> installedAt,
      Value<int> rowid,
    });

class $$CatalogDocumentsTableFilterComposer
    extends Composer<_$AppDatabase, $CatalogDocumentsTable> {
  $$CatalogDocumentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CatalogDocumentsTableOrderingComposer
    extends Composer<_$AppDatabase, $CatalogDocumentsTable> {
  $$CatalogDocumentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get json => $composableBuilder(
    column: $table.json,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CatalogDocumentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatalogDocumentsTable> {
  $$CatalogDocumentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get documentId => $composableBuilder(
    column: $table.documentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get schemaVersion => $composableBuilder(
    column: $table.schemaVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get catalogVersion => $composableBuilder(
    column: $table.catalogVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAt => $composableBuilder(
    column: $table.installedAt,
    builder: (column) => column,
  );
}

class $$CatalogDocumentsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CatalogDocumentsTable,
          CatalogDocumentRow,
          $$CatalogDocumentsTableFilterComposer,
          $$CatalogDocumentsTableOrderingComposer,
          $$CatalogDocumentsTableAnnotationComposer,
          $$CatalogDocumentsTableCreateCompanionBuilder,
          $$CatalogDocumentsTableUpdateCompanionBuilder,
          (
            CatalogDocumentRow,
            BaseReferences<
              _$AppDatabase,
              $CatalogDocumentsTable,
              CatalogDocumentRow
            >,
          ),
          CatalogDocumentRow,
          PrefetchHooks Function()
        > {
  $$CatalogDocumentsTableTableManager(
    _$AppDatabase db,
    $CatalogDocumentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatalogDocumentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatalogDocumentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatalogDocumentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> documentId = const Value.absent(),
                Value<int> schemaVersion = const Value.absent(),
                Value<String> catalogVersion = const Value.absent(),
                Value<String> json = const Value.absent(),
                Value<DateTime> installedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CatalogDocumentsCompanion(
                documentId: documentId,
                schemaVersion: schemaVersion,
                catalogVersion: catalogVersion,
                json: json,
                installedAt: installedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String documentId,
                required int schemaVersion,
                required String catalogVersion,
                required String json,
                required DateTime installedAt,
                Value<int> rowid = const Value.absent(),
              }) => CatalogDocumentsCompanion.insert(
                documentId: documentId,
                schemaVersion: schemaVersion,
                catalogVersion: catalogVersion,
                json: json,
                installedAt: installedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CatalogDocumentsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CatalogDocumentsTable,
      CatalogDocumentRow,
      $$CatalogDocumentsTableFilterComposer,
      $$CatalogDocumentsTableOrderingComposer,
      $$CatalogDocumentsTableAnnotationComposer,
      $$CatalogDocumentsTableCreateCompanionBuilder,
      $$CatalogDocumentsTableUpdateCompanionBuilder,
      (
        CatalogDocumentRow,
        BaseReferences<
          _$AppDatabase,
          $CatalogDocumentsTable,
          CatalogDocumentRow
        >,
      ),
      CatalogDocumentRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db, _db.profiles);
  $$UserPreferencesTableTableManager get userPreferences =>
      $$UserPreferencesTableTableManager(_db, _db.userPreferences);
  $$CardPreferenceOverridesTableTableManager get cardPreferenceOverrides =>
      $$CardPreferenceOverridesTableTableManager(
        _db,
        _db.cardPreferenceOverrides,
      );
  $$ProfileEvolutionEntriesTableTableManager get profileEvolutionEntries =>
      $$ProfileEvolutionEntriesTableTableManager(
        _db,
        _db.profileEvolutionEntries,
      );
  $$ProfileLearningStatesTableTableManager get profileLearningStates =>
      $$ProfileLearningStatesTableTableManager(_db, _db.profileLearningStates);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$SessionPlayersTableTableManager get sessionPlayers =>
      $$SessionPlayersTableTableManager(_db, _db.sessionPlayers);
  $$SessionCardsTableTableManager get sessionCards =>
      $$SessionCardsTableTableManager(_db, _db.sessionCards);
  $$RoundsTableTableManager get rounds =>
      $$RoundsTableTableManager(_db, _db.rounds);
  $$CombatValueSnapshotsTableTableManager get combatValueSnapshots =>
      $$CombatValueSnapshotsTableTableManager(_db, _db.combatValueSnapshots);
  $$EventLogsTableTableManager get eventLogs =>
      $$EventLogsTableTableManager(_db, _db.eventLogs);
  $$CatalogDocumentsTableTableManager get catalogDocuments =>
      $$CatalogDocumentsTableTableManager(_db, _db.catalogDocuments);
}
