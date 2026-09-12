import 'dart:io';

import 'package:dabirkhane/db/database_helper.dart';
import 'package:dabirkhane/main.dart';
import 'package:dabirkhane/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shamsi_date/shamsi_date.dart';
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

  // ============================================================
  // Daily Reminder
  // ============================================================

  static const String _dailyReminderPrefix = 'daily_reminder|';

  /// ID ثابت برای هر روز.
  ///
  /// با این کار مثلاً تمام یادآورهای 1405/06/21
  /// فقط یک Notification دارند.
  int _dailyNotificationId(DateTime date) {
    final jalali = Jalali.fromDateTime(date);

    return 100000 + (jalali.year * 10000) + (jalali.month * 100) + jalali.day;
  }

  String _jalaliDateString(DateTime date) {
    final jalali = Jalali.fromDateTime(date);

    return '${jalali.year}/'
        '${jalali.month.toString().padLeft(2, '0')}/'
        '${jalali.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseDailyReminderPayload(String payload) {
    if (!payload.startsWith(_dailyReminderPrefix)) {
      return null;
    }

    final dateText = payload.substring(_dailyReminderPrefix.length);

    final parts = dateText.split('/');

    if (parts.length != 3) {
      return null;
    }

    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);

    if (year == null || month == null || day == null) {
      return null;
    }

    try {
      return Jalali(year, month, day).toDateTime();
    } catch (_) {
      return null;
    }
  }

  /// تاریخ روزی که کاربر از طریق Notification روی آن کلیک کرده.
  ///
  /// اگر برنامه هنگام دریافت کلیک هنوز بالا نیامده باشد،
  /// این مقدار موقتاً ذخیره می‌شود.
  String? _pendingDailyReminderDate;

  String? takePendingDailyReminderDate() {
    final value = _pendingDailyReminderDate;
    _pendingDailyReminderDate = null;
    return value;
  }

  // ============================================================
  // Initialize
  // ============================================================

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

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

    const androidSettings = AndroidInitializationSettings('icon');

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

    await _plugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    if (Platform.isAndroid) {
      final androidImplementation = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidImplementation?.requestNotificationsPermission();
    }

    _initialized = true;

    // اگر برنامه با کلیک روی Notification باز شده باشد.
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();

      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;

        if (payload != null && payload.isNotEmpty) {
          final date = _parseDailyReminderPayload(payload);

          if (date != null) {
            _pendingDailyReminderDate = _jalaliDateString(date);
          }
        }
      }
    } catch (e) {
      print('Notification launch details error: $e');
    }
  }

  // ============================================================
  // Notification click
  // ============================================================

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;

    if (payload == null || payload.isEmpty) {
      return;
    }

    final date = _parseDailyReminderPayload(payload);

    if (date == null) {
      print('Unknown notification payload: $payload');
      return;
    }

    final jalaliDate = _jalaliDateString(date);

    print('Daily reminder clicked: $jalaliDate');

    _pendingDailyReminderDate = jalaliDate;
  }

  // ============================================================
  // Notification details
  // ============================================================

  NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
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

  // ============================================================
  // Daily reminder
  // ============================================================

  /// برای یک روز مشخص، فقط یک Notification ایجاد می‌کند.
  ///
  /// اگر 5 نامه در این روز Reminder داشته باشند،
  /// فقط یک Notification ساخته می‌شود.
  Future<void> scheduleDailyReminder(DateTime date) async {
    await initialize();

    final day = DateTime(date.year, date.month, date.day);

    final notificationId = _dailyNotificationId(day);

    // ابتدا Notification قبلی همان روز را حذف می‌کنیم.
    await _plugin.cancel(id: notificationId);

    final allPendingReminders = await DatabaseHelper.getPendingReminders();

    final remindersForDay = allPendingReminders.where((reminder) {
      return reminder.dueDate.year == day.year &&
          reminder.dueDate.month == day.month &&
          reminder.dueDate.day == day.day;
    }).toList();

    // اگر برای این روز Reminder نداریم،
    // Notification هم نباید وجود داشته باشد.
    if (remindersForDay.isEmpty) {
      return;
    }

    final now = tz.TZDateTime.now(tz.local);

    var scheduledDate = tz.TZDateTime(
      tz.local,
      day.year,
      day.month,
      day.day,
      9,
      0,
    );

    // اگر ساعت 9 امروز گذشته باشد، دیگر برای امروز
    // Notification زمان‌بندی نمی‌کنیم.
    if (!scheduledDate.isAfter(now)) {
      return;
    }

    final count = remindersForDay.length;

    final body = count == 1
        ? 'موعد پیگیری ۱ نامه امروز فرا رسیده است.'
        : 'موعد پیگیری $count نامه امروز فرا رسیده است.';

    final jalaliDate = _jalaliDateString(day);

    await _plugin.zonedSchedule(
      id: notificationId,
      title: '🔔 یادآوری پیگیری نامه‌ها',
      body: body,
      scheduledDate: scheduledDate,
      notificationDetails: _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: '$_dailyReminderPrefix$jalaliDate',
    );
  }

  /// Notification یک روز را مجدداً محاسبه می‌کند.
  ///
  /// بعد از اضافه، حذف، انجام شدن یا تغییر موعد Reminder
  /// باید این متد اجرا شود.
  Future<void> rebuildDailyReminderForDate(DateTime date) async {
    await scheduleDailyReminder(date);
  }

  /// تمام Notificationهای روزانه را از روی دیتابیس می‌سازد.
  ///
  /// این متد در شروع برنامه اجرا می‌شود.
  Future<void> rebuildAllDailyReminderNotifications() async {
    await initialize();

    final allPendingReminders = await DatabaseHelper.getPendingReminders();

    final uniqueDays = <String, DateTime>{};

    for (final reminder in allPendingReminders) {
      final date = DateTime(
        reminder.dueDate.year,
        reminder.dueDate.month,
        reminder.dueDate.day,
      );

      final key = '${date.year}-${date.month}-${date.day}';

      uniqueDays[key] = date;
    }

    for (final date in uniqueDays.values) {
      await scheduleDailyReminder(date);
    }
  }

  /// Notification مربوط به یک روز را حذف می‌کند.
  Future<void> cancelDailyReminder(DateTime date) async {
    await initialize();

    await _plugin.cancel(id: _dailyNotificationId(date));
  }

  // ============================================================
  // Legacy individual reminder methods
  // ============================================================

  /// این متد دیگر برای Reminderهای نامه استفاده نمی‌شود.
  ///
  /// نگه داشته شده تا کدهای قدیمی پروژه دچار خطای Compile نشوند.
  Future<void> scheduleReminder({
    required int reminderId,
    required int recordId,
    required DateTime dueDate,
    required String text,
  }) async {
    await scheduleDailyReminder(dueDate);
  }

  Future<void> cancelReminder(int reminderId) async {
    await initialize();

    // عمداً چیزی لغو نمی‌شود.
    //
    // Notificationها اکنون بر اساس «روز» مدیریت می‌شوند
    // نه بر اساس reminderId.
  }

  // ============================================================
  // Cancel all
  // ============================================================

  Future<void> cancelAll() async {
    await initialize();

    await _plugin.cancelAll();
  }

  // ============================================================
  // Pending notifications
  // ============================================================

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    await initialize();

    return _plugin.pendingNotificationRequests();
  }

  // ============================================================
  // Test notification
  // ============================================================

  Future<void> showTestNotification() async {
    await initialize();

    await _plugin.show(
      id: 999999,
      title: 'دبیرخانه',
      body: 'این یک اعلان آزمایشی است.',
      notificationDetails: _notificationDetails(),
    );
  }

  // ============================================================
  // Debug
  // ============================================================

  Future<String> debugInitialize() async {
    final logs = <String>[];

    void log(String message) {
      logs.add(message);
    }

    try {
      log('شروع initialize');

      await initialize();

      log('✅ Notification Service آماده است.');

      try {
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
    } catch (e, st) {
      log('❌ خطای اصلی');
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

  tz.TZDateTime _getBackupReminderDate(int year, int month) {
    var date = tz.TZDateTime(tz.local, year, month, 1, 10, 0);

    if (date.weekday == DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }

    return date;
  }

  Future<void> scheduleMonthlyBackupReminder() async {
    await initialize();

    for (int i = 0; i < 12; i++) {
      await _plugin.cancel(id: _monthlyBackupReminderBaseId + i);
    }

    final now = tz.TZDateTime.now(tz.local);

    int scheduledCount = 0;

    for (int offset = 0; offset < 12; offset++) {
      final totalMonths = now.month - 1 + offset;

      final year = now.year + (totalMonths ~/ 12);
      final month = (totalMonths % 12) + 1;

      final scheduledDate = _getBackupReminderDate(year, month);

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

  Future<void> cancelMonthlyBackupReminder() async {
    await initialize();

    for (int i = 0; i < 12; i++) {
      await _plugin.cancel(id: _monthlyBackupReminderBaseId + i);
    }
  }

  void openPendingReminderDate() {
    final date = takePendingDailyReminderDate();

    if (date == null) {
      return;
    }

    final navigator = MyApp.navigatorKey.currentState;

    if (navigator == null) {
      return;
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage(initialReminderDate: date)),
      (route) => false,
    );
  }
}
