import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db/database_helper.dart';
import 'pages/database_recovery_page.dart';
import 'pages/schema_config_page.dart';
import 'providers/scan_service.dart';
import 'providers/theme_provider.dart';
import 'services/notification_service.dart';
import 'services/schema_service.dart';
import 'services/sync/sync_service.dart';
import 'ui/home_page.dart';
import 'utils/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final themeProvider = ThemeProvider();

  try {
    await themeProvider.load();
  } catch (e) {
    debugPrint('Theme load error: $e');
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => themeProvider,
      child: const BootstrapApp(),
    ),
  );
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  bool loading = true;
  Object? error;
  StackTrace? stackTrace;
  bool isConfigured = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = null;
      stackTrace = null;
    });

    try {
      // سرویس اسکن مستقل از دیتابیس است.
      await ScanService.initialize();

      // دیتابیس و Migration بخش حیاتی شروع برنامه هستند.
      await DatabaseHelper.database;

      // فقط آماده‌سازی سبک sync در مسیر شروع انجام می‌شود.
      // بازسازی صف تمام نامه‌های قدیمی در این مرحله عمداً انجام نمی‌شود.
      await DatabaseHelper.ensureSyncIdentity();

      // خطای سرویس Sync نباید مانع باز شدن نرم‌افزار شود.
      try {
        await SyncService.instance.initialize();
      } catch (e, st) {
        debugPrint('Sync initialization warning: $e');
        debugPrintStack(stackTrace: st);
      }

      var schema = await SchemaService.load();

      if (schema == null) {
        await SchemaService.initializeForNewInstall();
        schema = await SchemaService.load();
      }

      if (schema == null) {
        throw StateError('ساختار دبیرخانه پس از باز شدن دیتابیس ایجاد نشد.');
      }

      // اگر فایل دیتابیس از نسخه قدیمی یا یک Migration ناقص آمده باشد،
      // ستون‌های تعریف‌شده در Dynamic Schema را بدون دستکاری رکوردها
      // دوباره با ساختار SQLite هماهنگ می‌کنیم.
      await SchemaService.repairDatabaseColumns();
      schema = await SchemaService.load();

      if (schema == null) {
        throw StateError('ساختار دبیرخانه پس از تعمیر اولیه قابل خواندن نیست.');
      }

      final configured =
          schema.fields.any((field) => !field.system && field.visible);

      // Notificationها سرویس جانبی هستند؛ خرابی آنها نباید مانع
      // ورود کاربر به اطلاعات نامه‌ها شود.
      try {
        await NotificationService.instance.initialize();
        await NotificationService.instance.cancelAll();

        final backupReminderEnabled =
            await AppSettings.getMonthlyBackupReminderEnabled();

        if (backupReminderEnabled) {
          await NotificationService.instance
              .scheduleMonthlyBackupReminder();
        }

        await NotificationService.instance
            .rebuildAllDailyReminderNotifications();
      } catch (e, st) {
        debugPrint('Notification initialization warning: $e');
        debugPrintStack(stackTrace: st);
      }

      if (!mounted) return;

      setState(() {
        isConfigured = configured;
        loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final date =
            NotificationService.instance.takePendingDailyReminderDate();

        if (date != null) {
          MyApp.navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => HomePage(initialReminderDate: date),
            ),
            (route) => false,
          );
        }
      });
    } catch (e, st) {
      debugPrint('BOOTSTRAP ERROR: $e');
      debugPrintStack(stackTrace: st);

      if (!mounted) return;

      setState(() {
        error = e;
        stackTrace = st;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    Widget home;

    if (loading) {
      home = const _StartupLoadingPage();
    } else if (error != null) {
      home = DatabaseRecoveryPage(
        error: error!,
        stackTrace: stackTrace,
        onRetry: _bootstrap,
      );
    } else {
      home = isConfigured
          ? const HomePage()
          : const SchemaConfigPage(firstRun: true);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دبیرخانه',
      navigatorKey: MyApp.navigatorKey,
      theme: theme.lightTheme,
      darkTheme: theme.darkTheme,
      themeMode: theme.themeMode,
      home: home,
    );
  }
}

class _StartupLoadingPage extends StatelessWidget {
  const _StartupLoadingPage();

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              margin: const EdgeInsets.all(24),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.storage_rounded, size: 54),
                    SizedBox(height: 18),
                    Text(
                      'در حال آماده‌سازی دبیرخانه',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'در حال بررسی دیتابیس و ساختار فرم هستیم. '
                      'اگر مشکلی وجود داشته باشد، صفحه عیب‌یابی نمایش داده می‌شود.',
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 22),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  final bool isConfigured;

  const MyApp({super.key, required this.isConfigured});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'دبیرخانه',
      navigatorKey: navigatorKey,
      theme: theme.lightTheme,
      darkTheme: theme.darkTheme,
      themeMode: theme.themeMode,
      home: isConfigured
          ? const HomePage()
          : const SchemaConfigPage(firstRun: true),
    );
  }
}
