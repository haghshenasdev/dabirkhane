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

  // ------------------------------------------------------------
  // Initialize
  // ------------------------------------------------------------

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    // Initialize timezone database.
    tz.initializeTimeZones();

    // Set device timezone.
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();

      tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));
    } catch (e) {
      // Fallback
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      } catch (_) {
        // اگر timezone مورد نظر در دیتابیس وجود نداشت،
        // timezone پیش‌فرض timezone package استفاده می‌شود.
      }
    }

    // ----------------------------------------------------------
    // Android
    // ----------------------------------------------------------

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // ----------------------------------------------------------
    // Windows
    // ----------------------------------------------------------

    const windowsSettings = WindowsInitializationSettings(
      appName: 'دبیرخانه',
      appUserModelId: 'com.haghshenasdev.dabirkhane',
      guid: '8d9a4f1b-8e5c-4a5a-b5f1-2d7f9f6a1234',
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

    // Android 13+
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

    // payload فعلاً شماره نامه است.
    //
    // در مرحله بعد اینجا می‌توانیم:
    //
    // 1. شماره نامه را استخراج کنیم
    // 2. صفحه Home را باز کنیم
    // 3. همان نامه را مستقیماً باز کنیم

    print('Reminder notification clicked. Record ID: $payload');
  }

  // ------------------------------------------------------------
  // Notification details
  // ------------------------------------------------------------

  NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

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
      body: 'اعلان‌های یادآور با موفقیت فعال شده‌اند.',
      notificationDetails: _notificationDetails(),
    );
  }
}
