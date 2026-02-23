import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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
    final List<Map<String, dynamic>> results = await db.rawQuery(
      'SELECT DISTINCT $field FROM daftare_andicator WHERE $field IS NOT NULL AND $field != ""',
    );
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

    if (query.trim().isEmpty) return [];

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
    String path = await _dbPath();

    return openDatabase(
      path,
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

        // ساخت جدول categories
        await db.execute('''
                CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT UNIQUE NOT NULL
);
      ''');

        // ساخت جدول record_categories
        await db.execute('''
        CREATE TABLE IF NOT EXISTS record_categories (
  record_id TEXT NOT NULL,
  category_id INTEGER NOT NULL,
  PRIMARY KEY (record_id, category_id),
  FOREIGN KEY (record_id) REFERENCES daftare_andicator(Shomare_Radif) ON DELETE CASCADE,
  FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE CASCADE
);
      ''');
      },
    );
  }

  static Future<String> getDbPath() async {
    Directory dir;

    if (Platform.isWindows) {
      // روی ویندوز داخل Documents
      dir = await getApplicationDocumentsDirectory();
    } else {
      // روی اندروید و سایر پلتفرم‌ها داخل مسیر امن دیتابیس
      final path = await getDatabasesPath();
      return join(path, 'dabirkhane.sqlite');
    }

    return join(dir.path, 'dabirkhane.sqlite');
  }

  static Future<List<Map<String, dynamic>>> getPaged({
    required int limit,
    required int offset,
    String? search,
    required String? fromDate,
    required String? toDate,
    required String? onvan,
    List<String>? categories,
  }) async {
    final db = await database;

    List<String> conditions = [];
    List<Object?> args = [];

    // 🔍 سرچ عمومی
    if (search != null && search.isNotEmpty) {
      conditions.add('''
      (
        guy LIKE ? 
        OR saheb_name LIKE ?
        OR Shomare_Radif LIKE ?
        OR sh_name_reside LIKE ?
      )
    ''');

      args.addAll(['%$search%', '%$search%', '%$search%', '%$search%']);
    }

    // 🏷 فیلتر عنوان
    if (onvan != null && onvan.isNotEmpty) {
      conditions.add('onvan LIKE ?');
      args.add('%$onvan%');
    }

    // 📅 فیلتر از تاریخ
    if (fromDate != null && fromDate.isNotEmpty) {
      conditions.add('date >= ?');
      args.add(fromDate);
    }

    // 📅 فیلتر تا تاریخ
    if (toDate != null && toDate.isNotEmpty) {
      conditions.add('date <= ?');
      args.add(toDate);
    }

    if (categories != null && categories.isNotEmpty) {
      final placeholders = List.generate(
        categories.length,
        (_) => '?',
      ).join(',');

      conditions.add('''
    Shomare_Radif IN (
      SELECT rc.record_id
      FROM record_categories rc
      JOIN categories c ON c.id = rc.category_id
      WHERE c.name IN ($placeholders)
      GROUP BY rc.record_id
      HAVING COUNT(DISTINCT c.name) = ?
    )
  ''');

      args.addAll(categories);
      args.add(categories.length); // برای اینکه همه دسته‌ها را داشته باشد
    }

    // ساخت WHERE داینامیک
    String whereClause = '';
    if (conditions.isNotEmpty) {
      whereClause = 'WHERE ${conditions.join(' AND ')}';
    }

    return await db.rawQuery(
      '''
    SELECT * FROM daftare_andicator
    $whereClause
    ORDER BY Shomare_Radif DESC
    LIMIT ? OFFSET ?
    ''',
      [...args, limit, offset],
    );
  }

  // CRUD
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
    return db.query('daftare_andicator', orderBy: 'Shomare_Radif DESC');
  }

  // متد گرفتن آخرین Shomare_Radif
  static Future<int?> getLastShomareRadif() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT MAX(Shomare_Radif) as maxRadif FROM daftare_andicator',
    );
    if (result.isNotEmpty) {
      return result.first['maxRadif'] as int?;
    }
    return null;
  }

  static Future<List<String>> searchCategories(String query) async {
    final db = await database;
    final res = await db.rawQuery(
      "SELECT name FROM categories WHERE name LIKE ? LIMIT 10",
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
    JOIN record_categories rc ON rc.category_id = c.id
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
}
