import 'dart:async';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

import '../utils/app_settings.dart';

class ScanService {
  ScanService._();
  static DateTime? _scanStartTime;
  static int? _recordId;

  //------------------------------------------------------------
  // شروع فرآیند اسکن
  //------------------------------------------------------------

  static Future<void> startScan(int recordId) async {
    _recordId = recordId;
    _scanStartTime = DateTime.now();

    // شماره نامه داخل کلیپ برد
    await Clipboard.setData(ClipboardData(text: recordId.toString()));

    // باز کردن CamScanner
    const intent = AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.intsig.camscanner',
      componentName: 'com.intsig.camscanner.CaptureIntentActivity',
    );
    // com.intsig.camscanner.mainmenu.mainactivity.MainActivity
    await intent.launch();
  }

  //------------------------------------------------------------
  // هنگام برگشت از CamScanner
  //------------------------------------------------------------

  static Future<bool> processReturnedScan() async {
    if (_recordId == null || _scanStartTime == null) {
      return false;
    }

    final file = await _findLatestScannedFile();

    if (file == null) {
      return false;
    }

    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    final extension = path.extension(file.path);

    // پیدا کردن اولین نام آزاد
    String targetName = '$_recordId$extension';
    File targetFile = File(path.join(lettersDir.path, targetName));

    int index = 1;
    while (await targetFile.exists()) {
      targetName = '${_recordId}_$index$extension';
      targetFile = File(path.join(lettersDir.path, targetName));
      index++;
    }

    await file.copy(targetFile.path);

    _recordId = null;
    _scanStartTime = null;

    return true;
  }

  //------------------------------------------------------------
  // پیدا کردن فایل جدید CamScanner
  //------------------------------------------------------------

  static Future<File?> _findLatestScannedFile() async {
    final directories = await AppSettings.getCamScannerDirectories();

    final files = <File>[];

    for (final dir in directories) {
      if (!await dir.exists()) continue;

      await for (final entity in dir.list()) {
        if (entity is! File) continue;

        final ext = path.extension(entity.path).toLowerCase();

        if (ext == ".pdf" || ext == ".jpg" || ext == ".jpeg" || ext == ".png") {
          files.add(entity);
        }
      }
    }

    if (files.isEmpty) {
      return null;
    }

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final newest = files.first;

    // اگر فایل قدیمی‌تر از شروع اسکن است
    if (newest.lastModifiedSync().isBefore(_scanStartTime!)) {
      return null;
    }

    // اگر بیش از 10 دقیقه از شروع اسکن گذشته باشد
    if (DateTime.now().difference(_scanStartTime!).inMinutes > 10) {
      return null;
    }

    return newest;
  }
  //------------------------------------------------------------
  // آیا فرآیند اسکن در حال انجام است؟
  //------------------------------------------------------------

  static bool get isWaitingForScan {
    return _recordId != null && _scanStartTime != null;
  }

  //------------------------------------------------------------
  // شماره نامه فعلی
  //------------------------------------------------------------

  static int? get currentRecordId => _recordId;

  //------------------------------------------------------------
  // زمان شروع اسکن
  //------------------------------------------------------------

  static DateTime? get scanStartTime => _scanStartTime;

  //------------------------------------------------------------
  // لغو عملیات اسکن
  //------------------------------------------------------------

  static void cancel() {
    _recordId = null;
    _scanStartTime = null;
  }

  //------------------------------------------------------------
  // پاک کردن فایل قدیمی هم نام (اختیاری)
  //------------------------------------------------------------

  static Future<void> deleteOldScans(int recordId) async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      return;
    }

    await for (final entity in lettersDir.list()) {
      if (entity is! File) continue;

      final name = path.basenameWithoutExtension(entity.path);

      if (name == recordId.toString()) {
        await entity.delete();
      }
    }
  }
}
