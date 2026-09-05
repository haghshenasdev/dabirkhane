import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:dabirkhane/utils/letter_file_organizer.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../utils/app_settings.dart';

class ScanResult {
  final bool success;
  final bool cancelled;
  final String? recordId;
  final String? filePath;
  final String? mimeType;

  const ScanResult({
    required this.success,
    required this.cancelled,
    this.recordId,
    this.filePath,
    this.mimeType,
  });
}

class ScanService {
  ScanService._();

  // ============================================================
  // FastScanner
  // ============================================================

  static const MethodChannel _channel = MethodChannel('dabirkhane/scanner');

  static const String _fastScannerPackage = 'ir.haghshenas.fastscanner';

  static const String _fastScannerAction =
      'ir.haghshenas.fastscanner.action.SCAN';

  static const String _scanResultAction =
      'ir.haghshenas.dabirkhane.action.SCAN_RESULT';

  // ============================================================
  // وضعیت اسکن
  // ============================================================

  static DateTime? _scanStartTime;

  static String? _recordId;

  static bool _waitingForFastScanner = false;

  // ============================================================
  // نتیجه FastScanner
  // ============================================================

  static final StreamController<ScanResult> _resultController =
      StreamController<ScanResult>.broadcast();

  static Stream<ScanResult> get results => _resultController.stream;

  // ============================================================
  // initialize
  // ============================================================

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'scanResult') {
        return;
      }

      final arguments = Map<dynamic, dynamic>.from(call.arguments as Map);

      final result = ScanResult(
        success: arguments['success'] == true,
        cancelled: arguments['cancelled'] == true,
        recordId: arguments['record_id']?.toString(),
        filePath: arguments['file_path']?.toString(),
        mimeType: arguments['mime_type']?.toString(),
      );

      await _handleFastScannerResult(result);
    });
  }

  // ============================================================
  // شروع اسکن
  // ============================================================

  static String? _recordDate;

  static Future<void> startScan(String recordId, String? date) async {
    _recordId = recordId;
    _recordDate = date;
    _scanStartTime = DateTime.now();

    // شماره نامه داخل Clipboard
    await Clipboard.setData(ClipboardData(text: recordId));

    // ----------------------------------------------------------
    // تعیین نوع اسکنر از تنظیمات
    // ----------------------------------------------------------

    final scannerType = await AppSettings.getScannerType();

    // ==========================================================
    // FastScanner
    // ==========================================================

    if (scannerType == AppSettings.scannerFastScanner) {
      await _startFastScanner(recordId);
      return;
    }

    // ==========================================================
    // CamScanner
    // ==========================================================

    await _startCamScanner();
  }

  // ============================================================
  // باز کردن FastScanner
  // ============================================================

  static Future<void> _startFastScanner(String recordId) async {
    _waitingForFastScanner = true;

    final intent = AndroidIntent(
      action: _fastScannerAction,
      package: _fastScannerPackage,
      componentName: 'ir.haghshenas.fastscanner.MainActivity',
      arguments: {
        'record_id': recordId,
        'return_package': 'com.example.dabirkhane',
        'return_action': _scanResultAction,
      },
    );

    await intent.launch();
  }

  // ============================================================
  // باز کردن CamScanner
  // ============================================================

  static Future<void> _startCamScanner() async {
    _waitingForFastScanner = false;

    final readWithoutGallerySave =
        await AppSettings.getReadWithoutGallerySave();

    AndroidIntent intent;

    if (readWithoutGallerySave) {
      // ========================================================
      // حالت بدون ذخیره در گالری
      // ========================================================

      intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.intsig.camscanner',
        componentName: 'com.intsig.camscanner.capture.CaptureActivity',
      );
    } else {
      // ========================================================
      // حالت عادی CamScanner
      // ========================================================

      intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.intsig.camscanner',
        componentName:
            'com.intsig.camscanner.mainmenu.mainactivity.MainActivity',
      );
    }

    await intent.launch();
  }

  // ============================================================
  // نتیجه FastScanner
  // ============================================================

  static Future<void> _handleFastScannerResult(ScanResult result) async {
    _waitingForFastScanner = false;

    // ابتدا نتیجه را برای UI ارسال می‌کنیم
    _resultController.add(result);

    // ----------------------------------------------------------
    // لغو
    // ----------------------------------------------------------

    if (result.cancelled) {
      cancel();
      return;
    }

    // ----------------------------------------------------------
    // ناموفق
    // ----------------------------------------------------------

    if (!result.success) {
      cancel();
      return;
    }

    // ----------------------------------------------------------
    // اطلاعات ناقص
    // ----------------------------------------------------------

    if (result.recordId == null || result.filePath == null) {
      cancel();
      return;
    }

    try {
      await _copyFastScannerResult(
        recordId: result.recordId!,
        sourcePath: result.filePath!,
        mimeType: result.mimeType,
      );
    } catch (e) {
      print('FastScanner result error: $e');
    }
  }

  // ============================================================
  // انتقال فایل FastScanner به پوشه نامه‌ها
  // ============================================================

  static Future<void> _copyFastScannerResult({
    required String recordId,
    required String sourcePath,
    String? mimeType,
  }) async {
    final sourceFile = File(sourcePath);

    // ----------------------------------------------------------
    // بررسی وجود فایل
    // ----------------------------------------------------------

    if (!await sourceFile.exists()) {
      throw Exception('فایل اسکن شده پیدا نشد:\n$sourcePath');
    }

    // ----------------------------------------------------------
    // بررسی حجم
    // ----------------------------------------------------------

    final sourceSize = await sourceFile.length();

    if (sourceSize <= 0) {
      throw Exception('فایل اسکن شده خالی است.');
    }

    // ----------------------------------------------------------
    // پوشه نامه‌ها
    // ----------------------------------------------------------

    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    // ----------------------------------------------------------
    // تعیین پسوند
    // ----------------------------------------------------------

    var extension = path.extension(sourceFile.path).toLowerCase();

    if (extension.isEmpty) {
      if (mimeType == 'application/pdf') {
        extension = '.pdf';
      } else {
        extension = '.jpg';
      }
    }

    // ----------------------------------------------------------
    // نام فایل
    //
    // مثل CamScanner:
    //
    // 12345.jpg
    // 12345_1.jpg
    // 12345_2.jpg
    // 12345_3.jpg
    //
    // اگر فایل اصلی وجود داشته باشد، فایل قبلی حذف نمی‌شود.
    // اولین شماره آزاد انتخاب می‌شود.
    // ----------------------------------------------------------

    var targetName = '$recordId$extension';

    var targetFile = File(path.join(lettersDir.path, targetName));

    int counter = 1;

    while (await targetFile.exists()) {
      targetName = '${recordId}_$counter$extension';

      targetFile = File(path.join(lettersDir.path, targetName));

      counter++;
    }

    // ----------------------------------------------------------
    // کپی
    // ----------------------------------------------------------

    await targetFile.writeAsBytes(await sourceFile.readAsBytes(), flush: true);

    // ----------------------------------------------------------
    // بررسی کپی
    // ----------------------------------------------------------

    final targetSize = await targetFile.length();

    if (targetSize != sourceSize) {
      throw Exception('کپی فایل ناقص انجام شد.');
    }

    // ----------------------------------------------------------
    // حذف فایل موقت
    // ----------------------------------------------------------

    try {
      await sourceFile.delete();
    } catch (_) {}

    // ----------------------------------------------------------
    // پایان
    // ----------------------------------------------------------

    _recordId = null;
    _scanStartTime = null;
  }

  // ============================================================
  // مکانیزم قبلی CamScanner
  // ============================================================

  static Future<bool> processReturnedScan() async {
    // این قسمت فقط برای CamScanner است
    if (_recordId == null || _scanStartTime == null) {
      return false;
    }

    final files = await _findScannedFiles();

    if (files.isEmpty) {
      return false;
    }

    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    final targetDirectory = await LetterFileOrganizer.getDirectoryForDate(
      _recordDate ?? '',
    );

    if (targetDirectory == null) {
      return false;
    }

    int counter = 0;

    for (final file in files) {
      final extension = path.extension(file.path);

      String targetName;

      if (counter == 0) {
        targetName = '$_recordId$extension';
      } else {
        targetName = '${_recordId}_$counter$extension';
      }

      File targetFile = File(path.join(targetDirectory.path, targetName));

      int index = counter;

      while (await targetFile.exists()) {
        index++;

        targetName = '${_recordId}_$index$extension';

        targetFile = File(path.join(lettersDir.path, targetName));
      }

      await file.copy(targetFile.path);

      counter++;
    }

    // ----------------------------------------------------------
    // پایان CamScanner
    // ----------------------------------------------------------

    _recordId = null;
    _recordDate = null;
    _scanStartTime = null;

    return true;
  }

  // ============================================================
  // پیدا کردن فایل‌های جدید CamScanner
  // ============================================================

  static Future<List<File>> _findScannedFiles() async {
    final readWithoutGallerySave =
        await AppSettings.getReadWithoutGallerySave();

    final directories = <Directory>[];

    // ----------------------------------------------------------
    // مسیر بر اساس تنظیمات قبلی
    // ----------------------------------------------------------

    if (readWithoutGallerySave) {
      directories.add(Directory(AppSettings.camScannerPrivateImagePath));
    } else {
      directories.addAll(await AppSettings.getCamScannerDirectories());
    }

    // ----------------------------------------------------------
    // پیدا کردن فایل‌ها
    // ----------------------------------------------------------

    final files = <File>[];

    for (final dir in directories) {
      if (!await dir.exists()) {
        continue;
      }

      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }

        final ext = path.extension(entity.path).toLowerCase();

        if (ext != '.jpg' && ext != '.jpeg' && ext != '.png' && ext != '.pdf') {
          continue;
        }

        final modified = await entity.lastModified();

        if (modified.isAfter(_scanStartTime!)) {
          files.add(entity);
        }
      }
    }

    // ----------------------------------------------------------
    // چیزی پیدا نشد
    // ----------------------------------------------------------

    if (files.isEmpty) {
      return [];
    }

    // ----------------------------------------------------------
    // مرتب‌سازی
    // ----------------------------------------------------------

    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));

    // ----------------------------------------------------------
    // گروه‌بندی فایل‌های همین اسکن
    // ----------------------------------------------------------

    final latestTime = await files.last.lastModified();

    final result = <File>[];

    for (final file in files) {
      final time = await file.lastModified();

      final difference = latestTime.difference(time).inSeconds;

      if (difference <= 30) {
        result.add(file);
      }
    }

    // ----------------------------------------------------------
    // حداکثر ۱۰ دقیقه
    // ----------------------------------------------------------

    if (DateTime.now().difference(_scanStartTime!).inMinutes > 10) {
      return [];
    }

    return result;
  }

  // ============================================================
  // وضعیت انتظار
  // ============================================================

  static bool get isWaitingForScan {
    return _recordId != null && _scanStartTime != null;
  }

  // ============================================================
  // آیا FastScanner است؟
  // ============================================================

  static bool get isWaitingForFastScanner {
    return _waitingForFastScanner && _recordId != null;
  }

  // ============================================================
  // شماره نامه
  // ============================================================

  static String? get currentRecordId {
    return _recordId;
  }

  // ============================================================
  // زمان شروع
  // ============================================================

  static DateTime? get scanStartTime {
    return _scanStartTime;
  }

  // ============================================================
  // لغو
  // ============================================================

  static void cancel() {
    _recordId = null;
    _recordDate = null;
    _scanStartTime = null;
    _waitingForFastScanner = false;
  }

  // ============================================================
  // حذف اسکن قبلی نامه
  // ============================================================

  static Future<void> deleteOldScans(int recordId) async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      return;
    }

    await for (final entity in lettersDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      final name = path.basenameWithoutExtension(entity.path);

      if (name == recordId.toString() || name.startsWith('${recordId}_')) {
        await entity.delete();
      }
    }
  }

  // ============================================================
  // dispose
  // ============================================================

  static Future<void> dispose() async {
    await _resultController.close();
  }
}
