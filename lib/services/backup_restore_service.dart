import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../db/database_helper.dart';
import '../utils/app_settings.dart';

enum BackupType { database, previousMonthFiles, full }

enum BackupContentType { database, files, full, unknown }

class BackupResult {
  final bool success;
  final String? path;
  final String message;

  const BackupResult({required this.success, required this.message, this.path});
}

class RestoreResult {
  final bool success;
  final String message;
  final bool databaseRestored;
  final bool filesRestored;

  const RestoreResult({
    required this.success,
    required this.message,
    this.databaseRestored = false,
    this.filesRestored = false,
  });
}

class BackupInfo {
  final BackupContentType type;
  final String title;
  final String description;
  final File? file;
  final int? year;
  final int? month;

  const BackupInfo({
    required this.type,
    required this.title,
    required this.description,
    this.file,
    this.year,
    this.month,
  });
}

class BackupRestoreService {
  BackupRestoreService._();

  static const String _manifestFileName = 'manifest.json';
  static const int _backupVersion = 1;

  // ============================================================
  // Public API
  // ============================================================

  static Future<BackupResult> createBackup({
    required BackupType type,
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      onProgress?.call(0.05, 'در حال آماده‌سازی...');

      switch (type) {
        case BackupType.database:
          return await _createDatabaseBackup(onProgress: onProgress);

        case BackupType.previousMonthFiles:
          return await _createPreviousMonthFilesBackup(onProgress: onProgress);

        case BackupType.full:
          return await _createFullBackup(onProgress: onProgress);
      }
    } catch (e) {
      return BackupResult(success: false, message: 'خطا در ایجاد پشتیبان:\n$e');
    }
  }

  static Future<RestoreResult> restoreBackup(
    File backupFile, {
    void Function(double progress, String message)? onProgress,
  }) async {
    try {
      if (!await backupFile.exists()) {
        return const RestoreResult(
          success: false,
          message: 'فایل پشتیبان پیدا نشد.',
        );
      }

      final extension = path.extension(backupFile.path).toLowerCase();

      if (extension == '.sqlite' || extension == '.db') {
        return await _restoreDatabase(backupFile, onProgress: onProgress);
      }

      if (extension == '.zip') {
        return await _restoreZip(backupFile, onProgress: onProgress);
      }

      return const RestoreResult(
        success: false,
        message:
            'نوع فایل انتخاب‌شده قابل تشخیص نیست.\n'
            'فقط فایل‌های SQLite و ZIP پشتیبانی می‌شوند.',
      );
    } catch (e) {
      return RestoreResult(success: false, message: 'خطا در بازیابی:\n$e');
    }
  }

  static Future<BackupInfo> inspectBackup(File file) async {
    try {
      final extension = path.extension(file.path).toLowerCase();

      if (extension == '.sqlite' || extension == '.db') {
        return BackupInfo(
          type: BackupContentType.database,
          title: 'پشتیبان دیتابیس',
          description: 'این فایل شامل دیتابیس دبیرخانه است.',
          file: file,
        );
      }

      if (extension != '.zip') {
        return BackupInfo(
          type: BackupContentType.unknown,
          title: 'فایل ناشناخته',
          description: 'نوع فایل قابل تشخیص نیست.',
          file: file,
        );
      }

      final bytes = await file.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final manifestEntry = _findArchiveFile(archive, _manifestFileName);

      if (manifestEntry != null) {
        try {
          final manifest = jsonDecode(
            utf8.decode(manifestEntry.content as List<int>),
          );

          final type = manifest['type']?.toString();

          final year = _toInt(manifest['jalali_year']);
          final month = _toInt(manifest['jalali_month']);

          if (type == 'database') {
            return BackupInfo(
              type: BackupContentType.database,
              title: 'پشتیبان دیتابیس',
              description: _monthDescription('دیتابیس', year, month),
              file: file,
              year: year,
              month: month,
            );
          }

          if (type == 'files') {
            return BackupInfo(
              type: BackupContentType.files,
              title: 'پشتیبان فایل‌ها',
              description: _monthDescription('فایل‌های نامه‌ها', year, month),
              file: file,
              year: year,
              month: month,
            );
          }

          if (type == 'full') {
            return BackupInfo(
              type: BackupContentType.full,
              title: 'پشتیبان کامل',
              description: _monthDescription('دیتابیس و فایل‌ها', year, month),
              file: file,
              year: year,
              month: month,
            );
          }
        } catch (_) {
          // در صورت خراب بودن manifest
          // از تشخیص ساختار ZIP استفاده می‌کنیم.
        }
      }

      bool hasDatabase = false;
      bool hasFiles = false;

      for (final entry in archive) {
        if (entry.isFile) {
          final name = entry.name.replaceAll('\\', '/');

          if (name == 'database/dabirkhane.sqlite' ||
              name.endsWith('/dabirkhane.sqlite')) {
            hasDatabase = true;
          }

          if (name.startsWith('files/')) {
            hasFiles = true;
          }
        }
      }

      if (hasDatabase && hasFiles) {
        return BackupInfo(
          type: BackupContentType.full,
          title: 'پشتیبان کامل',
          description: 'دیتابیس و فایل‌های نامه‌ها',
          file: file,
        );
      }

      if (hasDatabase) {
        return BackupInfo(
          type: BackupContentType.database,
          title: 'پشتیبان دیتابیس',
          description: 'فایل شامل دیتابیس دبیرخانه است.',
          file: file,
        );
      }

      if (hasFiles) {
        return BackupInfo(
          type: BackupContentType.files,
          title: 'پشتیبان فایل‌ها',
          description: 'فایل شامل فایل‌های نامه‌ها است.',
          file: file,
        );
      }

      return BackupInfo(
        type: BackupContentType.unknown,
        title: 'پشتیبان ناشناخته',
        description: 'ساختار فایل ZIP قابل تشخیص نیست.',
        file: file,
      );
    } catch (e) {
      return BackupInfo(
        type: BackupContentType.unknown,
        title: 'فایل خراب',
        description: 'امکان بررسی فایل وجود ندارد.',
        file: file,
      );
    }
  }

  // ============================================================
  // Database Backup
  // ============================================================

  static Future<BackupResult> _createDatabaseBackup({
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.15, 'در حال آماده‌سازی دیتابیس...');

    final db = await DatabaseHelper.database;
    final dbFile = File(db.path);

    if (!await dbFile.exists()) {
      return const BackupResult(
        success: false,
        message: 'فایل دیتابیس پیدا نشد.',
      );
    }

    final fileName = _databaseBackupFileName();

    if (Platform.isAndroid) {
      final tempDir = await getTemporaryDirectory();

      final backupFile = File(path.join(tempDir.path, fileName));

      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      await dbFile.copy(backupFile.path);

      onProgress?.call(0.80, 'در حال آماده‌سازی اشتراک‌گذاری...');

      await Share.shareXFiles(
        [XFile(backupFile.path, mimeType: 'application/x-sqlite3')],
        subject: 'پشتیبان دیتابیس دبیرخانه',
        text: 'فایل پشتیبان دیتابیس دبیرخانه',
      );

      if (await backupFile.exists()) {
        await backupFile.delete();
      }

      onProgress?.call(1, 'پشتیبان‌گیری انجام شد.');

      return const BackupResult(
        success: true,
        message: 'پشتیبان دیتابیس آماده و برای اشتراک‌گذاری ارسال شد.',
      );
    }

    if (Platform.isWindows) {
      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'SQLite Database', extensions: ['sqlite', 'db']),
        ],
      );

      if (location == null) {
        return const BackupResult(success: false, message: 'عملیات لغو شد.');
      }

      final target = File(location.path);

      if (await target.exists()) {
        await target.delete();
      }

      await dbFile.copy(target.path);

      onProgress?.call(1, 'پشتیبان‌گیری انجام شد.');

      return BackupResult(
        success: true,
        path: target.path,
        message: 'پشتیبان دیتابیس با موفقیت ذخیره شد.\n\n${target.path}',
      );
    }

    return const BackupResult(
      success: false,
      message: 'پشتیبان‌گیری در این پلتفرم پشتیبانی نمی‌شود.',
    );
  }

  // ============================================================
  // Previous Month Files Backup
  // ============================================================

  static Future<BackupResult> _createPreviousMonthFilesBackup({
    void Function(double progress, String message)? onProgress,
  }) async {
    final previous = _getPreviousJalaliMonth();

    onProgress?.call(0.10, 'در حال پیدا کردن فایل‌های ماه قبل...');

    final lettersDir = await AppSettings.getLettersDirectory();

    final monthDir = Directory(
      path.join(
        lettersDir.path,
        previous.year.toString(),
        previous.month.toString(),
      ),
    );

    final files = <File>[];

    if (await monthDir.exists()) {
      await for (final entity in monthDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          files.add(entity);
        }
      }
    }

    if (files.isEmpty) {
      return BackupResult(
        success: false,
        message:
            'برای ماه ${previous.month} سال ${previous.year} '
            'فایلی برای پشتیبان‌گیری پیدا نشد.',
      );
    }

    final zipFile = await _createZipFile(
      type: BackupType.previousMonthFiles,
      files: files,
      year: previous.year,
      month: previous.month,
      includeDatabase: false,
      onProgress: onProgress,
    );

    return await _exportZipFile(
      zipFile,
      title: 'پشتیبان فایل‌های ماه ${previous.month}',
    );
  }

  // ============================================================
  // Full Backup
  // ============================================================

  static Future<BackupResult> _createFullBackup({
    void Function(double progress, String message)? onProgress,
  }) async {
    final previous = _getPreviousJalaliMonth();

    onProgress?.call(0.08, 'در حال آماده‌سازی دیتابیس...');

    final db = await DatabaseHelper.database;
    final dbFile = File(db.path);

    if (!await dbFile.exists()) {
      return const BackupResult(
        success: false,
        message: 'فایل دیتابیس پیدا نشد.',
      );
    }

    onProgress?.call(0.15, 'در حال پیدا کردن فایل‌های ماه قبل...');

    final lettersDir = await AppSettings.getLettersDirectory();

    final monthDir = Directory(
      path.join(
        lettersDir.path,
        previous.year.toString(),
        previous.month.toString(),
      ),
    );

    final files = <File>[];

    if (await monthDir.exists()) {
      await for (final entity in monthDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          files.add(entity);
        }
      }
    }

    final zipFile = await _createZipFile(
      type: BackupType.full,
      files: files,
      year: previous.year,
      month: previous.month,
      databaseFile: dbFile,
      includeDatabase: true,
      onProgress: onProgress,
    );

    return await _exportZipFile(zipFile, title: 'پشتیبان کامل دبیرخانه');
  }

  // ============================================================
  // ZIP Creation
  // ============================================================

  static Future<File> _createZipFile({
    required BackupType type,
    required List<File> files,
    required int year,
    required int month,
    required bool includeDatabase,
    File? databaseFile,
    void Function(double progress, String message)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();

    final prefix = type == BackupType.full
        ? 'dabirkhane-full'
        : 'dabirkhane-files';

    final zipPath = path.join(
      tempDir.path,
      '${prefix}_${year}_'
      '${month.toString().padLeft(2, '0')}.zip',
    );

    final zipFile = File(zipPath);

    if (await zipFile.exists()) {
      await zipFile.delete();
    }

    final archive = Archive();

    final manifest = <String, dynamic>{
      'format': 'dabirkhane_backup',
      'version': _backupVersion,
      'type': type == BackupType.full ? 'full' : 'files',
      'created_at': DateTime.now().toIso8601String(),
      'jalali_year': year,
      'jalali_month': month,
      'files_count': files.length,
    };

    archive.addFile(
      ArchiveFile(
        _manifestFileName,
        utf8
            .encode(const JsonEncoder.withIndent('  ').convert(manifest))
            .length,
        utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
      ),
    );

    if (includeDatabase && databaseFile != null) {
      onProgress?.call(0.25, 'در حال افزودن دیتابیس به ZIP...');

      final dbBytes = await databaseFile.readAsBytes();

      archive.addFile(
        ArchiveFile('database/dabirkhane.sqlite', dbBytes.length, dbBytes),
      );
    }

    for (int i = 0; i < files.length; i++) {
      final file = files[i];

      final relativePath = path.relative(
        file.path,
        from: path.join(
          (await AppSettings.getLettersDirectory()).path,
          year.toString(),
          month.toString(),
        ),
      );

      final zipPathInside = path
          .join('files', year.toString(), month.toString(), relativePath)
          .replaceAll('\\', '/');

      final bytes = await file.readAsBytes();

      archive.addFile(ArchiveFile(zipPathInside, bytes.length, bytes));

      final progress = includeDatabase
          ? 0.30 + ((i + 1) / files.length.clamp(1, 999999)) * 0.45
          : 0.20 + ((i + 1) / files.length.clamp(1, 999999)) * 0.60;

      onProgress?.call(
        progress.clamp(0.0, 0.90),
        'در حال فشرده‌سازی فایل ${i + 1} از ${files.length}...',
      );
    }

    onProgress?.call(0.92, 'در حال ساخت فایل ZIP...');

    final encoded = ZipEncoder().encode(archive);

    if (encoded == null) {
      throw Exception('ساخت فایل ZIP با خطا مواجه شد.');
    }

    await zipFile.writeAsBytes(encoded, flush: true);

    onProgress?.call(0.96, 'فایل پشتیبان آماده شد.');

    return zipFile;
  }

  // ============================================================
  // Export ZIP
  // ============================================================

  static Future<BackupResult> _exportZipFile(
    File zipFile, {
    required String title,
  }) async {
    if (Platform.isAndroid) {
      try {
        await Share.shareXFiles(
          [XFile(zipFile.path, mimeType: 'application/zip')],
          subject: title,
          text: title,
        );

        if (await zipFile.exists()) {
          await zipFile.delete();
        }

        return BackupResult(
          success: true,
          message: '$title آماده و برای اشتراک‌گذاری ارسال شد.',
        );
      } catch (e) {
        return BackupResult(
          success: false,
          message: 'خطا در اشتراک‌گذاری فایل ZIP:\n$e',
        );
      }
    }

    if (Platform.isWindows) {
      final suggestedName = path.basename(zipFile.path);

      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'ZIP Archive', extensions: ['zip']),
        ],
      );

      if (location == null) {
        return const BackupResult(success: false, message: 'عملیات لغو شد.');
      }

      final target = File(location.path);

      if (await target.exists()) {
        await target.delete();
      }

      await zipFile.copy(target.path);

      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      return BackupResult(
        success: true,
        path: target.path,
        message: '$title با موفقیت ذخیره شد.\n\n${target.path}',
      );
    }

    return const BackupResult(
      success: false,
      message: 'پشتیبان‌گیری در این پلتفرم پشتیبانی نمی‌شود.',
    );
  }

  // ============================================================
  // Restore Database
  // ============================================================

  static Future<RestoreResult> _restoreDatabase(
    File selectedFile, {
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.10, 'در حال بررسی دیتابیس...');

    final targetPath = await DatabaseHelper.getDbPath();

    final targetFile = File(targetPath);

    onProgress?.call(0.25, 'در حال بستن دیتابیس فعلی...');

    await DatabaseHelper.closeDb();

    try {
      if (await targetFile.exists()) {
        final backupPath = '$targetPath.backup';

        onProgress?.call(0.35, 'در حال تهیه نسخه پشتیبان از دیتابیس فعلی...');

        final oldBackup = File(backupPath);

        if (await oldBackup.exists()) {
          await oldBackup.delete();
        }

        await targetFile.copy(backupPath);
        await targetFile.delete();
      }

      onProgress?.call(0.65, 'در حال جایگزینی دیتابیس...');

      await selectedFile.copy(targetPath);

      onProgress?.call(0.85, 'در حال باز کردن دیتابیس جدید...');

      await DatabaseHelper.database;

      onProgress?.call(1, 'بازیابی انجام شد.');

      return const RestoreResult(
        success: true,
        databaseRestored: true,
        message: 'دیتابیس با موفقیت بازیابی شد.',
      );
    } catch (e) {
      // اگر جایگزینی شکست خورد، تلاش می‌کنیم
      // نسخه backup قبلی را برگردانیم.
      try {
        final backupFile = File('$targetPath.backup');

        if (await backupFile.exists()) {
          if (await targetFile.exists()) {
            await targetFile.delete();
          }

          await backupFile.copy(targetPath);
          await DatabaseHelper.database;
        }
      } catch (_) {}

      return RestoreResult(
        success: false,
        message: 'بازیابی دیتابیس انجام نشد.\n\n$e',
      );
    }
  }

  // ============================================================
  // Restore ZIP
  // ============================================================

  static Future<RestoreResult> _restoreZip(
    File zipFile, {
    void Function(double progress, String message)? onProgress,
  }) async {
    onProgress?.call(0.05, 'در حال بررسی فایل پشتیبان...');

    final info = await inspectBackup(zipFile);

    if (info.type == BackupContentType.unknown) {
      return const RestoreResult(
        success: false,
        message:
            'ساختار فایل ZIP قابل تشخیص نیست.\n'
            'این فایل احتمالاً پشتیبان دبیرخانه نیست.',
      );
    }

    final bytes = await zipFile.readAsBytes();

    onProgress?.call(0.15, 'در حال باز کردن فایل پشتیبان...');

    final archive = ZipDecoder().decodeBytes(bytes);

    bool databaseRestored = false;
    bool filesRestored = false;

    final databaseEntry = _findArchiveFile(
      archive,
      'database/dabirkhane.sqlite',
    );

    if (databaseEntry != null &&
        (info.type == BackupContentType.database ||
            info.type == BackupContentType.full)) {
      onProgress?.call(0.30, 'در حال بازیابی دیتابیس...');

      final tempDir = await getTemporaryDirectory();

      final extractedDb = File(
        path.join(tempDir.path, 'dabirkhane_restore.sqlite'),
      );

      if (await extractedDb.exists()) {
        await extractedDb.delete();
      }

      await extractedDb.writeAsBytes(
        databaseEntry.content as List<int>,
        flush: true,
      );

      final result = await _restoreDatabase(
        extractedDb,
        onProgress: (progress, message) {
          onProgress?.call(0.30 + progress * 0.30, message);
        },
      );

      if (!result.success) {
        return result;
      }

      databaseRestored = true;

      if (await extractedDb.exists()) {
        await extractedDb.delete();
      }
    }

    if (info.type == BackupContentType.files ||
        info.type == BackupContentType.full) {
      onProgress?.call(0.65, 'در حال بازیابی فایل‌های نامه‌ها...');

      final restoredCount = await _restoreFilesFromArchive(
        archive,
        onProgress: (progress, message) {
          onProgress?.call(0.65 + progress * 0.30, message);
        },
      );

      filesRestored = restoredCount > 0;
    }

    onProgress?.call(1, 'بازیابی کامل شد.');

    if (databaseRestored && filesRestored) {
      return const RestoreResult(
        success: true,
        databaseRestored: true,
        filesRestored: true,
        message: 'دیتابیس و فایل‌های نامه‌ها با موفقیت بازیابی شدند.',
      );
    }

    if (databaseRestored) {
      return const RestoreResult(
        success: true,
        databaseRestored: true,
        message: 'دیتابیس با موفقیت بازیابی شد.',
      );
    }

    if (filesRestored) {
      return const RestoreResult(
        success: true,
        filesRestored: true,
        message: 'فایل‌های نامه‌ها با موفقیت بازیابی شدند.',
      );
    }

    return const RestoreResult(
      success: true,
      message: 'فایل پشتیبان بررسی شد، اما فایل قابل بازیابی پیدا نشد.',
    );
  }

  // ============================================================
  // Restore Files
  // ============================================================

  static Future<int> _restoreFilesFromArchive(
    Archive archive, {
    void Function(double progress, String message)? onProgress,
  }) async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    final fileEntries = archive
        .where(
          (entry) =>
              entry.isFile &&
              entry.name.replaceAll('\\', '/').startsWith('files/'),
        )
        .toList();

    if (fileEntries.isEmpty) {
      return 0;
    }

    int restored = 0;

    for (int i = 0; i < fileEntries.length; i++) {
      final entry = fileEntries[i];

      final normalized = entry.name.replaceAll('\\', '/');

      final relative = normalized.substring('files/'.length);

      if (relative.isEmpty) {
        continue;
      }

      // جلوگیری از Path Traversal
      if (relative.contains('../') ||
          relative.startsWith('../') ||
          path.isAbsolute(relative)) {
        continue;
      }

      final targetPath = path.join(lettersDir.path, relative);

      final normalizedTarget = path.normalize(targetPath);

      final normalizedRoot = path.normalize(lettersDir.path);

      if (!normalizedTarget.startsWith(normalizedRoot)) {
        continue;
      }

      File targetFile = File(normalizedTarget);

      await targetFile.parent.create(recursive: true);

      // جلوگیری از overwrite فایل فعلی
      if (await targetFile.exists()) {
        targetFile = await _findAvailableFile(targetFile);
      }

      await targetFile.writeAsBytes(entry.content as List<int>, flush: true);

      restored++;

      onProgress?.call(
        (i + 1) / fileEntries.length,
        'بازیابی فایل ${i + 1} از ${fileEntries.length}...',
      );
    }

    return restored;
  }

  // ============================================================
  // Helpers
  // ============================================================

  static Future<File> _findAvailableFile(File target) async {
    final directory = target.parent.path;

    final extension = path.extension(target.path);

    final baseName = path.basenameWithoutExtension(target.path);

    int index = 1;

    File candidate = target;

    while (await candidate.exists()) {
      candidate = File(
        path.join(directory, '${baseName}_restore_$index$extension'),
      );

      index++;
    }

    return candidate;
  }

  static ArchiveFile? _findArchiveFile(Archive archive, String target) {
    final normalizedTarget = target.replaceAll('\\', '/');

    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');

      if (name == normalizedTarget) {
        return entry;
      }
    }

    return null;
  }

  static String _databaseBackupFileName() {
    final now = Jalali.now();

    return 'dabirkhane_database_'
        '${now.year}_'
        '${now.month.toString().padLeft(2, '0')}_'
        '${now.day.toString().padLeft(2, '0')}.sqlite';
  }

  static _JalaliMonth _getPreviousJalaliMonth() {
    final now = Jalali.now();

    if (now.month == 1) {
      return _JalaliMonth(year: now.year - 1, month: 12);
    }

    return _JalaliMonth(year: now.year, month: now.month - 1);
  }

  static String _monthDescription(String title, int? year, int? month) {
    if (year == null || month == null) {
      return title;
    }

    return '$title — $year/$month';
  }

  static int? _toInt(dynamic value) {
    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }
}

class _JalaliMonth {
  final int year;
  final int month;

  const _JalaliMonth({required this.year, required this.month});
}
