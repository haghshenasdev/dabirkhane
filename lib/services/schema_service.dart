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
    return RecordSchema.fromDatabaseRow(Map<String, dynamic>.from(rows.first));
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
      ],
      sections: const [
        FormSectionDefinition(
          id: 'main',
          title: 'اطلاعات اصلی',
          order: 0,
          columns: 1,
          fields: ['Shomare_Radif', 'date'],
        ),
      ],
      defaultSearchFields: ['Shomare_Radif'],
      dateField: null,
      statsGroupFields: const [],
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
        _f('comment', 'توضیحات', FieldType.multiline, searchable: true, order: 6, section: 'اطلاعات اصلی', maxLines: 4),
        _f('shomare_badi', 'شماره بعدی', FieldType.text, searchable: true, order: 7, section: 'اطلاعات اصلی'),
        _f('goshashte', 'شماره قبلی', FieldType.text, searchable: true, order: 8, section: 'سایر اطلاعات'),
        _f('from_pywa', 'پیوست نامه', FieldType.text, searchable: true, order: 9, section: 'سایر اطلاعات'),
        _f('t_name_reside', 'تاریخ نامه', FieldType.date, searchable: true, order: 10, section: 'سایر اطلاعات'),
        _f('wordmost2', 'پیوست مکاتبه', FieldType.text, searchable: true, order: 11, section: 'سایر اطلاعات'),
        _f('t_name_ersali', 'تاریخ مکاتبه', FieldType.date, searchable: true, order: 12, section: 'سایر اطلاعات'),
        _f('adres_name', 'آدرس', FieldType.multiline, searchable: true, order: 13, section: 'سایر اطلاعات', maxLines: 4),
      ],
      sections: const [
        FormSectionDefinition(id: 'main', title: 'اطلاعات اصلی', order: 0, columns: 2, fields: ['Shomare_Radif', 'date', 'saheb_name', 'guy', 'sh_name_reside', 'onvan', 'comment', 'shomare_badi']),
        FormSectionDefinition(id: 'other', title: 'سایر اطلاعات', order: 1, columns: 1, collapsible: true, fields: ['goshashte', 'from_pywa', 't_name_reside', 'wordmost2', 't_name_ersali', 'adres_name']),
      ],
      defaultSearchFields: const ['guy', 'saheb_name', 'Shomare_Radif', 'sh_name_reside'],
      dateField: 'date',
      statsGroupFields: const ['onvan', 'guy', 'saheb_name'],
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
      );

  static Future<void> addField(FieldDefinition field, FieldDefinition result) async {
    _validateKey(field.key);
    final schema = await load();
    if (schema == null) throw StateError('ساختار دبیرخانه هنوز ایجاد نشده است.');
    if (schema.field(field.key) != null) throw StateError('این کلید فیلد قبلاً استفاده شده است.');

    final db = await DatabaseHelper.database;
    final columns = await _columns(db);
    if (columns.contains(field.key)) throw StateError('ستون ${field.key} از قبل در دیتابیس وجود دارد.');

    final sqlType = _sqlType(field.type);
    await db.execute('ALTER TABLE $recordTable ADD COLUMN "${_quote(field.key)}" $sqlType');

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
    final normalized = sections.asMap().entries.map((e) => e.value.copyWith(order: e.key)).toList();
    await save(_copySchema(schema, sections: normalized));
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
      card: card ?? schema.card,
    );
  }
}
