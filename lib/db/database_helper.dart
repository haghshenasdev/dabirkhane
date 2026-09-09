import 'dart:io';

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
      version: 1,
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

    return db.insert('daftare_andicator', data);
  }

  static Future<int> update(int id, Map<String, dynamic> data) async {
    final db = await database;

    return db.update(
      'daftare_andicator',
      data,
      where: 'Shomare_Radif = ?',
      whereArgs: [id],
    );
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

  static Future<void> closeDb() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
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
}
