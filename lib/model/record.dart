/// مدل عمومی یک رکورد دبیرخانه.
///
/// ساختار واقعی داده‌ها در SQLite همچنان ستونی است؛ این Map فقط لایه مدل
/// را از نام فیلدهای ثابت جدا می‌کند تا Schema بتواند فرم را توسعه دهد.
class Record {
  final int? shomareRadif;
  final Map<String, dynamic> fields;

  const Record({
    this.shomareRadif,
    this.fields = const <String, dynamic>{},
  });

  dynamic operator [](String key) => fields[key];

  Map<String, dynamic> toMap() => {
        'Shomare_Radif': shomareRadif,
        ...fields,
      };

  factory Record.fromMap(Map<String, dynamic> map) {
    final idValue = map['Shomare_Radif'];
    final id = idValue is int ? idValue : int.tryParse(idValue?.toString() ?? '');
    final fields = Map<String, dynamic>.from(map)..remove('Shomare_Radif');
    return Record(shomareRadif: id, fields: fields);
  }
}
