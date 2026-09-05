import 'dart:io';

import 'package:path/path.dart' as path;

import '../db/database_helper.dart';
import 'app_settings.dart';

class LetterFileOrganizer {
  LetterFileOrganizer._();

  /// تبدیل اعداد فارسی و عربی به انگلیسی
  static String normalizeNumbers(String input) {
    const persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    const arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    for (int i = 0; i < 10; i++) {
      input = input.replaceAll(persianDigits[i], i.toString());
      input = input.replaceAll(arabicDigits[i], i.toString());
    }

    return input;
  }

  /// استخراج سال و ماه از تاریخ شمسی
  ///
  /// مثال:
  /// 1405/01/25 -> [1405, 1]
  /// ۱۴۰۵/۰۱/۲۵ -> [1405, 1]
  static List<int>? parseJalaliDate(String value) {
    final normalized = normalizeNumbers(value.trim());

    final match = RegExp(
      r'^(\d{4})[\/\-](\d{1,2})[\/\-](\d{1,2})$',
    ).firstMatch(normalized);

    if (match == null) {
      return null;
    }

    final year = int.tryParse(match.group(1)!);
    final month = int.tryParse(match.group(2)!);

    if (year == null || month == null) {
      return null;
    }

    if (month < 1 || month > 12) {
      return null;
    }

    return [year, month];
  }

  /// مسیر مقصد فایل بر اساس تاریخ
  static Future<Directory?> getDirectoryForDate(String date) async {
    final parsed = parseJalaliDate(date);

    if (parsed == null) {
      return null;
    }

    final year = parsed[0];
    final month = parsed[1];

    final lettersDir = await AppSettings.getLettersDirectory();

    final yearDir = Directory(path.join(lettersDir.path, year.toString()));

    final monthDir = Directory(path.join(yearDir.path, month.toString()));

    if (!await monthDir.exists()) {
      await monthDir.create(recursive: true);
    }

    return monthDir;
  }

  /// انتقال یک فایل به پوشه مربوط به تاریخ
  static Future<File?> moveFileToDate({
    required File file,
    required String date,
    String? targetName,
  }) async {
    if (!await file.exists()) {
      return null;
    }

    final targetDirectory = await getDirectoryForDate(date);

    if (targetDirectory == null) {
      return null;
    }

    final fileName = targetName ?? path.basename(file.path);

    File targetFile = File(path.join(targetDirectory.path, fileName));

    // اگر فایل در همان مسیر مقصد است
    if (path.normalize(file.path) == path.normalize(targetFile.path)) {
      return targetFile;
    }

    // جلوگیری از overwrite
    if (await targetFile.exists()) {
      final extension = path.extension(fileName);
      final baseName = path.basenameWithoutExtension(fileName);

      int index = 1;

      while (await targetFile.exists()) {
        targetFile = File(
          path.join(targetDirectory.path, '${baseName}_$index$extension'),
        );

        index++;
      }
    }

    await file.rename(targetFile.path);

    return targetFile;
  }

  /// مرتب‌سازی تمام فایل‌های موجود در پوشه نامه‌ها
  ///
  /// نام فایل باید با شماره ثبت شروع شود:
  ///
  /// 125.pdf
  /// 125_1.pdf
  /// 125_2.jpg
  ///
  /// سپس شماره ثبت از دیتابیس خوانده شده و تاریخ آن مشخص می‌شود.
  static Future<OrganizeResult> organizeAll() async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    int moved = 0;
    int skipped = 0;
    int errors = 0;

    final List<String> errorMessages = [];

    final List<File> files = [];

    await for (final entity in lettersDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        files.add(entity);
      }
    }

    for (final file in files) {
      try {
        final fileName = path.basenameWithoutExtension(file.path);

        // مثال:
        // 125
        // 125_1
        // 125_2
        //
        // شماره نامه همان قسمت اول است.
        final match = RegExp(r'^(\d+)').firstMatch(fileName);

        if (match == null) {
          skipped++;
          continue;
        }

        final recordId = int.tryParse(match.group(1)!);

        if (recordId == null) {
          skipped++;
          continue;
        }

        final record = await DatabaseHelper.getById(recordId);

        // نامه‌ای با این شماره در دیتابیس وجود ندارد
        if (record == null) {
          skipped++;
          continue;
        }

        final date = record['date']?.toString() ?? '';

        final parsedDate = parseJalaliDate(date);

        if (parsedDate == null) {
          skipped++;
          continue;
        }

        final year = parsedDate[0];
        final month = parsedDate[1];

        final lettersPath = lettersDir.path;

        final targetDirectory = Directory(
          path.join(lettersPath, year.toString(), month.toString()),
        );

        if (!await targetDirectory.exists()) {
          await targetDirectory.create(recursive: true);
        }

        final targetPath = path.join(
          targetDirectory.path,
          path.basename(file.path),
        );

        // اگر همین الان در مقصد قرار دارد
        if (path.normalize(file.path) == path.normalize(targetPath)) {
          skipped++;
          continue;
        }

        File finalTarget = File(targetPath);

        // جلوگیری از overwrite
        if (await finalTarget.exists()) {
          final extension = path.extension(file.path);
          final baseName = path.basenameWithoutExtension(file.path);

          int index = 1;

          while (await finalTarget.exists()) {
            finalTarget = File(
              path.join(targetDirectory.path, '${baseName}_$index$extension'),
            );

            index++;
          }
        }

        await file.rename(finalTarget.path);

        moved++;
      } catch (e) {
        errors++;

        errorMessages.add('${path.basename(file.path)}: $e');
      }
    }

    return OrganizeResult(
      moved: moved,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}

class OrganizeResult {
  final int moved;
  final int skipped;
  final int errors;
  final List<String> errorMessages;

  const OrganizeResult({
    required this.moved,
    required this.skipped,
    required this.errors,
    required this.errorMessages,
  });
}
