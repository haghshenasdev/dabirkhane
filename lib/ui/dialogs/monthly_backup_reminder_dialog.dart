import 'package:flutter/material.dart';

class MonthlyBackupReminderDialog extends StatelessWidget {
  const MonthlyBackupReminderDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Icon(
            Icons.backup_outlined,
            size: 34,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
        title: const Text('یادآوری پشتیبان‌گیری', textAlign: TextAlign.center),
        content: const Text(
          'زمان تهیه نسخه پشتیبان ماهانه دبیرخانه فرا رسیده است.\n\n'
          'برای جلوگیری از از دست رفتن اطلاعات، پیشنهاد می‌شود '
          'همین حالا از اطلاعات برنامه نسخه پشتیبان تهیه کنید.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.backup_outlined),
            label: const Text('تهیه پشتیبان'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
            },
            child: const Text('بعداً'),
          ),
        ],
      ),
    );
  }
}
