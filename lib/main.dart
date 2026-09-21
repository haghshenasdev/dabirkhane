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

  // SQLite برای Windows / Linux / macOS
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

// ================================================================
// BootstrapApp
// ================================================================

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

    // اجازه می‌دهیم اولین frame نمایش داده شود،
    // سپس عملیات Bootstrap شروع شود.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = null;
      stackTrace = null;
    });

    try {
      // ------------------------------------------------------------
      // Scan Service
      // ------------------------------------------------------------
      await ScanService.initialize();

      // ------------------------------------------------------------
      // Database
      // ------------------------------------------------------------
      await DatabaseHelper.database;

      // ------------------------------------------------------------
      // Sync identity
      // ------------------------------------------------------------
      await DatabaseHelper.ensureSyncIdentity();

      // ------------------------------------------------------------
      // Schema
      // ------------------------------------------------------------
      //
      // SchemaService باید از Cache استفاده کند.
      //
      var schema = await SchemaService.preload();

      // نصب جدید
      if (schema == null) {
        await SchemaService.initializeForNewInstall();
        schema = await SchemaService.preload();
      }

      if (schema == null) {
        throw StateError('ساختار دبیرخانه پس از باز شدن دیتابیس ایجاد نشد.');
      }

      // ------------------------------------------------------------
      // بررسی ناسازگاری واقعی دیتابیس
      // ------------------------------------------------------------
      //
      // Repair فقط در صورت وجود مشکل انجام می‌شود.
      //
      final schemaMatchesDb = await SchemaService.databaseColumnsMatchSchema(
        schema,
      );

      if (!schemaMatchesDb) {
        debugPrint('Schema/Database mismatch detected. Starting repair...');

        await SchemaService.repairDatabaseColumns();

        // بعد از Repair، Cache را مجدداً دریافت می‌کنیم.
        schema = await SchemaService.preload();
      }

      if (schema == null) {
        throw StateError('ساختار دبیرخانه پس از تعمیر قابل خواندن نیست.');
      }

      // ------------------------------------------------------------
      // وضعیت تنظیم فرم
      // ------------------------------------------------------------
      final configured = schema.fields.any(
        (field) => !field.system && field.visible,
      );

      if (!mounted) return;

      setState(() {
        isConfigured = configured;
        loading = false;
      });

      // ------------------------------------------------------------
      // سرویس‌های جانبی بعد از نمایش UI
      // ------------------------------------------------------------
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeBackgroundServices();
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

  Future<void> _initializeBackgroundServices() async {
    // ------------------------------------------------------------
    // Sync
    // ------------------------------------------------------------
    try {
      await SyncService.instance.initialize();
    } catch (e, st) {
      debugPrint('Sync initialization warning: $e');
      debugPrintStack(stackTrace: st);
    }

    // ------------------------------------------------------------
    // Notifications
    // ------------------------------------------------------------
    try {
      await NotificationService.instance.initialize();

      await NotificationService.instance.cancelAll();

      final backupReminderEnabled =
          await AppSettings.getMonthlyBackupReminderEnabled();

      if (backupReminderEnabled) {
        await NotificationService.instance.scheduleMonthlyBackupReminder();
      }

      await NotificationService.instance.rebuildAllDailyReminderNotifications();

      if (!mounted) return;

      final date = NotificationService.instance.takePendingDailyReminderDate();

      if (date != null) {
        MyApp.navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => HomePage(initialReminderDate: date),
          ),
          (route) => false,
        );
      }
    } catch (e, st) {
      debugPrint('Notification initialization warning: $e');
      debugPrintStack(stackTrace: st);
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

    return MyApp(home: home, themeProvider: theme);
  }
}

// ================================================================
// MyApp
// ================================================================
//
// MyApp را به عنوان Widget نگه می‌داریم تا تمام کدهای قبلی پروژه
// که MyApp را می‌شناسند و از navigatorKey استفاده می‌کنند، سالم
// باقی بمانند.
//
// هیچ mounted یا عملیات Async در این کلاس نداریم.
// ================================================================

class MyApp extends StatelessWidget {
  final Widget home;
  final ThemeProvider themeProvider;

  const MyApp({super.key, required this.home, required this.themeProvider});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'دبیرخانه',

      navigatorKey: navigatorKey,

      theme: themeProvider.lightTheme,
      darkTheme: themeProvider.darkTheme,
      themeMode: themeProvider.themeMode,

      home: home,
    );
  }
}

// ================================================================
// Startup Loading
// ================================================================
//
// فقط UI لودینگ.
//
// هیچ mounted یا عملیات Async در این کلاس وجود ندارد.
// ================================================================

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
