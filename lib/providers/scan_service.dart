import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
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

  static final StreamController<ScanResult> _resultController =
      StreamController<ScanResult>.broadcast();

  static Stream<ScanResult> get results => _resultController.stream;

  static const MethodChannel _channel = MethodChannel('dabirkhane/scanner');

  static const String _fastScannerPackage = 'ir.haghshenas.fastscanner';

  static const String _fastScannerAction =
      'ir.haghshenas.fastscanner.action.SCAN';

  static const String _scanResultAction =
      'ir.haghshenas.dabirkhane.action.SCAN_RESULT';

  static String? _recordId;

  static bool _waitingForFastScanner = false;

  static Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'scanResult') {
        return;
      }

      final arguments = Map<dynamic, dynamic>.from(call.arguments as Map);

      final success = arguments['success'] == true;

      final cancelled = arguments['cancelled'] == true;

      final recordId = arguments['record_id']?.toString();

      final filePath = arguments['file_path']?.toString();

      final mimeType = arguments['mime_type']?.toString();

      final result = ScanResult(
        success: success,
        cancelled: cancelled,
        recordId: recordId,
        filePath: filePath,
        mimeType: mimeType,
      );

      await _handleScanResult(result);
    });
  }

  static Future<void> _handleScanResult(ScanResult result) async {
    _waitingForFastScanner = false;
    _resultController.add(result);

    if (!result.success) {
      cancel();
      return;
    }

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
      // خطا را ذخیره نمی‌کنیم؛
      // RecordForm در صورت نیاز می‌تواند وضعیت را بررسی کند.

      print('FastScanner result error: $e');
    }
  }

  static Future<void> _copyFastScannerResult({
    required String recordId,
    required String sourcePath,
    String? mimeType,
  }) async {
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) {
      throw Exception('فایل اسکن شده پیدا نشد:\n$sourcePath');
    }

    final size = await sourceFile.length();

    if (size <= 0) {
      throw Exception('فایل اسکن شده خالی است.');
    }

    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    String extension = path.extension(sourcePath).toLowerCase();

    if (extension.isEmpty) {
      if (mimeType == 'application/pdf') {
        extension = '.pdf';
      } else {
        extension = '.jpg';
      }
    }

    final targetPath = path.join(lettersDir.path, '$recordId$extension');

    final targetFile = File(targetPath);

    await targetFile.writeAsBytes(await sourceFile.readAsBytes(), flush: true);

    final copiedSize = await targetFile.length();

    if (copiedSize != size) {
      throw Exception('کپی فایل ناقص انجام شد.');
    }

    // پاک کردن فایل موقت FastScanner
    try {
      await sourceFile.delete();
    } catch (_) {}

    _recordId = null;
  }

  //------------------------------------------------------------
  // شروع اسکن
  //------------------------------------------------------------

  static Future<void> startScan(String recordId) async {
    _recordId = recordId;

    final scannerType = await AppSettings.getScannerType();

    if (scannerType == AppSettings.scannerFastScanner) {
      await _startFastScanner(recordId);

      return;
    }

    // ==========================================================
    // CamScanner
    // ==========================================================

    final readWithoutGallerySave =
        await AppSettings.getReadWithoutGallerySave();

    AndroidIntent intent;

    if (readWithoutGallerySave) {
      intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.intsig.camscanner',
        componentName: 'com.intsig.camscanner.capture.CaptureActivity',
      );
    } else {
      intent = const AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.intsig.camscanner',
        componentName:
            'com.intsig.camscanner.mainmenu.mainactivity.MainActivity',
      );
    }

    await intent.launch();
  }

  static Future<void> dispose() async {
    await _resultController.close();
  }

  //------------------------------------------------------------
  // باز کردن FastScanner
  //------------------------------------------------------------

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

  //------------------------------------------------------------
  // آیا FastScanner باز است؟
  //------------------------------------------------------------

  static bool get isWaitingForScan {
    return _waitingForFastScanner && _recordId != null;
  }

  //------------------------------------------------------------
  // شماره نامه
  //------------------------------------------------------------

  static String? get currentRecordId {
    return _recordId;
  }

  //------------------------------------------------------------
  // لغو
  //------------------------------------------------------------

  static void cancel() {
    _recordId = null;
    _waitingForFastScanner = false;
  }

  //------------------------------------------------------------
  // پاک کردن فایل های قبلی نامه
  //------------------------------------------------------------

  static Future<void> deleteOldScans(int recordId) async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      return;
    }

    await for (final entity in lettersDir.list()) {
      if (entity is! File) {
        continue;
      }

      final name = path.basenameWithoutExtension(entity.path);

      if (name == recordId.toString() || name.startsWith('${recordId}_')) {
        await entity.delete();
      }
    }
  }
}
