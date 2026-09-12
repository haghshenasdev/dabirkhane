import 'package:dabirkhane/providers/scan_service.dart';
import 'package:dabirkhane/services/notification_service.dart';
import 'package:dabirkhane/utils/app_settings.dart';

import 'providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'ui/home_page.dart';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  await ScanService.initialize();

  // ------------------------------------------------------------
  // Notification Service
  // ------------------------------------------------------------

  await NotificationService.instance.initialize();

  // ------------------------------------------------------------
  // حذف Notificationهای قدیمی
  //
  // این کار باعث می‌شود Notificationهای قدیمی که
  // به ازای هر Reminder ساخته شده‌اند باقی نمانند.
  // ------------------------------------------------------------

  await NotificationService.instance.cancelAll();

  // ------------------------------------------------------------
  // Monthly Backup Reminder
  // ------------------------------------------------------------

  final backupReminderEnabled =
      await AppSettings.getMonthlyBackupReminderEnabled();

  if (backupReminderEnabled) {
    await NotificationService.instance.scheduleMonthlyBackupReminder();
  }

  // ------------------------------------------------------------
  // Daily Letter Reminders
  // ------------------------------------------------------------

  await NotificationService.instance.rebuildAllDailyReminderNotifications();

  runApp(
    ChangeNotifierProvider(create: (_) => themeProvider, child: const MyApp()),
  );

  // ------------------------------------------------------------
  // اگر برنامه با کلیک روی Notification باز شده باشد
  // ------------------------------------------------------------

  WidgetsBinding.instance.addPostFrameCallback((_) {
    final date = NotificationService.instance.takePendingDailyReminderDate();

    if (date != null) {
      MyApp.navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => HomePage(initialReminderDate: date)),
        (route) => false,
      );
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دبیرخانه',
      navigatorKey: navigatorKey,
      // theme: ThemeData(fontFamily: 'sans'),
      theme: theme.lightTheme,
      darkTheme: theme.darkTheme,
      themeMode: theme.themeMode,
      home: HomePage(),
    );
  }
}
