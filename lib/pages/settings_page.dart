import 'dart:io';
import 'package:dabirkhane/db/database_helper.dart';

import '../providers/theme_provider.dart';
import '../utils/LettersPathTile.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/wid/ThemeColorTile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<void> restoreDbBackup(BuildContext context) async {
    try {
      // 1️⃣ مسیر دیتابیس اصلی و فایل بکاپ
      final String targetPath = await DatabaseHelper.getDbPath();
      final File targetFile = File(targetPath);
      final String backupPath = '$targetPath.backup';
      final File backupFile = File(backupPath);

      // 2️⃣ بررسی اینکه آیا فایل بکاپ وجود دارد یا نه
      if (!await backupFile.exists()) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('خطا'),
            content: Text('هیچ بکاپی برای بازیابی وجود ندارد.'),
            actions: [
              TextButton(
                child: Text('باشه'),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
        return;
      }

      // 3️⃣ نمایش پیام تایید برای بازیابی (آیا مطمئن است که می‌خواهد داده‌ها را بازیابی کند؟)
      final confirm = await showConfirmationDialog(context);
      if (!confirm) {
        return;
      }

      // 4️⃣ بستن دیتابیس فعلی
      await DatabaseHelper.closeDb();

      // 5️⃣ حذف دیتابیس فعلی
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      // 6️⃣ کپی کردن فایل بکاپ به مسیر اصلی
      await backupFile.copy(targetPath);

      // 7️⃣ باز کردن دیتابیس جدید (بازیابی شده)
      await DatabaseHelper.database;

      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('بازیابی موفقیت‌آمیز'),
          content: Text('دیتابیس با موفقیت بازیابی شد.'),
          actions: [
            TextButton(
              child: Text('باشه'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
    } catch (e) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('خطا'),
          content: Text(
            'بازیابی دیتابیس با خطا مواجه شد.\nلطفاً مطمئن شوید که فایل بکاپ سالم است.\n\n$e',
          ),
          actions: [
            TextButton(
              child: Text('باشه'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      debugPrint(e.toString());
    }
  }

  Future<bool> showConfirmationDialog(BuildContext context) async {
    // اینجا می‌توانید از هر کدام از روش‌های تایید که دوست دارید استفاده کنید
    // برای مثال، استفاده از یک دیالوگ تایید برای کاربر
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Text('هشدار'),
              content: Text(
                'تمامی داده‌های فعلی پاک خواهند شد. آیا مطمئن هستید که می‌خواهید دیتابیس قبلی را بازیابی کنید؟',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  child: Text('خیر'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true);
                  },
                  child: Text('بله'),
                ),
              ],
            );
          },
        ) ??
        false; // اگر دیالوگ بسته شود، مقدار پیش‌فرض false است
  }

  Future<Directory> getLettersDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/letters');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        children: [
          _sectionTitle('عمومی'),
          SwitchListTile(
            title: const Text('حالت تیره'),
            subtitle: const Text('فعال / غیرفعال کردن Dark Mode'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (value) {
              context.read<ThemeProvider>().toggleDark(value);
            },
          ),

          ThemeColorTile(),

          const Divider(),

          _sectionTitle('فایل‌ها'),
          const LettersPathTile(),

          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('بازیابی دیتابیس قبلی'),
            onTap: () {
              restoreDbBackup(context);
            },
          ),

          const Divider(),

          _sectionTitle('درباره برنامه'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('نسخه برنامه'),
            subtitle: const Text('1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('توسعه‌دهنده'),
            subtitle: GestureDetector(
              onTap: () async {
                final url = Uri.parse('https://haghshenasdev.github.io/');
                if (await canLaunchUrl(url)) {
                  await launchUrl(url);
                } else {
                  // اگر باز نشد می‌تونی یه هشدار یا پیام خطا نشون بدی
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('امکان باز کردن سایت وجود ندارد')),
                  );
                }
              },
              child: const Text(
                'MH-DEV | محمد مهدی حق شناس'
                '\n'
                'https://haghshenasdev.github.io/',
                style: TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
        ),
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

class DarkModeTile extends StatelessWidget {
  const DarkModeTile({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return SwitchListTile(
      title: const Text('حالت تیره (Dark Mode)'),
      secondary: const Icon(Icons.dark_mode),
      value: theme.isDark,
      onChanged: (value) {
        context.read<ThemeProvider>().toggleDark(value);
      },
    );
  }
}
