import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

class AppSettings {
  static const _lettersPathKey = 'letters_path';

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
