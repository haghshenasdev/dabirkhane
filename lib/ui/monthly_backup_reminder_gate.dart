import 'package:flutter/material.dart';

import '../services/notification_service.dart';
import '../utils/app_settings.dart';
import 'dialogs/monthly_backup_reminder_dialog.dart';

class MonthlyBackupReminderGate extends StatefulWidget {
  final Widget child;

  const MonthlyBackupReminderGate({
    super.key,
    required this.child,
  });

  @override
  State<MonthlyBackupReminderGate> createState() =>
      _MonthlyBackupReminderGateState();
}

class _MonthlyBackupReminderGateState
    extends State<MonthlyBackupReminderGate> {
  bool _checked = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkReminder();
    });
  }

  Future<void> _checkReminder() async {
    if (_checked) {
      return;
    }

    _checked = true;

    final enabled =
        await AppSettings.getMonthlyBackupReminderEnabled();

    if (!enabled) {
      return;
    }

    final now = DateTime.now();

    // فقط زمانی که امروز روز یادآوری است.
    var reminderDate = DateTime(
      now.year,
      now.month,
      1,
    );

    // اگر اول ماه جمعه باشد، شنبه یادآوری می‌کنیم.
    if (reminderDate.weekday == DateTime.friday) {
      reminderDate = reminderDate.add(
        const Duration(days: 1),
      );
    }

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final reminderDay = DateTime(
      reminderDate.year,
      reminderDate.month,
      reminderDate.day,
    );

    if (today != reminderDay) {
      return;
    }

    final monthKey =
        '${reminderDate.year}-${reminderDate.month.toString().padLeft(2, '0')}';

    final lastShown =
        await AppSettings.getMonthlyBackupReminderLastShown();

    // در همین ماه قبلاً نمایش داده شده.
    if (lastShown == monthKey) {
      return;
    }

    if (!mounted) {
      return;
    }

    await Future.delayed(
      const Duration(milliseconds: 400),
    );

    if (!mounted) {
      return;
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const MonthlyBackupReminderDialog();
      },
    );

    // حتی اگر کاربر "بعداً" را بزند،
    // در همین ماه دوباره دیالوگ نمایش داده نمی‌شود.
    await AppSettings.setMonthlyBackupReminderLastShown(
      monthKey,
    );

    if (result == true) {
      // فعلاً فقط دیالوگ بسته می‌شود.
      //
      // در مرحله بعد می‌توانیم همین‌جا مستقیماً
      // دیالوگ/صفحه تهیه Backup را باز کنیم.
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}