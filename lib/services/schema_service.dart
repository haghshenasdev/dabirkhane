import 'dart:convert';
import 'dart:math';

import 'package:dabirkhane/db/database_helper.dart';
import 'package:dabirkhane/model/field_definition.dart';
import 'package:sqflite/sqflite.dart';

class SchemaService {
  static const String tableName = 'record_schema';
  static const String recordTable = 'daftare_andicator';

  static Future<RecordSchema?> load() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(tableName, where: 'id = 1', limit: 1);
    if (rows.isEmpty) return null;

    final schema = RecordSchema.fromDatabaseRow(
      Map<String, dynamic>.from(rows.first),
    );
    final normalized = _normalizeExistingSchema(schema);

    if (normalized.schemaVersion != schema.schemaVersion ||
        normalized.fieldsJsonString != schema.fieldsJsonString ||
        normalized.layoutJsonString != schema.layoutJsonString ||
        normalized.searchJsonString != schema.searchJsonString) {
      await _saveWithExecutor(db, normalized);
      return normalized;
    }

    return schema;
  }

  static RecordSchema _normalizeExistingSchema(RecordSchema schema) {
    var fields = [...schema.fields];
    var sections = [...schema.sections];
    var filterFields = [...schema.filterFields];
    var changed = false;

    // دسته‌بندی همیشه یک فیلد سیستمی مجازی است؛ قابل حذف نیست و جای آن
    // در همان layout داینامیک فرم تعیین می‌شود.
    if (schema.field('__category__') == null) {
      fields.add(const FieldDefinition(
        key: '__category__',
        label: 'دسته‌بندی',
        type: FieldType.category,
        visible: true,
        searchable: false,
        filterable: false,
        system: true,
        deletable: false,
        section: 'اطلاعات اصلی',
        order: 999,
        icon: 'label',
      ));
      changed = true;
    }

    fields = fields.map((f) {
      var next = f;
      if ((f.key == 'comment' || f.key == 'shomare_badi') && !f.filterable) {
        next = next.copyWith(filterable: true);
        changed = true;
      }
      if (f.icon == null || f.icon!.isEmpty) {
        next = next.copyWith(icon: _defaultIconCode(f.key, f.type));
        changed = true;
      }
      return next;
    }).toList();

    final category = fields.firstWhere((f) => f.key == '__category__');
    if (sections.isEmpty) {
      sections = [
        FormSectionDefinition(
          id: 'main',
          title: 'اطلاعات اصلی',
          order: 0,
          columns: 1,
          fields: [category.key],
        ),
      ];
      changed = true;
    } else if (!sections.any((s) => s.fields.contains(category.key))) {
      final index = sections.indexWhere((s) => s.title == category.section);
      final target = index >= 0 ? index : 0;
      sections[target] = sections[target].copyWith(
        fields: [...sections[target].fields, category.key],
      );
      changed = true;
    }

    final allowedFilters = fields
        .where((f) => f.visible && f.filterable && !f.system)
        .map((f) => f.key)
        .toSet();

    final normalizedFilters = <String>[];
    for (final key in filterFields) {
      if (allowedFilters.contains(key) && !normalizedFilters.contains(key)) {
        normalizedFilters.add(key);
      }
    }
    for (final key in ['comment', 'shomare_badi']) {
      if (allowedFilters.contains(key) && !normalizedFilters.contains(key)) {
        normalizedFilters.add(key);
        changed = true;
      }
    }
    for (final f in fields) {
      if (allowedFilters.contains(f.key) && !normalizedFilters.contains(f.key)) {
        normalizedFilters.add(f.key);
        changed = true;
      }
    }

    if (normalizedFilters.length != filterFields.length ||
        !normalizedFilters.every((e) => filterFields.contains(e))) {
      changed = true;
    }

    if (!changed) return schema;

    return RecordSchema(
      schemaVersion: schema.schemaVersion + 1,
      fields: fields,
      sections: sections,
      defaultSearchFields: schema.defaultSearchFields,
      dateField: schema.dateField,
      statsGroupFields: schema.statsGroupFields,
      statsEnabled: schema.statsEnabled,
      filterFields: normalizedFilters,
      filterColumns: schema.filterColumns,
      card: schema.card,
    );
  }

  static Future<bool> hasSchema() async {
    final db = await DatabaseHelper.database;
    final rows = await db.query(tableName, columns: ['id'], where: 'id = 1', limit: 1);
    return rows.isNotEmpty;
  }

  static Future<void> save(RecordSchema schema) async {
    final db = await DatabaseHelper.database;
    await _saveWithExecutor(db, schema);
  }

  static Future<void> _saveWithExecutor(DatabaseExecutor db, RecordSchema schema) async {
    final now = DateTime.now().toIso8601String();
    await db.insert(
      tableName,
      {
        'id': 1,
        'schema_version': schema.schemaVersion,
        'fields_json': schema.fieldsJsonString,
        'layout_json': schema.layoutJsonString,
        'search_json': schema.searchJsonString,
        'stats_json': schema.statsJsonString,
        'card_json': schema.cardJsonString,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> initializeForNewInstall() async {
    final existing = await load();
    if (existing != null) return;

    final starter = RecordSchema(
      fields: const [
        FieldDefinition(
          key: 'Shomare_Radif',
          label: 'شماره نامه',
          type: FieldType.number,
          required: true,
          visible: true,
          searchable: true,
          sortable: true,
          system: true,
          deletable: false,
          section: 'اطلاعات اصلی',
          order: 0,
        ),
        FieldDefinition(key: 'date', label: 'تاریخ', type: FieldType.date, required: true, visible: true, searchable: true, sortable: true, system: true, deletable: false, section: 'اطلاعات اصلی', order: 1),
        FieldDefinition(
          key: '__category__',
          label: 'دسته‌بندی',
          type: FieldType.category,
          visible: true,
          system: true,
          deletable: false,
          section: 'اطلاعات اصلی',
          order: 2,
          icon: 'label',
        ),
      ],
      sections: const [
        FormSectionDefinition(
          id: 'main',
          title: 'اطلاعات اصلی',
          order: 0,
          columns: 1,
          fields: ['Shomare_Radif', 'date', '__category__'],
        ),
      ],
      defaultSearchFields: ['Shomare_Radif'],
      dateField: null,
      statsGroupFields: const [],
      filterFields: const [],
      filterColumns: 2,
    );

    await save(starter);
  }

  static Future<RecordSchema> createLegacyCompatibleSchema() async {
    final now = DateTime.now().toIso8601String();
    final schema = RecordSchema(
      schemaVersion: 1,
      fields: [
        _f('Shomare_Radif', 'شماره نامه', FieldType.number, system: true, deletable: false, required: true, searchable: true, sortable: true, order: 0, section: 'اطلاعات اصلی'),
        _f('date', 'تاریخ', FieldType.date, system: true, deletable: false, required: true, searchable: true, sortable: true, order: 1, section: 'اطلاعات اصلی'),
        _f('saheb_name', 'صاحب نامه', FieldType.text, searchable: true, sortable: true, suggestions: true, order: 2, section: 'اطلاعات اصلی'),
        _f('guy', 'موضوع', FieldType.text, searchable: true, suggestions: true, order: 3, section: 'اطلاعات اصلی'),
        _f('sh_name_reside', 'شماره تماس', FieldType.phone, searchable: true, order: 4, section: 'اطلاعات اصلی'),
        _f('onvan', 'گیرنده نامه', FieldType.text, searchable: true, suggestions: true, order: 5, section: 'اطلاعات اصلی'),
        _f('comment', 'توضیحات', FieldType.multiline, searchable: true, filterable: true, order: 6, section: 'اطلاعات اصلی', maxLines: 4),
        _f('shomare_badi', 'شماره بعدی', FieldType.text, searchable: true, filterable: true, order: 7, section: 'اطلاعات اصلی'),
        _f('goshashte', 'شماره قبلی', FieldType.text, searchable: true, order: 8, section: 'سایر اطلاعات'),
        _f('from_pywa', 'پیوست نامه', FieldType.text, searchable: true, order: 9, section: 'سایر اطلاعات'),
        _f('t_name_reside', 'تاریخ نامه', FieldType.date, searchable: true, order: 10, section: 'سایر اطلاعات'),
        _f('wordmost2', 'پیوست مکاتبه', FieldType.text, searchable: true, order: 11, section: 'سایر اطلاعات'),
        _f('t_name_ersali', 'تاریخ مکاتبه', FieldType.date, searchable: true, order: 12, section: 'سایر اطلاعات'),
        _f('adres_name', 'آدرس', FieldType.multiline, searchable: true, order: 13, section: 'سایر اطلاعات', maxLines: 4),
        _f('__category__', 'دسته‌بندی', FieldType.category, filterable: false, system: true, deletable: false, order: 14, section: 'اطلاعات اصلی', icon: 'label'),
      ],
      sections: const [
        FormSectionDefinition(id: 'main', title: 'اطلاعات اصلی', order: 0, columns: 2, fields: ['Shomare_Radif', 'date', 'saheb_name', 'guy', 'sh_name_reside', 'onvan', 'comment', 'shomare_badi', '__category__']),
        FormSectionDefinition(id: 'other', title: 'سایر اطلاعات', order: 1, columns: 1, collapsible: true, fields: ['goshashte', 'from_pywa', 't_name_reside', 'wordmost2', 't_name_ersali', 'adres_name']),
      ],
      defaultSearchFields: const ['guy', 'saheb_name', 'Shomare_Radif', 'sh_name_reside'],
      dateField: 'date',
      statsGroupFields: const ['onvan', 'guy', 'saheb_name'],
      filterFields: const ['onvan', 'comment', 'shomare_badi', 'saheb_name', 'guy', 'sh_name_reside'],
      filterColumns: 2,
    );

    final db = await DatabaseHelper.database;
    await db.insert(
      tableName,
      {
        'id': 1,
        'schema_version': 1,
        'fields_json': schema.fieldsJsonString,
        'layout_json': schema.layoutJsonString,
        'search_json': schema.searchJsonString,
        'stats_json': schema.statsJsonString,
        'card_json': schema.cardJsonString,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return schema;
  }

  static String _defaultIconCode(String key, FieldType type) {
    const byKey = <String, String>{
      'Shomare_Radif': 'numbers',
      'date': 'event',
      'saheb_name': 'person',
      'guy': 'subject',
      'sh_name_reside': 'phone',
      'onvan': 'person_outline',
      'comment': 'notes',
      'shomare_badi': 'forward',
      'goshashte': 'history',
      'from_pywa': 'attach_file',
      't_name_reside': 'event_note',
      'wordmost2': 'description',
      't_name_ersali': 'event_note',
      'adres_name': 'location_on',
      '__category__': 'label',
    };
    final known = byKey[key];
    if (known != null) return known;
    switch (type) {
      case FieldType.date:
      case FieldType.datetime:
        return 'event';
      case FieldType.number:
        return 'numbers';
      case FieldType.boolean:
        return 'check_circle';
      case FieldType.phone:
        return 'phone';
      case FieldType.email:
        return 'email';
      case FieldType.multiline:
        return 'notes';
      case FieldType.file:
        return 'attach_file';
      case FieldType.category:
        return 'label';
      case FieldType.select:
      case FieldType.multiselect:
        return 'subject';
      case FieldType.url:
        return 'link';
      case FieldType.text:
        return 'text';
    }
  }

  static FieldDefinition _f(
    String key,
    String label,
    FieldType type, {
    bool required = false,
    bool searchable = false,
    bool sortable = false,
    bool suggestions = false,
    bool? filterable,
    bool system = false,
    bool deletable = true,
    int order = 0,
    String section = 'اطلاعات اصلی',
    int maxLines = 3,
    String? icon,
    int gridSpan = 1,
  }) => FieldDefinition(
        key: key,
        label: label,
        type: type,
        required: required,
        searchable: searchable,
        sortable: sortable,
        suggestions: suggestions,
        filterable: filterable ?? !system,
        system: system,
        deletable: deletable,
        order: order,
        section: section,
        maxLines: maxLines,
        icon: icon,
        gridSpan: gridSpan,
      );

  static Future<void> addField(FieldDefinition field) async {
    _validateKey(field.key);
    final schema = await load();
    if (schema == null) throw StateError('ساختار دبیرخانه هنوز ایجاد نشده است.');
    if (schema.field(field.key) != null) throw StateError('این کلید فیلد قبلاً استفاده شده است.');

    final db = await DatabaseHelper.database;
    final columns = await _columns(db);

    // دسته‌بندی یک فیلد سیستمی مجازی است و داده‌های آن در جدول
    // record_categories نگهداری می‌شود، بنابراین ستون SQLite ندارد.
    if (field.type != FieldType.category && !columns.contains(field.key)) {
      final sqlType = _sqlType(field.type);
      await db.execute(
        'ALTER TABLE $recordTable ADD COLUMN "${_quote(field.key)}" $sqlType',
      );
    } else if (field.type != FieldType.category) {
      throw StateError('ستون ${field.key} از قبل در دیتابیس وجود دارد.');
    }

    final fields = [...schema.fields, field];
    final sections = _ensureFieldInSections(schema.sections, field);
    final updated = _copySchema(schema, fields: fields, sections: sections);
    await save(updated);
  }

  static Future<void> updateField(FieldDefinition updatedField) async {
    _validateKey(updatedField.key);
    final schema = await load();
    if (schema == null) throw StateError('ساختار دبیرخانه هنوز ایجاد نشده است.');
    final old = schema.field(updatedField.key);
    if (old == null) throw StateError('فیلد پیدا نشد.');

    final fields = schema.fields.map((f) => f.key == updatedField.key ? updatedField : f).toList();
    var sections = schema.sections;
    if (old.section != updatedField.section) {
      sections = sections.map((s) => s.copyWith(fields: s.fields.where((k) => k != old.key).toList())).toList();
      sections = _ensureFieldInSections(sections, updatedField);
    }
    await save(_copySchema(schema, fields: fields, sections: sections));
  }

  static Future<void> setLayout(List<FormSectionDefinition> sections) async {
    final schema = await load();
    if (schema == null) return;

    final normalized = sections
        .asMap()
        .entries
        .map((e) => e.value.copyWith(order: e.key))
        .toList();

    var globalOrder = 0;
    final sectionByField = <String, String>{};
    final orderByField = <String, int>{};
    for (final section in normalized) {
      for (final key in section.fields) {
        sectionByField[key] = section.title;
        orderByField[key] = globalOrder++;
      }
    }

    final updatedFields = schema.fields.map((field) {
      final section = sectionByField[field.key];
      final order = orderByField[field.key];
      if (section == null && order == null) return field;
      return field.copyWith(
        section: section ?? field.section,
        order: order ?? field.order,
      );
    }).toList();

    await save(_copySchema(
      schema,
      fields: updatedFields,
      sections: normalized,
    ));
  }

  static Future<void> setSearchFields(List<String> fields) async {
    final schema = await load();
    if (schema == null) return;
    final allowed = fields.where((key) => schema.field(key)?.searchable == true).toList();
    await save(_copySchema(schema, defaultSearchFields: allowed));
  }

  static Future<void> setStatsConfig({required bool enabled, String? dateField, required List<String> groupFields}) async {
    final schema = await load();
    if (schema == null) return;
    final validGroups = groupFields.where((key) => schema.field(key)?.visible == true).take(6).toList();
    final validDate = dateField != null && schema.field(dateField)?.visible == true ? dateField : null;
    await save(RecordSchema(
      schemaVersion: schema.schemaVersion + 1,
      fields: schema.fields,
      sections: schema.sections,
      defaultSearchFields: schema.defaultSearchFields,
      dateField: validDate,
      statsGroupFields: validGroups,
      statsEnabled: enabled,
      filterFields: schema.filterFields,
      filterColumns: schema.filterColumns,
      card: schema.card,
    ));
  }

  static Future<void> setFilterConfig({
    required List<String> fields,
    required int columns,
  }) async {
    final schema = await load();
    if (schema == null) return;

    final allowed = schema.fields
        .where((f) => f.visible && f.filterable && !f.system)
        .map((f) => f.key)
        .toSet();

    final normalized = <String>[];
    for (final key in fields) {
      if (allowed.contains(key) && !normalized.contains(key)) {
        normalized.add(key);
      }
    }

    for (final field in schema.fields) {
      if (allowed.contains(field.key) && !normalized.contains(field.key)) {
        normalized.add(field.key);
      }
    }

    await save(_copySchema(
      schema,
      filterFields: normalized,
      filterColumns: columns.clamp(1, 2).toInt(),
    ));
  }

  static Future<void> disableField(String key) async {
    final schema = await load();
    if (schema == null) return;
    final field = schema.field(key);
    if (field == null || !field.deletable) throw StateError('این فیلد سیستمی است و قابل غیرفعال‌سازی نیست.');
    await updateField(field.copyWith(visible: false, searchable: false));
  }

  static Future<Set<String>> columns() async {
    final db = await DatabaseHelper.database;
    return _columns(db);
  }

  static Future<Set<String>> _columns(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA table_info($recordTable)');
    return rows.map((e) => e['name']?.toString() ?? '').where((e) => e.isNotEmpty).toSet();
  }

  static String _sqlType(FieldType type) {
    switch (type) {
      case FieldType.number:
      case FieldType.boolean:
        return 'INTEGER';
      default:
        return 'TEXT';
    }
  }

  static String _quote(String value) => value.replaceAll('"', '""');

  static void _validateKey(String key) {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
      throw ArgumentError('کلید فنی فیلد فقط باید شامل حروف انگلیسی، عدد و _ باشد.');
    }
    if (key.toLowerCase() == 'sqlite_sequence') {
      throw ArgumentError('نام فیلد مجاز نیست.');
    }
  }

  static List<FormSectionDefinition> _ensureFieldInSections(List<FormSectionDefinition> source, FieldDefinition field) {
    final result = source.map((e) => e.copyWith(fields: [...e.fields])).toList();
    var index = result.indexWhere((e) => e.title == field.section || e.id == field.section);
    if (index < 0) {
      result.add(FormSectionDefinition(id: _slug(field.section), title: field.section, order: result.length, fields: [field.key]));
    } else if (!result[index].fields.contains(field.key)) {
      result[index] = result[index].copyWith(fields: [...result[index].fields, field.key]);
    }
    return result;
  }

  static String _slug(String value) {
    final clean = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
    return clean.isEmpty ? 'section_${Random().nextInt(99999)}' : clean;
  }

  static RecordSchema _copySchema(
    RecordSchema schema, {
    List<FieldDefinition>? fields,
    List<FormSectionDefinition>? sections,
    List<String>? defaultSearchFields,
    String? dateField,
    List<String>? statsGroupFields,
    bool? statsEnabled,
    List<String>? filterFields,
    int? filterColumns,
    CardSchema? card,
  }) {
    return RecordSchema(
      schemaVersion: schema.schemaVersion + 1,
      fields: fields ?? schema.fields,
      sections: sections ?? schema.sections,
      defaultSearchFields: defaultSearchFields ?? schema.defaultSearchFields,
      dateField: dateField ?? schema.dateField,
      statsGroupFields: statsGroupFields ?? schema.statsGroupFields,
      statsEnabled: statsEnabled ?? schema.statsEnabled,
      filterFields: filterFields ?? schema.filterFields,
      filterColumns: filterColumns ?? schema.filterColumns,
      card: card ?? schema.card,
    );
  }
}
