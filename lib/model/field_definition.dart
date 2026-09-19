import 'dart:convert';

enum FieldType {
  text,
  multiline,
  number,
  date,
  datetime,
  select,
  multiselect,
  boolean,
  phone,
  email,
  url,
  category,
  file,
}

FieldType fieldTypeFromString(String value) {
  return FieldType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => FieldType.text,
  );
}

class FieldDefinition {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final bool visible;
  final bool searchable;
  final bool sortable;
  final bool suggestions;
  final bool filterable;
  final bool system;
  final bool deletable;
  final String section;
  final int order;
  final int maxLines;
  final String? icon;
  final List<String> options;
  /// Number of grid columns occupied by this field inside its form section.
  final int gridSpan;

  const FieldDefinition({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.visible = true,
    this.searchable = false,
    this.sortable = false,
    this.suggestions = false,
    this.filterable = false,
    this.system = false,
    this.deletable = true,
    this.section = 'اطلاعات اصلی',
    this.order = 0,
    this.maxLines = 3,
    this.icon,
    this.options = const [],
    this.gridSpan = 1,
  });

  FieldDefinition copyWith({
    String? key,
    String? label,
    FieldType? type,
    bool? required,
    bool? visible,
    bool? searchable,
    bool? sortable,
    bool? suggestions,
    bool? filterable,
    bool? system,
    bool? deletable,
    String? section,
    int? order,
    int? maxLines,
    String? icon,
    List<String>? options,
    int? gridSpan,
  }) {
    return FieldDefinition(
      key: key ?? this.key,
      label: label ?? this.label,
      type: type ?? this.type,
      required: required ?? this.required,
      visible: visible ?? this.visible,
      searchable: searchable ?? this.searchable,
      sortable: sortable ?? this.sortable,
      suggestions: suggestions ?? this.suggestions,
      filterable: filterable ?? this.filterable,
      system: system ?? this.system,
      deletable: deletable ?? this.deletable,
      section: section ?? this.section,
      order: order ?? this.order,
      maxLines: maxLines ?? this.maxLines,
      icon: icon ?? this.icon,
      options: options ?? this.options,
      gridSpan: (gridSpan ?? this.gridSpan).clamp(1, 3).toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'required': required,
        'visible': visible,
        'searchable': searchable,
        'sortable': sortable,
        'suggestions': suggestions,
        'filterable': filterable,
        'system': system,
        'deletable': deletable,
        'section': section,
        'order': order,
        'maxLines': maxLines,
        'icon': icon,
        'options': options,
        'gridSpan': gridSpan,
      };

  factory FieldDefinition.fromJson(Map<String, dynamic> json) {
    return FieldDefinition(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? json['key']?.toString() ?? '',
      type: fieldTypeFromString(json['type']?.toString() ?? 'text'),
      required: json['required'] == true,
      visible: json['visible'] != false,
      searchable: json['searchable'] == true,
      sortable: json['sortable'] == true,
      suggestions: json['suggestions'] == true,
      filterable: json['filterable'] == true,
      system: json['system'] == true,
      deletable: json['deletable'] != false,
      section: json['section']?.toString() ?? 'اطلاعات اصلی',
      order: int.tryParse(json['order']?.toString() ?? '') ?? 0,
      maxLines: int.tryParse(json['maxLines']?.toString() ?? '') ?? 3,
      icon: json['icon']?.toString(),
      options: (json['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      gridSpan: ((int.tryParse(json['gridSpan']?.toString() ?? '') ?? 1).clamp(1, 3)).toInt(),
    );
  }
}

class FormSectionDefinition {
  final String id;
  final String title;
  final int order;
  final int columns;
  final bool collapsible;
  final List<String> fields;

  const FormSectionDefinition({
    required this.id,
    required this.title,
    this.order = 0,
    this.columns = 1,
    this.collapsible = false,
    this.fields = const [],
  });

  FormSectionDefinition copyWith({
    String? id,
    String? title,
    int? order,
    int? columns,
    bool? collapsible,
    List<String>? fields,
  }) {
    return FormSectionDefinition(
      id: id ?? this.id,
      title: title ?? this.title,
      order: order ?? this.order,
      columns: columns ?? this.columns,
      collapsible: collapsible ?? this.collapsible,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'order': order,
        'columns': columns,
        'collapsible': collapsible,
        'fields': fields,
      };

  factory FormSectionDefinition.fromJson(Map<String, dynamic> json) {
    return FormSectionDefinition(
      id: json['id']?.toString() ?? 'section',
      title: json['title']?.toString() ?? 'اطلاعات',
      order: int.tryParse(json['order']?.toString() ?? '') ?? 0,
      columns: ((int.tryParse(json['columns']?.toString() ?? '') ?? 1).clamp(1, 3)).toInt(),
      collapsible: json['collapsible'] == true,
      fields: (json['fields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}

class CardSchema {
  final String? titleField;
  final List<String> bodyFields;
  final List<String> footerFields;
  const CardSchema({this.titleField, this.bodyFields = const [], this.footerFields = const []});
  Map<String,dynamic> toJson()=>{'titleField':titleField,'bodyFields':bodyFields,'footerFields':footerFields};
  factory CardSchema.fromJson(Map<String,dynamic> j)=>CardSchema(titleField:j['titleField']?.toString(),bodyFields:(j['bodyFields'] as List?)?.map((e)=>e.toString()).toList()??const [],footerFields:(j['footerFields'] as List?)?.map((e)=>e.toString()).toList()??const []);
}

class RecordSchema {
  final int schemaVersion;
  final List<FieldDefinition> fields;
  final List<FormSectionDefinition> sections;
  final List<String> defaultSearchFields;
  final String? dateField;
  final List<String> statsGroupFields;
  final bool statsEnabled;
  final List<String> filterFields;
  final int filterColumns;
  final CardSchema card;

  const RecordSchema({
    this.schemaVersion = 1,
    this.fields = const [],
    this.sections = const [],
    this.defaultSearchFields = const [],
    this.dateField,
    this.statsGroupFields = const [],
    this.statsEnabled = true,
    this.filterFields = const [],
    this.filterColumns = 2,
    this.card = const CardSchema(),
  });

  FieldDefinition? field(String key) {
    for (final item in fields) {
      if (item.key == key) return item;
    }
    return null;
  }

  List<FieldDefinition> get activeFields =>
      fields.where((f) => f.visible && !f.system).toList()
        ..sort((a, b) => a.order.compareTo(b.order));

  List<FieldDefinition> get searchableFields =>
      fields.where((f) => f.searchable && f.visible).toList();

  Map<String, dynamic> fieldsJson() => {
        'schemaVersion': schemaVersion,
        'fields': fields.map((e) => e.toJson()).toList(),
      };

  Map<String, dynamic> layoutJson() => {
        'sections': sections.map((e) => e.toJson()).toList(),
      };

  Map<String, dynamic> searchJson() => {
        'defaultFields': defaultSearchFields,
        'filterFields': filterFields,
        'filterColumns': filterColumns,
      };

  Map<String, dynamic> cardJson() => card.toJson();

  Map<String, dynamic> statsJson() => {
        'enabled': statsEnabled,
        'dateField': dateField,
        'groupFields': statsGroupFields,
      };

  String get fieldsJsonString => jsonEncode(fieldsJson());
  String get layoutJsonString => jsonEncode(layoutJson());
  String get searchJsonString => jsonEncode(searchJson());
  String get statsJsonString => jsonEncode(statsJson());
  String get cardJsonString => jsonEncode(cardJson());

  factory RecordSchema.fromDatabaseRow(Map<String, dynamic> row) {
    final fieldsRaw = _decode(row['fields_json']);
    final layoutRaw = _decode(row['layout_json']);
    final searchRaw = _decode(row['search_json']);
    final statsRaw = _decode(row['stats_json']);
    final cardRaw = _decode(row['card_json']);

    final fields = (fieldsRaw['fields'] as List?)
            ?.whereType<Map>()
            .map((e) => FieldDefinition.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <FieldDefinition>[];

    final sections = (layoutRaw['sections'] as List?)
            ?.whereType<Map>()
            .map((e) => FormSectionDefinition.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const <FormSectionDefinition>[];

    final configuredFilterFields = (searchRaw['filterFields'] as List?)
            ?.map((e) => e.toString())
            .where((key) => fields.any((f) => f.key == key && f.visible && f.filterable && !f.system))
            .toList() ??
        <String>[];
    final fallbackFilterFields = fields
        .where((f) => f.visible && f.filterable && !f.system)
        .map((f) => f.key)
        .toList()
      ..sort((a, b) => (fields.firstWhere((f) => f.key == a).order)
          .compareTo(fields.firstWhere((f) => f.key == b).order));

    return RecordSchema(
      schemaVersion: int.tryParse(row['schema_version']?.toString() ?? '') ?? 1,
      fields: fields,
      sections: sections,
      defaultSearchFields: (searchRaw['defaultFields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      filterFields: configuredFilterFields.isNotEmpty ? configuredFilterFields : fallbackFilterFields,
      filterColumns: ((int.tryParse(searchRaw['filterColumns']?.toString() ?? '') ?? 2).clamp(1, 2)).toInt(),
      dateField: statsRaw['dateField']?.toString(),
      statsGroupFields: (statsRaw['groupFields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      statsEnabled: statsRaw['enabled'] != false,
      card: CardSchema.fromJson(cardRaw),
    );
  }

  static Map<String, dynamic> _decode(dynamic value) {
    if (value == null) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(value.toString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
