import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const String _channelId = 'letter_reminders';
  static const String _channelName = 'یادآور نامه‌ها';
  static const String _channelDescription = 'اعلان‌های مربوط به یادآور نامه‌ها';

  static const String _backupChannelId = 'backup_reminders';
  static const String _backupChannelName = 'یادآور پشتیبان‌گیری';
  static const String _backupChannelDescription =
      'اعلان‌های مربوط به پشتیبان‌گیری';

  static const int _monthlyBackupReminderBaseId = 700000;

  // ------------------------------------------------------------
  // Initialize
  // ------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // ----------------------------------------------------------
    // Timezone
    // ----------------------------------------------------------

    tz.initializeTimeZones();

    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      } catch (_) {
        // از timezone پیش‌فرض استفاده می‌شود.
      }
    }

    // ----------------------------------------------------------
    // Android
    //
    // icon.png باید در این مسیر باشد:
    //
    // android/app/src/main/res/drawable/icon.png
    //
    // ----------------------------------------------------------

    const androidSettings = AndroidInitializationSettings('icon');

    // ----------------------------------------------------------
    // Windows
    // ----------------------------------------------------------

    const windowsSettings = WindowsInitializationSettings(
      appName: 'دبیرخانه',
      appUserModelId: 'com.haghshenasdev.dabirkhane',
      guid: '8d9a4f1b-8e5c-4a5a-b5f1-2d7f9f6a1234',
      iconPath: 'assets/images/logo.png',
    );

    // ----------------------------------------------------------
    // InitializationSettings
    // ----------------------------------------------------------

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // ----------------------------------------------------------
    // Android 13+
    // ----------------------------------------------------------

    if (Platform.isAndroid) {
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidImplementation?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  // ------------------------------------------------------------
  // Notification click
  // ------------------------------------------------------------

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;

    if (payload == null || payload.isEmpty) {
      return;
    }

    print('Reminder notification clicked. Record ID: $payload');
  }

  // ------------------------------------------------------------
  // Notification details
  // ------------------------------------------------------------

  NotificationDetails _notificationDetails() {
    // ----------------------------------------------------------
    // Android
    // ----------------------------------------------------------

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,

      // icon.png
      icon: 'icon',
    );

    // ----------------------------------------------------------
    // Windows
    // ----------------------------------------------------------

    const windowsDetails = WindowsNotificationDetails();

    return const NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );
  }

  // ------------------------------------------------------------
  // Schedule reminder
  // ------------------------------------------------------------

  Future<void> scheduleReminder({
    required int reminderId,
    required int recordId,
    required DateTime dueDate,
    required String text,
  }) async {
    await initialize();

    final scheduledDate = tz.TZDateTime.from(dueDate, tz.local);

    final now = tz.TZDateTime.now(tz.local);

    // تاریخ گذشته است.
    if (!scheduledDate.isAfter(now)) {
      return;
    }

    await _plugin.zonedSchedule(
      id: reminderId,
      title: 'یادآور نامه',
      body: text.trim().isEmpty
          ? 'زمان پیگیری این نامه فرا رسیده است.'
          : text.trim(),
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails(),

      // Android
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,

      // شماره نامه
      payload: recordId.toString(),
    );
  }

  // ------------------------------------------------------------
  // Cancel reminder
  // ------------------------------------------------------------

  Future<void> cancelReminder(int reminderId) async {
    await initialize();

    await _plugin.cancel(id: reminderId);
  }

  // ------------------------------------------------------------
  // Cancel all reminders
  // ------------------------------------------------------------

  Future<void> cancelAll() async {
    await initialize();

    await _plugin.cancelAll();
  }

  // ------------------------------------------------------------
  // Pending notifications
  // ------------------------------------------------------------

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    await initialize();

    return _plugin.pendingNotificationRequests();
  }

  // ------------------------------------------------------------
  // Test notification
  // ------------------------------------------------------------

  Future<void> showTestNotification() async {
    await initialize();

    await _plugin.show(
      id: 999999,
      title: 'دبیرخانه',
      body: 'این یک اعلان آزمایشی است.',
      notificationDetails: _notificationDetails(),
    );
  }

  // ------------------------------------------------------------
  // Debug initialize + test notification
  // ------------------------------------------------------------

  Future<String> debugInitialize() async {
    final logs = <String>[];

    void log(String message) {
      logs.add(message);
    }

    try {
      log('شروع initialize');

      // --------------------------------------------------------
      // Already initialized
      // --------------------------------------------------------

      if (_initialized) {
        log('⚠️ سرویس قبلاً initialize شده است.');

        try {
          log('مرحله تست: ارسال Notification تستی...');

          await _plugin.show(
            id: 999999,
            title: 'دبیرخانه',
            body: 'این یک اعلان آزمایشی است.',
            notificationDetails: _notificationDetails(),
          );

          log('✅ Notification تستی با موفقیت ارسال شد.');
        } catch (e, st) {
          log('❌ خطا در ارسال Notification تستی:\n$e');

          log('StackTrace:\n$st');
        }

        return logs.join('\n\n');
      }

      // --------------------------------------------------------
      // Timezone
      // --------------------------------------------------------

      log('مرحله 1: initializeTimeZones');

      tz.initializeTimeZones();

      log('✅ timezone database آماده شد.');

      try {
        log('مرحله 2: دریافت timezone دستگاه...');

        final timezoneInfo = await FlutterTimezone.getLocalTimezone();

        log('✅ timezone دستگاه:\n${timezoneInfo.identifier}');

        tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

        log('✅ timezone تنظیم شد.');
      } catch (e, st) {
        log('❌ خطا در FlutterTimezone:\n$e');

        log('StackTrace:\n$st');

        try {
          tz.setLocalLocation(tz.getLocation('Asia/Tehran'));

          log('⚠️ timezone به Asia/Tehran تغییر کرد.');
        } catch (e2) {
          log('❌ خطا در timezone جایگزین:\n$e2');
        }
      }

      // --------------------------------------------------------
      // Android settings
      // --------------------------------------------------------

      log('مرحله 3: ساخت AndroidInitializationSettings');

      const androidSettings = AndroidInitializationSettings('icon');

      log('✅ Android settings ساخته شد.');

      // --------------------------------------------------------
      // Windows settings
      // --------------------------------------------------------

      const windowsSettings = WindowsInitializationSettings(
        appName: 'دبیرخانه',
        appUserModelId: 'com.haghshenasdev.dabirkhane',
        guid: '8d9a4f1b-8e5c-4a5a-b5f1-2d7f9f6a1234',
        iconPath: 'assets/images/logo.png',
      );

      const initializationSettings = InitializationSettings(
        android: androidSettings,
        windows: windowsSettings,
      );

      // --------------------------------------------------------
      // Initialize plugin
      // --------------------------------------------------------

      log('مرحله 4: اجرای plugin.initialize');

      await _plugin.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      log('✅ plugin.initialize با موفقیت انجام شد.');

      // --------------------------------------------------------
      // Android permission
      // --------------------------------------------------------

      if (Platform.isAndroid) {
        log('مرحله 5: بررسی Android notification permission');

        final androidImplementation = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        if (androidImplementation == null) {
          log('⚠️ Android implementation پیدا نشد.');
        } else {
          log('✅ Android implementation پیدا شد.');

          log('درخواست Notification Permission...');

          final result = await androidImplementation
              .requestNotificationsPermission();

          log('نتیجه permission:\n$result');
        }
      }

      // --------------------------------------------------------
      // Mark initialized
      // --------------------------------------------------------

      _initialized = true;

      log('🎉 initialize با موفقیت کامل شد.');

      // --------------------------------------------------------
      // Test notification
      // --------------------------------------------------------

      try {
        log('مرحله 6: ارسال Notification تستی...');

        await _plugin.show(
          id: 999999,
          title: 'دبیرخانه',
          body: 'این یک اعلان آزمایشی است.',
          notificationDetails: _notificationDetails(),
        );

        log('✅ Notification تستی با موفقیت ارسال شد.');
      } catch (e, st) {
        log('❌ خطا در ارسال Notification تستی:\n$e');

        log('StackTrace:\n$st');
      }

      log('🏁 عملیات Debug به پایان رسید.');

      return logs.join('\n\n');
    } catch (e, st) {
      log('❌❌ خطای اصلی ❌❌');

      log('Error:\n$e');

      log('StackTrace:\n$st');

      return logs.join('\n\n');
    }
  }

  // ============================================================
  // Monthly Backup Reminder
  // ============================================================

  NotificationDetails _backupNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _backupChannelId,
      _backupChannelName,
      channelDescription: _backupChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: 'icon',
    );

    const windowsDetails = WindowsNotificationDetails();

    return const NotificationDetails(
      android: androidDetails,
      windows: windowsDetails,
    );
  }

  /// تاریخ یادآور پشتیبان‌گیری برای یک ماه
  ///
  /// روز اول ماه ساعت 10:00
  /// اگر روز اول ماه جمعه باشد، شنبه ساعت 10:00
  tz.TZDateTime _getBackupReminderDate(int year, int month) {
    var date = tz.TZDateTime(tz.local, year, month, 1, 10, 0);

    // جمعه = 5
    if (date.weekday == DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }

    return date;
  }

  /// زمان‌بندی 12 ماه آینده
  Future<void> scheduleMonthlyBackupReminder() async {
    await initialize();

    // ابتدا فقط Reminderهای مخصوص Backup را حذف می‌کنیم.
    for (int i = 0; i < 12; i++) {
      await _plugin.cancel(id: _monthlyBackupReminderBaseId + i);
    }

    final now = tz.TZDateTime.now(tz.local);

    int scheduledCount = 0;

    for (int offset = 0; offset < 12; offset++) {
      final totalMonths = now.month - 1 + offset;

      final year = now.year + (totalMonths ~/ 12);
      final month = (totalMonths % 12) + 1;

      var scheduledDate = _getBackupReminderDate(year, month);

      // اگر تاریخ این ماه گذشته باشد، آن را رد می‌کنیم.
      if (!scheduledDate.isAfter(now)) {
        continue;
      }

      final notificationId = _monthlyBackupReminderBaseId + scheduledCount;

      await _plugin.zonedSchedule(
        id: notificationId,
        title: 'یادآور پشتیبان‌گیری',
        body: 'زمان تهیه نسخه پشتیبان ماهانه دبیرخانه فرا رسیده است.',
        scheduledDate: scheduledDate,
        notificationDetails: _backupNotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'monthly_backup',
      );

      scheduledCount++;
    }
  }

  /// لغو تمام Reminderهای مربوط به پشتیبان‌گیری ماهانه
  Future<void> cancelMonthlyBackupReminder() async {
    await initialize();

    for (int i = 0; i < 12; i++) {
      await _plugin.cancel(id: _monthlyBackupReminderBaseId + i);
    }
  }
}
