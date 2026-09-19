import 'dart:io';
import 'dart:convert';

import 'package:dabirkhane/model/reminder.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:dabirkhane/services/sync_models.dart';
import 'package:dabirkhane/utils/app_settings.dart';
import 'package:dabirkhane/services/sync/sync_network_client.dart';

class DatabaseHelper {
  static Database? _db;
  static bool _syncApplying = false;

  static Future<Database> get database async {
    if (_db != null) return _db!;

    _db = await initDb();
    return _db!;
  }

  static Future<String> _dbPath() async {
    return getDbPath();
  }

  static Future<List<String>> getDistinctFieldValues(String field) async {
    final db = await database;
    await _ensureFieldExists(field);
    final safeField = _quoteIdentifier(field);

    final results = await db.rawQuery('''
      SELECT DISTINCT $safeField
      FROM daftare_andicator
      WHERE $safeField IS NOT NULL
        AND $safeField != ""
      ''');

    return results.map((e) => e[field].toString()).toList();
  }

  static Future<List<String>> searchDistinctField(
    String field,
    String query,
  ) async {
    final db = await database;
    await _ensureFieldExists(field);
    final safeField = _quoteIdentifier(field);

    final result = await db.rawQuery(
      '''
      SELECT DISTINCT $safeField
      FROM daftare_andicator
      WHERE $safeField IS NOT NULL
        AND $safeField != ''
        AND CAST($safeField AS TEXT) LIKE ?
      ORDER BY Shomare_Radif DESC
      LIMIT 5
      ''',
      ['%$query%'],
    );

    return result
        .map((e) => e[field]?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Future<List<String>> searchSahebName(String query) async {
    if (query.trim().isEmpty) return [];
    return searchDistinctField('saheb_name', query);
  }

  static Future<Map<String, dynamic>?> getLastRecordBySahebName(
    String name,
  ) async {
    final db = await database;

    final res = await db.rawQuery(
      '''
      SELECT *
      FROM daftare_andicator
      WHERE saheb_name = ?
      ORDER BY Shomare_Radif DESC
      LIMIT 1
      ''',
      [name],
    );

    if (res.isNotEmpty) {
      return res.first;
    }

    return null;
  }

  static String _quoteIdentifier(String value) => '"${value.replaceAll('"', '""')}"';

  static Future<void> _ensureFieldExists(String field) async {
    final columns = await _columns();
    if (!columns.contains(field)) {
      throw ArgumentError('فیلد $field در ساختار دبیرخانه وجود ندارد.');
    }
  }

  static Future<Set<String>> _columns() async {
    final db = await database;
    final rows = await db.rawQuery('PRAGMA table_info(daftare_andicator)');
    return rows.map((e) => e['name']?.toString() ?? '').toSet();
  }

  static Future<List<String>> _searchableFields() async {
    final db = await database;
    final rows = await db.query('record_schema', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return ['Shomare_Radif'];
    try {
      final fieldsDecoded = jsonDecode(rows.first['fields_json'].toString()) as Map<String, dynamic>;
      final fields = (fieldsDecoded['fields'] as List?) ?? const [];
      final searchable = fields.whereType<Map>().where((e) => e['searchable'] == true && e['visible'] != false).map((e) => e['key'].toString()).toSet();
      final searchDecoded = jsonDecode(rows.first['search_json'].toString()) as Map<String, dynamic>;
      final configured = (searchDecoded['defaultFields'] as List?)?.map((e) => e.toString()).where(searchable.contains).toList() ?? const <String>[];
      return configured.isNotEmpty ? configured : searchable.toList();
    } catch (_) {
      return ['Shomare_Radif'];
    }
  }

  static Future<Database> initDb() async {
    final dbPath = await _dbPath();

    return openDatabase(
      dbPath,
      version: 7,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS daftare_andicator (
            Shomare_Radif INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL DEFAULT '',
            sync_id TEXT,
            sync_updated_at TEXT,
            sync_deleted INTEGER NOT NULL DEFAULT 0
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS categories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE IF NOT EXISTS record_categories (
            record_id TEXT NOT NULL,
            category_id INTEGER NOT NULL,
            PRIMARY KEY (record_id, category_id),
            FOREIGN KEY (record_id)
              REFERENCES daftare_andicator(Shomare_Radif)
              ON DELETE CASCADE,
            FOREIGN KEY (category_id)
              REFERENCES categories(id)
              ON DELETE CASCADE
          );
        ''');

        await db.execute('''
  CREATE TABLE IF NOT EXISTS reminders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id INTEGER NOT NULL,
    due_date TEXT NOT NULL,
    text TEXT NOT NULL,
    status INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL,
    completed_at TEXT
  );
''');

        await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_reminders_record_id
  ON reminders(record_id);
''');

        await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_reminders_due_date
  ON reminders(due_date);
''');

        await db.execute('''
  CREATE TABLE IF NOT EXISTS record_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_id INTEGER NOT NULL,
    action TEXT NOT NULL,
    field_name TEXT,
    old_value TEXT,
    new_value TEXT,
    created_at TEXT NOT NULL
  );
''');

        await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_record_history_record_id
  ON record_history(record_id);
''');

        await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_record_history_created_at
  ON record_history(created_at);
''');

        await _createSyncTables(db);

        await db.execute('''
          CREATE TABLE IF NOT EXISTS record_schema (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            schema_version INTEGER NOT NULL DEFAULT 1,
            fields_json TEXT NOT NULL,
            layout_json TEXT NOT NULL,
            search_json TEXT NOT NULL,
            stats_json TEXT NOT NULL,
          card_json TEXT NOT NULL DEFAULT '{}',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');
      },

      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        record_id INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        text TEXT NOT NULL,
        status INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        completed_at TEXT
      );
    ''');

          await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reminders_record_id
      ON reminders(record_id);
    ''');

          await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_reminders_due_date
      ON reminders(due_date);
    ''');
        }

        if (oldVersion < 3) {
          await db.execute('''
    CREATE TABLE IF NOT EXISTS record_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      record_id INTEGER NOT NULL,
      action TEXT NOT NULL,
      field_name TEXT,
      old_value TEXT,
      new_value TEXT,
      created_at TEXT NOT NULL
    );
  ''');

          await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_record_history_record_id
    ON record_history(record_id);
  ''');

          await db.execute('''
    CREATE INDEX IF NOT EXISTS idx_record_history_created_at
    ON record_history(created_at);
  ''');
        }

        if (oldVersion < 4) {
          await _createDynamicSchemaForLegacyDatabase(db);
        }

        // نسخه 5: ستون card_json و ستون date را برای دیتابیس‌های قدیمی
        // تضمین می‌کند. در نسخه‌های قبلی این متد تعریف شده بود اما از
        // onUpgrade فراخوانی نمی‌شد.
        if (oldVersion < 6) {
          await _ensureV5(db);
        }

        // نسخه 6 فقط منطق Schema را ارتقا داده است؛ نرمال‌سازی فیلدهای
        // داینامیک هنگام SchemaService.load انجام می‌شود تا با نسخه‌های
        // قبلی که قبلاً نصب شده‌اند نیز سازگار باشد.
        if (oldVersion < 7) {
          await _createSyncTables(db);
          await _ensureSyncColumns(db);
        }
      },
    );
  }

  static Future<void> _createSyncTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_changes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        change_id TEXT UNIQUE NOT NULL,
        device_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_changes_entity
      ON sync_changes(entity_type, entity_id);
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_number_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        next_number INTEGER NOT NULL
      );
    ''');
  }

  static Future<void> _ensureSyncColumns(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(daftare_andicator)');
    final names = columns.map((e) => e['name']?.toString()).toSet();
    if (!names.contains('sync_id')) await db.execute("ALTER TABLE daftare_andicator ADD COLUMN sync_id TEXT");
    if (!names.contains('sync_updated_at')) await db.execute("ALTER TABLE daftare_andicator ADD COLUMN sync_updated_at TEXT");
    if (!names.contains('sync_deleted')) await db.execute("ALTER TABLE daftare_andicator ADD COLUMN sync_deleted INTEGER NOT NULL DEFAULT 0");
    final rows = await db.query('daftare_andicator', columns: ['Shomare_Radif', 'sync_id']);
    for (final row in rows) {
      final id = (row['Shomare_Radif'] as num).toInt();
      final syncId = row['sync_id']?.toString();
      if (syncId == null || syncId.isEmpty) {
        await db.update('daftare_andicator', {'sync_id': 'legacy-record-$id'}, where: 'Shomare_Radif = ?', whereArgs: [id]);
      }
    }
  }

  static Future<int> reserveMasterLetterNumber() async {
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query('sync_number_state', where: 'id = 1', limit: 1);
      int next;
      if (rows.isEmpty) {
        next = ((await _maxLetterNumber(txn)) ?? 0) + 1;
        await txn.insert('sync_number_state', {'id': 1, 'next_number': next + 1});
      } else {
        next = (rows.first['next_number'] as num).toInt();
        await txn.update('sync_number_state', {'next_number': next + 1}, where: 'id = 1');
      }
      return next;
    });
  }

  static Future<int?> _maxLetterNumber(DatabaseExecutor db) async {
    final rows = await db.rawQuery('SELECT MAX(Shomare_Radif) AS maxRadif FROM daftare_andicator');
    return (rows.first['maxRadif'] as num?)?.toInt();
  }

  static Future<void> ensureSyncIdentity() async {
    final db = await database;
    await _createSyncTables(db);
    await _ensureSyncColumns(db);
    final state = await db.query('sync_number_state', where: 'id = 1', limit: 1);
    if (state.isEmpty && await AppSettings.getSyncRole() == 'master') {
      final next = ((await _maxLetterNumber(db)) ?? 0) + 1;
      await db.insert('sync_number_state', {'id': 1, 'next_number': next});
    }
    final syncCountRows = await db.rawQuery('SELECT COUNT(*) AS c FROM sync_changes');
    final syncCount = (syncCountRows.first['c'] as num?)?.toInt() ?? 0;
    if (syncCount == 0) {
      final records = await db.query('daftare_andicator');
      for (final record in records) {
        final syncId = record['sync_id']?.toString();
        if (syncId == null || syncId.isEmpty) continue;
        final categoriesRows = await db.rawQuery('SELECT c.name FROM categories c JOIN record_categories rc ON rc.category_id = c.id WHERE rc.record_id = ?', [record['Shomare_Radif']]);
        final categories = categoriesRows.map((e) => e['name']?.toString() ?? '').where((e) => e.isNotEmpty).toList();
        await _logSyncChange(db, entityType: 'record', entityId: syncId, operation: 'upsert', payload: {'record': record, 'categories': categories});
      }
    }
  }

  static Future<void> _logSyncChange(DatabaseExecutor db, {required String entityType, required String entityId, required String operation, required Map<String, dynamic> payload}) async {
    if (_syncApplying) return;
    final deviceId = await AppSettings.getDeviceId();
    final now = DateTime.now().toUtc().toIso8601String();
    final changeId = '$deviceId-${DateTime.now().microsecondsSinceEpoch}-$entityType-$entityId';
    await db.insert('sync_changes', {'change_id': changeId, 'device_id': deviceId, 'entity_type': entityType, 'entity_id': entityId, 'operation': operation, 'payload': jsonEncode(payload), 'created_at': now});
  }

  static Future<List<SyncChange>> getSyncChangesAfter(int id, {int limit = 100}) async {
    final db = await database;
    final rows = await db.query('sync_changes', where: 'id > ?', whereArgs: [id], orderBy: 'id ASC', limit: limit);
    return rows.map((row) => SyncChange.fromMap(Map<String, dynamic>.from(row))).toList();
  }

  static Future<int> getLastSyncChangeId() async {
    final db = await database;
    final rows = await db.rawQuery('SELECT MAX(id) AS id FROM sync_changes');
    return (rows.first['id'] as num?)?.toInt() ?? 0;
  }

  static Future<T> runWithoutSyncLogging<T>(Future<T> Function() action) async {
    final previous = _syncApplying;
    _syncApplying = true;
    try { return await action(); } finally { _syncApplying = previous; }
  }

  static Future<void> applySyncChange(SyncChange change) async {
    await runWithoutSyncLogging(() async {
      final db = await database;
      final p = change.payload;
      if (change.entityType == 'record') {
        if (change.operation == 'delete') {
          await db.update('daftare_andicator', {'sync_deleted': 1, 'sync_updated_at': change.createdAt}, where: 'sync_id = ?', whereArgs: [change.entityId]);
          return;
        }
        final data = Map<String, dynamic>.from(p['record'] as Map? ?? {});
        final existing = await db.query('daftare_andicator', where: 'sync_id = ?', whereArgs: [change.entityId], limit: 1);
        data['sync_id'] = change.entityId;
        data['sync_updated_at'] = change.createdAt;
        data['sync_deleted'] = 0;
        if (existing.isEmpty) {
          await db.insert('daftare_andicator', data);
        } else {
          final localId = existing.first['Shomare_Radif'];
          data.remove('Shomare_Radif');
          await db.update('daftare_andicator', data, where: 'Shomare_Radif = ?', whereArgs: [localId]);
        }
        final local = await db.query('daftare_andicator', columns: ['Shomare_Radif'], where: 'sync_id = ?', whereArgs: [change.entityId], limit: 1);
        if (local.isNotEmpty) {
          final localId = local.first['Shomare_Radif'].toString();
          final categories = (p['categories'] as List? ?? const []).map((e) => e.toString()).toList();
          await db.delete('record_categories', where: 'record_id = ?', whereArgs: [localId]);
          for (final cat in categories) {
            await db.insert('categories', {'name': cat}, conflictAlgorithm: ConflictAlgorithm.ignore);
            final catRows = await db.query('categories', columns: ['id'], where: 'name = ?', whereArgs: [cat], limit: 1);
            if (catRows.isNotEmpty) await db.insert('record_categories', {'record_id': localId, 'category_id': catRows.first['id']}, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        return;
      }
      if (change.entityType == 'reminder') {
        final data = Map<String, dynamic>.from(p['reminder'] as Map? ?? {});
        final id = int.tryParse(change.entityId);
        if (id == null) return;
        if (change.operation == 'delete') {
          await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
          return;
        }
        final existing = await db.query('reminders', where: 'id = ?', whereArgs: [id], limit: 1);
        if (existing.isEmpty) await db.insert('reminders', data); else await db.update('reminders', data, where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  static Future<void> _createDynamicSchemaForLegacyDatabase(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS record_schema (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        schema_version INTEGER NOT NULL DEFAULT 1,
        fields_json TEXT NOT NULL,
        layout_json TEXT NOT NULL,
        search_json TEXT NOT NULL,
        stats_json TEXT NOT NULL,
        card_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    final exists = await db.query('record_schema', where: 'id = 1', limit: 1);
    if (exists.isNotEmpty) return;

    const fields = [
      {'key':'Shomare_Radif','label':'شماره نامه','type':'number','required':true,'visible':true,'searchable':true,'sortable':true,'system':true,'deletable':false,'section':'اطلاعات اصلی','order':0},
      {'key':'date','label':'تاریخ','type':'date','required':true,'visible':true,'searchable':true,'sortable':true,'section':'اطلاعات اصلی','order':1},
      {'key':'saheb_name','label':'صاحب نامه','type':'text','visible':true,'searchable':true,'sortable':true,'suggestions':true,'section':'اطلاعات اصلی','order':2},
      {'key':'guy','label':'موضوع','type':'text','visible':true,'searchable':true,'suggestions':true,'section':'اطلاعات اصلی','order':3},
      {'key':'sh_name_reside','label':'شماره تماس','type':'phone','visible':true,'searchable':true,'section':'اطلاعات اصلی','order':4},
      {'key':'onvan','label':'گیرنده نامه','type':'text','visible':true,'searchable':true,'suggestions':true,'section':'اطلاعات اصلی','order':5},
      {'key':'comment','label':'توضیحات','type':'multiline','visible':true,'searchable':true,'filterable':true,'maxLines':4,'section':'اطلاعات اصلی','order':6},
      {'key':'shomare_badi','label':'شماره بعدی','type':'text','visible':true,'searchable':true,'filterable':true,'section':'اطلاعات اصلی','order':7},
      {'key':'goshashte','label':'شماره قبلی','type':'text','visible':true,'searchable':true,'section':'سایر اطلاعات','order':8},
      {'key':'from_pywa','label':'پیوست نامه','type':'text','visible':true,'searchable':true,'section':'سایر اطلاعات','order':9},
      {'key':'t_name_reside','label':'تاریخ نامه','type':'date','visible':true,'searchable':true,'section':'سایر اطلاعات','order':10},
      {'key':'wordmost2','label':'پیوست مکاتبه','type':'text','visible':true,'searchable':true,'section':'سایر اطلاعات','order':11},
      {'key':'t_name_ersali','label':'تاریخ مکاتبه','type':'date','visible':true,'searchable':true,'section':'سایر اطلاعات','order':12},
      {'key':'adres_name','label':'آدرس','type':'multiline','visible':true,'searchable':true,'maxLines':4,'section':'سایر اطلاعات','order':13},
      {'key':'__category__','label':'دسته‌بندی','type':'category','visible':true,'searchable':false,'filterable':false,'system':true,'deletable':false,'section':'اطلاعات اصلی','order':14,'icon':'label'},
    ];
    final layout = {
      'sections': [
        {'id':'main','title':'اطلاعات اصلی','order':0,'columns':2,'fields':['Shomare_Radif','date','saheb_name','guy','sh_name_reside','onvan','comment','shomare_badi','__category__']},
        {'id':'other','title':'سایر اطلاعات','order':1,'columns':1,'collapsible':true,'fields':['goshashte','from_pywa','t_name_reside','wordmost2','t_name_ersali','adres_name']},
      ],
    };
    final search = {
      'defaultFields':['guy','saheb_name','Shomare_Radif','sh_name_reside'],
      'filterFields':['onvan','comment','shomare_badi','saheb_name','guy','sh_name_reside'],
      'filterColumns':2,
    };
    final stats = {'enabled':true,'dateField':'date','groupFields':['onvan','guy','saheb_name']};
    final now = DateTime.now().toIso8601String();

    await db.insert('record_schema', {
      'id':1,
      'schema_version':1,
      'fields_json':jsonEncode({'schemaVersion':1,'fields':fields}),
      'layout_json':jsonEncode(layout),
      'search_json':jsonEncode(search),
      'stats_json':jsonEncode(stats),
      'card_json':jsonEncode({}),
      'created_at':now,
      'updated_at':now,
    });
  }

  static Future<String> getDbPath() async {
    Directory dir;

    if (Platform.isWindows) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      final dbPath = await getDatabasesPath();
      return join(dbPath, 'dabirkhane.sqlite');
    }

    return join(dir.path, 'dabirkhane.sqlite');
  }

  // ============================================================
  // CURSOR PAGINATION
  // ============================================================
  //
  // به جای OFFSET از آخرین Shomare_Radif استفاده می‌کنیم.
  //
  // مثال:
  //
  // صفحه اول:
  // 1000 ... 971
  //
  // cursor = 971
  //
  // صفحه بعد:
  // WHERE Shomare_Radif < 971
  //
  // این روش با اضافه شدن رکورد جدید به ابتدای دیتابیس
  // باعث تکرار یا جا افتادن رکوردها نمی‌شود.
  //
  static Future<List<Map<String, dynamic>>> getPaged({
    required int limit,
    int? beforeId,
    String? search,
    required String? fromDate,
    required String? toDate,
    required String? onvan,
    List<String>? categories,
    String? comment,
    String? shomareBadi,
    // وضعیت یادآور
    int reminderFilter = 0,
    Map<String, String>? dynamicFilters,
  }) async {
    final db = await database;

    final List<String> conditions = [];
    final List<Object?> args = [];

    // ------------------------------------------------------------
    // Cursor
    // ------------------------------------------------------------
    if (beforeId != null) {
      conditions.add('Shomare_Radif < ?');
      args.add(beforeId);
    }

    // ------------------------------------------------------------
    // جستجوی عمومی
    // ------------------------------------------------------------
    if (search != null && search.trim().isNotEmpty) {
      final searchable = await _searchableFields();
      final existing = await _columns();
      final q = search.trim().replaceAll('\u200c', '').replaceAll('\u200d', '');
      final expressions = <String>[];
      for (final field in searchable) {
        if (!existing.contains(field)) continue;
        final safe = _quoteIdentifier(field);
        expressions.add("REPLACE(REPLACE(CAST(COALESCE($safe, '') AS TEXT), char(8204), ''), char(8205), '') LIKE ?");
        args.add('%$q%');
      }
      if (expressions.isNotEmpty) {
        conditions.add('(${expressions.join(' OR ')})');
      }
    }

    // ------------------------------------------------------------
    // فیلتر یادآور
    //
    // 0 = همه
    // 1 = موعدرسیده
    // 2 = دارای یادآور فعال
    // 3 = یادآور آینده
    // ------------------------------------------------------------

    if (reminderFilter == 1) {
      conditions.add('''
    EXISTS (
      SELECT 1
      FROM reminders r
      WHERE r.record_id = daftare_andicator.Shomare_Radif
        AND r.status = ?
        AND r.due_date <= ?
    )
  ''');

      args.add(ReminderStatus.pending);
      args.add(DateTime.now().toIso8601String());
    }

    if (reminderFilter == 2) {
      conditions.add('''
    EXISTS (
      SELECT 1
      FROM reminders r
      WHERE r.record_id = daftare_andicator.Shomare_Radif
        AND r.status = ?
    )
  ''');

      args.add(ReminderStatus.pending);
    }

    if (reminderFilter == 3) {
      conditions.add('''
    EXISTS (
      SELECT 1
      FROM reminders r
      WHERE r.record_id = daftare_andicator.Shomare_Radif
        AND r.status = ?
        AND r.due_date > ?
    )
  ''');

      args.add(ReminderStatus.pending);
      args.add(DateTime.now().toIso8601String());
    }

    // ------------------------------------------------------------
    // فیلتر عنوان / گیرنده
    // ------------------------------------------------------------
    if (onvan != null && onvan.trim().isNotEmpty && (await _columns()).contains('onvan')) {
      conditions.add('onvan LIKE ?');
      args.add('%${onvan.trim()}%');
    }

    // 📝 فیلتر توضیحات
    if (comment != null && comment.isNotEmpty && (await _columns()).contains('comment')) {
      conditions.add('comment LIKE ?');
      args.add('%$comment%');
    }

    // 🔢 فیلتر شماره بعد
    if (shomareBadi != null && shomareBadi.isNotEmpty && (await _columns()).contains('shomare_badi')) {
      conditions.add('shomare_badi LIKE ?');
      args.add('%$shomareBadi%');
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ شروع
    // ------------------------------------------------------------
    if (fromDate != null && fromDate.trim().isNotEmpty && (await _columns()).contains('date')) {
      conditions.add('date >= ?');
      args.add(fromDate.trim());
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ پایان
    // ------------------------------------------------------------
    if (toDate != null && toDate.trim().isNotEmpty && (await _columns()).contains('date')) {
      conditions.add('date <= ?');
      args.add(toDate.trim());
    }

    // ------------------------------------------------------------
    // فیلترهای داینامیک Schema
    // ------------------------------------------------------------
    if (dynamicFilters != null && dynamicFilters.isNotEmpty) {
      final existing = await _columns();
      for (final entry in dynamicFilters.entries) {
        final value = entry.value.trim();
        if (value.isEmpty || !existing.contains(entry.key)) continue;
        final safe = _quoteIdentifier(entry.key);
        conditions.add("CAST(COALESCE($safe, '') AS TEXT) LIKE ?");
        args.add('%$value%');
      }
    }

    // ------------------------------------------------------------
    // فیلتر دسته‌بندی
    // ------------------------------------------------------------
    if (categories != null && categories.isNotEmpty) {
      final placeholders = List.generate(
        categories.length,
        (_) => '?',
      ).join(',');

      conditions.add('''
        Shomare_Radif IN (
          SELECT rc.record_id
          FROM record_categories rc
          JOIN categories c
            ON c.id = rc.category_id
          WHERE c.name IN ($placeholders)
          GROUP BY rc.record_id
          HAVING COUNT(DISTINCT c.name) = ?
        )
      ''');

      args.addAll(categories);
      args.add(categories.length);
    }

    // ------------------------------------------------------------
    // WHERE
    // ------------------------------------------------------------
    String whereClause = '';

    if (conditions.isNotEmpty) {
      whereClause = 'WHERE ${conditions.join(' AND ')}';
    }

    // ------------------------------------------------------------
    // Query
    // ------------------------------------------------------------
    final result = await db.rawQuery(
      '''
      SELECT *
      FROM daftare_andicator
      $whereClause
      ORDER BY Shomare_Radif DESC
      LIMIT ?
      ''',
      [...args, limit],
    );

    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  // ============================================================
  // CRUD
  // ============================================================

  static Future<int> insert(Map<String, dynamic> data) async {
    final db = await database;

    return db.transaction((txn) async {
      await _ensureSyncColumns(txn);
      data = Map<String, dynamic>.from(data);
      if (!data.containsKey('Shomare_Radif') || data['Shomare_Radif'] == null) {
        final role = await AppSettings.getSyncRole();
        if (await AppSettings.getSyncEnabled()) {
          if (role == 'master') {
            final state = await txn.query('sync_number_state', where: 'id = 1', limit: 1);
            if (state.isEmpty) {
              final maxRows = await txn.rawQuery('SELECT MAX(Shomare_Radif) AS maxRadif FROM daftare_andicator');
              final next = ((maxRows.first['maxRadif'] as num?)?.toInt() ?? 0) + 1;
              await txn.insert('sync_number_state', {'id': 1, 'next_number': next + 1});
              data['Shomare_Radif'] = next;
            } else {
              final next = (state.first['next_number'] as num).toInt();
              await txn.update('sync_number_state', {'next_number': next + 1}, where: 'id = 1');
              data['Shomare_Radif'] = next;
            }
          } else {
            for (var attempt = 0; attempt < 20; attempt++) {
              final masterNumber = await SyncNetworkClient.requestNextLetterNumber();
              if (masterNumber == null) break;
              final exists = await txn.query('daftare_andicator', columns: ['Shomare_Radif'], where: 'Shomare_Radif = ?', whereArgs: [masterNumber], limit: 1);
              if (exists.isEmpty) {
                data['Shomare_Radif'] = masterNumber;
                break;
              }
            }
          }
        }
      }
      final syncId = data['sync_id']?.toString() ?? '${await AppSettings.getDeviceId()}-${DateTime.now().microsecondsSinceEpoch}';
      data['sync_id'] = syncId;
      data['sync_updated_at'] = DateTime.now().toUtc().toIso8601String();
      data['sync_deleted'] = 0;
      final id = await txn.insert('daftare_andicator', data);

      await txn.insert('record_history', {
        'record_id': id,
        'action': 'create',
        'field_name': null,
        'old_value': null,
        'new_value': 'نامه ایجاد شد',
        'created_at': DateTime.now().toIso8601String(),
      });
      await _logSyncChange(txn, entityType: 'record', entityId: syncId, operation: 'upsert', payload: {'record': data, 'categories': <String>[]});
      return id;
    });
  }

  static Future<int> update(int id, Map<String, dynamic> data) async {
    final db = await database;

    return db.transaction((txn) async {
      final oldResult = await txn.query(
        'daftare_andicator',
        where: 'Shomare_Radif = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (oldResult.isEmpty) {
        throw Exception('نامه شماره $id برای بروزرسانی پیدا نشد.');
      }

      final oldData = Map<String, dynamic>.from(oldResult.first);

      final changedFields = <Map<String, dynamic>>[];

      for (final entry in data.entries) {
        final field = entry.key;

        // شماره ردیف شناسه اصلی است و نباید به عنوان تغییر
        // در تاریخچه ثبت شود.
        if (field == 'Shomare_Radif') {
          continue;
        }

        final oldValue = oldData[field]?.toString() ?? '';

        final newValue = entry.value?.toString() ?? '';

        if (oldValue != newValue) {
          changedFields.add({
            'field': field,
            'oldValue': oldValue,
            'newValue': newValue,
          });
        }
      }

      data = Map<String, dynamic>.from(data);
      data.remove('sync_id');
      data.remove('sync_deleted');
      data['sync_updated_at'] = DateTime.now().toUtc().toIso8601String();
      final result = await txn.update('daftare_andicator', data, where: 'Shomare_Radif = ?', whereArgs: [id]);

      if (changedFields.isNotEmpty) {
        final now = DateTime.now().toIso8601String();

        for (final change in changedFields) {
          await txn.insert('record_history', {
            'record_id': id,
            'action': 'update',
            'field_name': _historyFieldLabel(change['field'] as String),
            'old_value': change['oldValue'],
            'new_value': change['newValue'],
            'created_at': now,
          });
        }
      }

      final after = await txn.query('daftare_andicator', where: 'Shomare_Radif = ?', whereArgs: [id], limit: 1);
      if (after.isNotEmpty) {
        await _logSyncChange(txn, entityType: 'record', entityId: after.first['sync_id'].toString(), operation: 'upsert', payload: {'record': after.first, 'categories': <String>[]});
      }
      return result;
    });
  }

  static Future<List<Map<String, dynamic>>> getAll() async {
    final db = await database;

    final result = await db.query(
      'daftare_andicator',
      orderBy: 'Shomare_Radif DESC',
    );

    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<int?> getLastShomareRadif() async {
    final db = await database;

    final result = await db.rawQuery('''
      SELECT MAX(Shomare_Radif) AS maxRadif
      FROM daftare_andicator
      ''');

    if (result.isNotEmpty) {
      return result.first['maxRadif'] as int?;
    }

    return null;
  }

  static Future<List<String>> searchCategories(String query) async {
    final db = await database;

    final res = await db.rawQuery(
      '''
      SELECT name
      FROM categories
      WHERE name LIKE ?
      LIMIT 10
      ''',
      ['%$query%'],
    );

    return res.map((e) => e['name'] as String).toList();
  }

  static Future<void> saveCategoriesForRecord(
    String recordId,
    List<String> categories,
  ) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'record_categories',
        where: 'record_id = ?',
        whereArgs: [recordId],
      );

      for (final cat in categories) {
        await txn.insert('categories', {
          'name': cat,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);

        final idRes = await txn.query(
          'categories',
          columns: ['id'],
          where: 'name = ?',
          whereArgs: [cat],
        );

        final catId = idRes.first['id'];

        await txn.insert('record_categories', {
          'record_id': recordId,
          'category_id': catId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  static Future<List<String>> getCategoriesForRecord(String recordId) async {
    final db = await database;

    final res = await db.rawQuery(
      '''
      SELECT c.name
      FROM categories c
      JOIN record_categories rc
        ON rc.category_id = c.id
      WHERE rc.record_id = ?
      ''',
      [recordId],
    );

    return res.map((e) => e['name'] as String).toList();
  }

  // ============================================================
  // REMINDERS
  // ============================================================

  /// ایجاد یک یادآور
  static Future<int> insertReminder(Reminder reminder) async {
    final db = await database;

    final id = await db.insert('reminders', reminder.toMap());
    final row = await db.query('reminders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isNotEmpty) await _logSyncChange(db, entityType: 'reminder', entityId: id.toString(), operation: 'upsert', payload: {'reminder': row.first});
    return id;
  }

  /// دریافت یک یادآور با ID
  static Future<Reminder?> getReminderById(int id) async {
    final db = await database;

    final result = await db.query(
      'reminders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return Reminder.fromMap(Map<String, dynamic>.from(result.first));
  }

  /// دریافت تمام یادآورهای یک نامه
  static Future<List<Reminder>> getRemindersForRecord(int recordId) async {
    final db = await database;

    final result = await db.query(
      'reminders',
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'due_date ASC',
    );

    return result
        .map((row) => Reminder.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// دریافت یادآورهای فعال یک نامه
  static Future<List<Reminder>> getPendingRemindersForRecord(
    int recordId,
  ) async {
    final db = await database;

    final result = await db.query(
      'reminders',
      where: 'record_id = ? AND status = ?',
      whereArgs: [recordId, ReminderStatus.pending],
      orderBy: 'due_date ASC',
    );

    return result
        .map((row) => Reminder.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// بروزرسانی یادآور
  static Future<int> updateReminder(Reminder reminder) async {
    if (reminder.id == null) {
      throw ArgumentError('برای بروزرسانی، reminder.id نباید null باشد.');
    }

    final db = await database;

    final result = await db.update('reminders', reminder.toMap(), where: 'id = ?', whereArgs: [reminder.id]);
    final row = await db.query('reminders', where: 'id = ?', whereArgs: [reminder.id], limit: 1);
    if (row.isNotEmpty) await _logSyncChange(db, entityType: 'reminder', entityId: reminder.id.toString(), operation: 'upsert', payload: {'reminder': row.first});
    return result;
  }

  /// علامت‌گذاری به عنوان انجام‌شده
  static Future<int> completeReminder(int id) async {
    final db = await database;

    final result = await db.update('reminders', {'status': ReminderStatus.completed, 'completed_at': DateTime.now().toIso8601String()}, where: 'id = ?', whereArgs: [id]);
    final row = await db.query('reminders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isNotEmpty) await _logSyncChange(db, entityType: 'reminder', entityId: id.toString(), operation: 'upsert', payload: {'reminder': row.first});
    return result;
  }

  /// لغو یادآور
  static Future<int> cancelReminder(int id) async {
    final db = await database;

    final result = await db.update('reminders', {'status': ReminderStatus.cancelled}, where: 'id = ?', whereArgs: [id]);
    final row = await db.query('reminders', where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isNotEmpty) await _logSyncChange(db, entityType: 'reminder', entityId: id.toString(), operation: 'upsert', payload: {'reminder': row.first});
    return result;
  }

  /// حذف کامل یادآور
  static Future<int> deleteReminder(int id) async {
    final db = await database;

    final result = await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
    if (result > 0) await _logSyncChange(db, entityType: 'reminder', entityId: id.toString(), operation: 'delete', payload: {});
    return result;
  }

  /// یادآورهای فعال و سررسیدشده
  static Future<List<Reminder>> getDueReminders() async {
    final db = await database;

    final now = DateTime.now().toIso8601String();

    final result = await db.query(
      'reminders',
      where: 'status = ? AND due_date <= ?',
      whereArgs: [ReminderStatus.pending, now],
      orderBy: 'due_date ASC',
    );

    return result
        .map((row) => Reminder.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  /// تعداد یادآورهای سررسیدشده
  static Future<int> getDueRemindersCount() async {
    final db = await database;

    final now = DateTime.now().toIso8601String();

    final result = await db.rawQuery(
      '''
    SELECT COUNT(*) AS count
    FROM reminders
    WHERE status = ?
      AND due_date <= ?
    ''',
      [ReminderStatus.pending, now],
    );

    return (result.first['count'] as num?)?.toInt() ?? 0;
  }

  /// تمام یادآورهای فعال
  static Future<List<Reminder>> getPendingReminders() async {
    final db = await database;

    final result = await db.query(
      'reminders',
      where: 'status = ?',
      whereArgs: [ReminderStatus.pending],
      orderBy: 'due_date ASC',
    );

    return result
        .map((row) => Reminder.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  static Future<Set<int>> getDueReminderRecordIds() async {
    final db = await database;

    final now = DateTime.now().toIso8601String();

    final result = await db.rawQuery(
      '''
    SELECT DISTINCT record_id
    FROM reminders
    WHERE status = ?
      AND due_date <= ?
    ''',
      [ReminderStatus.pending, now],
    );

    return result.map((row) => (row['record_id'] as num).toInt()).toSet();
  }

  static Future<List<Map<String, dynamic>>> getRecordHistory(
    int recordId,
  ) async {
    final db = await database;

    final result = await db.query(
      'record_history',
      where: 'record_id = ?',
      whereArgs: [recordId],
      orderBy: 'created_at DESC, id DESC',
    );

    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  static Future<void> addRecordHistory({
    required int recordId,
    required String action,
    String? fieldName,
    String? oldValue,
    String? newValue,
  }) async {
    final db = await database;

    await db.insert('record_history', {
      'record_id': recordId,
      'action': action,
      'field_name': fieldName,
      'old_value': oldValue,
      'new_value': newValue,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> _ensureV5(DatabaseExecutor db) async {
    final sc = await db.rawQuery('PRAGMA table_info(record_schema)');
    if (!sc.any((r) => r['name'] == 'card_json')) {
      await db.execute("ALTER TABLE record_schema ADD COLUMN card_json TEXT NOT NULL DEFAULT '{}'");
    }
    final rc = await db.rawQuery('PRAGMA table_info(daftare_andicator)');
    if (!rc.any((r) => r['name'] == 'date')) {
      await db.execute("ALTER TABLE daftare_andicator ADD COLUMN date TEXT NOT NULL DEFAULT ''");
    }
  }

  static Future<void> closeDb() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  static String _historyFieldLabel(String field) {
    const labels = {
      'Shomare_Radif': 'شماره نامه',
      'goshashte': 'شماره قبلی',
      'date': 'تاریخ',
      'saheb_name': 'صاحب نامه',
      'guy': 'موضوع',
      'from_pywa': 'پیوست نامه',
      'sh_name_reside': 'شماره تماس',
      't_name_reside': 'تاریخ نامه',
      'onvan': 'گیرنده نامه',
      'comment': 'توضیحات',
      'shomare_badi': 'شماره بعدی',
      'wordmost2': 'پیوست مکاتبه',
      't_name_ersali': 'تاریخ مکاتبه',
      'adres_name': 'آدرس',
    };

    return labels[field] ?? field;
  }

  static Future<Map<String, dynamic>?> getById(int id) async {
    final db = await database;

    final result = await db.query(
      'daftare_andicator',
      where: 'Shomare_Radif = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(result.first);
  }

    // ============================================================
  // STREAM / CHUNK PAGINATION FOR CSV EXPORT
  // ============================================================
  //
  // رکوردها را به صورت دسته‌ای از دیتابیس می‌خواند.
  //
  // مزیت:
  // اگر 100,000 رکورد داشته باشیم، همه آنها وارد RAM نمی‌شوند.
  // مثلاً هر بار 500 رکورد خوانده می‌شود.
  //
  static Stream<List<Map<String, dynamic>>> streamPagedForExport({
    int chunkSize = 500,
    String? search,
    required String? fromDate,
    required String? toDate,
    required String? onvan,
    List<String>? categories,
    String? comment,
    String? shomareBadi,
    int reminderFilter = 0,
  }) async* {
    int? beforeId;

    while (true) {
      final chunk = await getPaged(
        limit: chunkSize,
        beforeId: beforeId,
        search: search,
        fromDate: fromDate,
        toDate: toDate,
        onvan: onvan,
        categories: categories,
        comment: comment,
        shomareBadi: shomareBadi,
        reminderFilter: reminderFilter,
      );

      if (chunk.isEmpty) {
        break;
      }

      yield chunk;

      // آخرین رکورد این دسته
      final lastRecord = chunk.last;

      final lastId = lastRecord['Shomare_Radif'];

      if (lastId == null) {
        break;
      }

      beforeId = (lastId as num).toInt();

      // اگر کمتر از chunkSize رکورد برگشته،
      // یعنی به انتهای نتایج رسیده‌ایم.
      if (chunk.length < chunkSize) {
        break;
      }
    }
  }
}
