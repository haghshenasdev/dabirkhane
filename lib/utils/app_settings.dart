import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  static const _lettersPathKey = 'letters_path';
  static const _camScannerPath1Key = 'camscanner_path_1';
  static const _camScannerPath2Key = 'camscanner_path_2';
  static const _readWithoutGallerySaveKey = 'read_without_gallery_save';
  static const _autoSaveRecordFormKey = 'auto_save_record_form';

  static const String _scannerTypeKey = 'scanner_type';

  static const String scannerCamScanner = 'camscanner';
  static const String scannerFastScanner = 'fastscanner';

  // ============================================================
  // Backup / Restore history
  // ============================================================

  static const _lastBackupAtKey = 'last_backup_at';
  static const _lastBackupTypeKey = 'last_backup_type';
  static const _lastBackupItemsKey = 'last_backup_items';

  static const _lastRestoreAtKey = 'last_restore_at';
  static const _lastRestoreTypeKey = 'last_restore_type';
  static const _lastRestoreItemsKey = 'last_restore_items';

  // ============================================================
  // Monthly Backup Reminder
  // ============================================================

  static const _monthlyBackupReminderEnabledKey =
      'monthly_backup_reminder_enabled';

  static const _monthlyBackupReminderLastShownKey =
      'monthly_backup_reminder_last_shown';

  static Future<bool> getMonthlyBackupReminderEnabled() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_monthlyBackupReminderEnabledKey) ?? true;
  }

  static Future<void> setMonthlyBackupReminderEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_monthlyBackupReminderEnabledKey, value);
  }

  static Future<String?> getMonthlyBackupReminderLastShown() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_monthlyBackupReminderLastShownKey);
  }

  static Future<void> setMonthlyBackupReminderLastShown(String monthKey) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_monthlyBackupReminderLastShownKey, monthKey);
  }

  // -----------------------------
  // Last Backup
  // -----------------------------

  static Future<void> saveLastBackup({
    required String type,
    required List<String> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastBackupAtKey, DateTime.now().toIso8601String());

    await prefs.setString(_lastBackupTypeKey, type);

    await prefs.setStringList(_lastBackupItemsKey, items);
  }

  static Future<DateTime?> getLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_lastBackupAtKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static Future<String?> getLastBackupType() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_lastBackupTypeKey);
  }

  static Future<List<String>> getLastBackupItems() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getStringList(_lastBackupItemsKey) ?? <String>[];
  }

  // -----------------------------
  // Last Restore
  // -----------------------------

  static Future<void> saveLastRestore({
    required String type,
    required List<String> items,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lastRestoreAtKey, DateTime.now().toIso8601String());

    await prefs.setString(_lastRestoreTypeKey, type);

    await prefs.setStringList(_lastRestoreItemsKey, items);
  }

  static Future<DateTime?> getLastRestoreAt() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getString(_lastRestoreAtKey);

    if (value == null || value.isEmpty) {
      return null;
    }

    return DateTime.tryParse(value);
  }

  static Future<String?> getLastRestoreType() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_lastRestoreTypeKey);
  }

  static Future<List<String>> getLastRestoreItems() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getStringList(_lastRestoreItemsKey) ?? <String>[];
  }

  // ============================================================
  // Scanner
  // ============================================================

  static Future<String> getScannerType() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_scannerTypeKey) ?? scannerCamScanner;
  }

  static Future<void> setScannerType(String value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_scannerTypeKey, value);
  }

  // ============================================================
  // Suggestions
  // ============================================================

  static const String _suggestionsSahebNameKey = 'form_suggestions_saheb_name';

  static const String _suggestionsGuyKey = 'form_suggestions_guy';

  static const String _suggestionsOnvanKey = 'form_suggestions_onvan';

  static const String _suggestionsCategoryKey = 'form_suggestions_category';

  static const String _saveAndReturnAfterScanKey = 'save_and_return_after_scan';

  static Future<bool> getSaveAndReturnAfterScan() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_saveAndReturnAfterScanKey) ?? false;
  }

  static Future<void> setSaveAndReturnAfterScan(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_saveAndReturnAfterScanKey, value);
  }

  static Future<bool> getAutoSaveRecordForm() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_autoSaveRecordFormKey) ?? false;
  }

  static Future<void> setAutoSaveRecordForm(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_autoSaveRecordFormKey, value);
  }

  static Future<bool> getFormSuggestionsEnabled(String field) async {
    final prefs = await SharedPreferences.getInstance();

    switch (field) {
      case 'saheb_name':
        return prefs.getBool(_suggestionsSahebNameKey) ?? true;

      case 'guy':
        return prefs.getBool(_suggestionsGuyKey) ?? true;

      case 'onvan':
        return prefs.getBool(_suggestionsOnvanKey) ?? true;

      case 'category':
        return prefs.getBool(_suggestionsCategoryKey) ?? true;

      default:
        return true;
    }
  }

  static Future<void> setFormSuggestionsEnabled(
    String field,
    bool value,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    switch (field) {
      case 'saheb_name':
        await prefs.setBool(_suggestionsSahebNameKey, value);
        break;

      case 'guy':
        await prefs.setBool(_suggestionsGuyKey, value);
        break;

      case 'onvan':
        await prefs.setBool(_suggestionsOnvanKey, value);
        break;

      case 'category':
        await prefs.setBool(_suggestionsCategoryKey, value);
        break;
    }
  }

  // ============================================================
  // CamScanner
  // ============================================================

  static const String defaultCamScannerPath1 =
      "/storage/emulated/0/DCIM/CamScanner";

  static const String defaultCamScannerPath2 =
      "/storage/emulated/0/Download/CamScanner";

  static const String camScannerPrivateImagePath =
      "/storage/emulated/0/Android/data/com.intsig.camscanner/files/CamScanner/.images";

  static Future<List<Directory>> getCamScannerDirectories() async {
    final prefs = await SharedPreferences.getInstance();

    final path1 =
        prefs.getString(_camScannerPath1Key) ?? defaultCamScannerPath1;

    final path2 =
        prefs.getString(_camScannerPath2Key) ?? defaultCamScannerPath2;

    return [Directory(path1), Directory(path2)];
  }

  static Future<void> setCamScannerDirectories({
    required String path1,
    required String path2,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_camScannerPath1Key, path1);

    await prefs.setString(_camScannerPath2Key, path2);
  }

  static Future<String> getCamScannerPath1() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_camScannerPath1Key) ?? defaultCamScannerPath1;
  }

  static Future<String> getCamScannerPath2() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_camScannerPath2Key) ?? defaultCamScannerPath2;
  }

  // ============================================================
  // Read without gallery
  // ============================================================

  static Future<bool> getReadWithoutGallerySave() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool(_readWithoutGallerySaveKey) ?? true;
  }

  static Future<void> setReadWithoutGallerySave(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_readWithoutGallerySaveKey, value);
  }

  static Future<void> toggleReadWithoutGallerySave() async {
    final current = await getReadWithoutGallerySave();

    await setReadWithoutGallerySave(!current);
  }

  // ============================================================
  // Letters directory
  // ============================================================

  /// گرفتن مسیر پوشه نامه‌ها
  static Future<Directory> getLettersDirectory() async {
    final prefs = await SharedPreferences.getInstance();

    final savedPath = prefs.getString(_lettersPathKey);

    if (savedPath != null && savedPath.isNotEmpty) {
      final dir = Directory(savedPath);

      if (await dir.exists()) {
        return dir;
      }
    }

    final appDir = await getApplicationDocumentsDirectory();

    final defaultDir = Directory('${appDir.path}/letters');

    if (!await defaultDir.exists()) {
      await defaultDir.create(recursive: true);
    }

    return defaultDir;
  }

  /// ذخیره مسیر جدید
  static Future<void> setLettersDirectory(String path) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_lettersPathKey, path);
  }

  /// گرفتن مسیر ذخیره‌شده
  static Future<String?> getSavedLettersPath() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getString(_lettersPathKey);
  }
}
