import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  static const _lettersPathKey = 'letters_path';
  static const _camScannerPath1Key = 'camscanner_path_1';
  static const _camScannerPath2Key = 'camscanner_path_2';
  static const _readWithoutGallerySaveKey = 'read_without_gallery_save';

  static const String _scannerTypeKey = 'scanner_type';

  static const String scannerCamScanner = 'camscanner';
static const String scannerFastScanner = 'fastscanner';

static Future<String> getScannerType() async {
  final prefs = await SharedPreferences.getInstance();

  return prefs.getString(_scannerTypeKey) ?? scannerCamScanner;
}

static Future<void> setScannerType(String value) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setString(_scannerTypeKey, value);
}

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

  static Future<String> getCamScannerPath2() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_camScannerPath2Key) ?? defaultCamScannerPath2;
  }

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

    // مسیر پیش‌فرض
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

  /// گرفتن مسیر ذخیره‌شده (برای نمایش)
  static Future<String?> getSavedLettersPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lettersPathKey);
  }
}
