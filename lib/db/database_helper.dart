import 'dart:io';

import 'package:dabirkhane/model/reminder.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  static Database? _db;

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

    final results = await db.rawQuery('''
      SELECT DISTINCT $field
      FROM daftare_andicator
      WHERE $field IS NOT NULL
        AND $field != ""
      ''');

    return results.map((e) => e[field].toString()).toList();
  }

  static Future<List<String>> searchDistinctField(
    String field,
    String query,
  ) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT DISTINCT $field
      FROM daftare_andicator
      WHERE $field IS NOT NULL
        AND $field != ''
        AND $field LIKE ?
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
    final db = await database;

    if (query.trim().isEmpty) {
      return [];
    }

    final res = await db.rawQuery(
      '''
      SELECT DISTINCT saheb_name
      FROM daftare_andicator
      WHERE saheb_name LIKE ?
      ORDER BY Shomare_Radif DESC
      LIMIT 5
      ''',
      ['%$query%'],
    );

    return res
        .map((e) => e['saheb_name']?.toString())
        .where((e) => e != null && e!.isNotEmpty)
        .cast<String>()
        .toList();
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

  static Future<Database> initDb() async {
    final dbPath = await _dbPath();

    return openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS daftare_andicator (
            Shomare_Radif INTEGER PRIMARY KEY AUTOINCREMENT,
            goshashte TEXT,
            date TEXT,
            saheb_name TEXT,
            guy TEXT,
            from_pywa TEXT,
            sh_name_reside TEXT,
            t_name_reside TEXT,
            onvan TEXT,
            comment TEXT,
            shomare_badi TEXT,
            wordmost2 TEXT,
            t_name_ersali TEXT,
            adres_name TEXT
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
      },
    );
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
      conditions.add('''
        (
          guy LIKE ?
          OR saheb_name LIKE ?
          OR Shomare_Radif LIKE ?
          OR sh_name_reside LIKE ?
        )
      ''');

      args.addAll([
        '%${search.trim()}%',
        '%${search.trim()}%',
        '%${search.trim()}%',
        '%${search.trim()}%',
      ]);
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
    if (onvan != null && onvan.trim().isNotEmpty) {
      conditions.add('onvan LIKE ?');
      args.add('%${onvan.trim()}%');
    }

    // 📝 فیلتر توضیحات
    if (comment != null && comment.isNotEmpty) {
      conditions.add('comment LIKE ?');
      args.add('%$comment%');
    }

    // 🔢 فیلتر شماره بعد
    if (shomareBadi != null && shomareBadi.isNotEmpty) {
      conditions.add('shomare_badi LIKE ?');
      args.add('%$shomareBadi%');
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ شروع
    // ------------------------------------------------------------
    if (fromDate != null && fromDate.trim().isNotEmpty) {
      conditions.add('date >= ?');
      args.add(fromDate.trim());
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ پایان
    // ------------------------------------------------------------
    if (toDate != null && toDate.trim().isNotEmpty) {
      conditions.add('date <= ?');
      args.add(toDate.trim());
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
      final id = await txn.insert('daftare_andicator', data);

      await txn.insert('record_history', {
        'record_id': id,
        'action': 'create',
        'field_name': null,
        'old_value': null,
        'new_value': 'نامه ایجاد شد',
        'created_at': DateTime.now().toIso8601String(),
      });

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

      final result = await txn.update(
        'daftare_andicator',
        data,
        where: 'Shomare_Radif = ?',
        whereArgs: [id],
      );

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

    return db.insert('reminders', reminder.toMap());
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

    return db.update(
      'reminders',
      reminder.toMap(),
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  /// علامت‌گذاری به عنوان انجام‌شده
  static Future<int> completeReminder(int id) async {
    final db = await database;

    return db.update(
      'reminders',
      {
        'status': ReminderStatus.completed,
        'completed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// لغو یادآور
  static Future<int> cancelReminder(int id) async {
    final db = await database;

    return db.update(
      'reminders',
      {'status': ReminderStatus.cancelled},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// حذف کامل یادآور
  static Future<int> deleteReminder(int id) async {
    final db = await database;

    return db.delete('reminders', where: 'id = ?', whereArgs: [id]);
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
