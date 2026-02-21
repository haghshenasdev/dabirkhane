import 'dart:io';
import '../providers/theme_provider.dart';
import '../utils/LettersPathTile.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ui/wid/ThemeColorTile.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

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
            leading: const Icon(Icons.cleaning_services),
            title: const Text('پاک‌سازی فایل‌های موقت'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('این قابلیت هنوز فعال نشده')),
              );
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
                'MH-DEV | محمد مهدی حق شناس',
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
