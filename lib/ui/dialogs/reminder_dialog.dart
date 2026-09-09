import 'package:dabirkhane/model/reminder.dart';
import 'package:dabirkhane/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../db/database_helper.dart';

class ReminderDialog extends StatefulWidget {
  final int recordId;
  final DateTime letterDate;

  const ReminderDialog({
    super.key,
    required this.recordId,
    required this.letterDate,
  });

  @override
  State<ReminderDialog> createState() => _ReminderDialogState();
}

class _ReminderDialogState extends State<ReminderDialog> {
  final _daysController = TextEditingController(text: '40');
  final _textController = TextEditingController();

  List<Reminder> _reminders = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadReminders();
  }

  @override
  void dispose() {
    _daysController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadReminders() async {
    try {
      final reminders = await DatabaseHelper.getRemindersForRecord(
        widget.recordId,
      );

      if (!mounted) return;

      setState(() {
        _reminders = reminders;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  DateTime _calculateDueDate(int days) {
    return widget.letterDate.add(Duration(days: days));
  }

  String _formatJalali(DateTime date) {
    final jalali = Jalali.fromDateTime(date);

    return '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveReminder() async {
    final days = int.tryParse(_daysController.text.trim());

    if (days == null || days <= 0) {
      _showError('تعداد روز را به صورت صحیح وارد کنید.');
      return;
    }

    final text = _textController.text.trim();

    if (text.isEmpty) {
      _showError('متن یادآور را وارد کنید.');
      return;
    }

    if (_saving) return;

    setState(() {
      _saving = true;
    });

    try {
      final dueDate = _calculateDueDate(days);

      final reminder = Reminder(
        recordId: widget.recordId,
        dueDate: dueDate,
        text: text,
        status: ReminderStatus.pending,
        createdAt: DateTime.now(),
      );

      final reminderId = await DatabaseHelper.insertReminder(reminder);

      final savedReminder = reminder.copyWith(id: reminderId);

      await NotificationService.instance.scheduleReminder(
        reminderId: reminderId,
        recordId: widget.recordId,
        dueDate: dueDate,
        text: text,
      );

      if (!mounted) return;

      _textController.clear();

      await _loadReminders();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'یادآور برای $days روز بعد ثبت شد.',
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _showError('خطا در ثبت یادآور:\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteReminder(Reminder reminder) async {
    if (reminder.id == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف یادآور', textDirection: TextDirection.rtl),
          content: const Text(
            'آیا از حذف این یادآور مطمئن هستید؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await NotificationService.instance.cancelReminder(reminder.id!);

    await DatabaseHelper.deleteReminder(reminder.id!);

    if (!mounted) return;

    await _loadReminders();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildReminderItem(Reminder reminder) {
    final dueText = _formatJalali(reminder.dueDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(
            reminder.isCompleted
                ? Icons.check_circle_outline_rounded
                : Icons.notifications_active_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  reminder.text,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'سررسید: $dueText',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.65),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: () => _deleteReminder(reminder),
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final previewDays = int.tryParse(_daysController.text.trim()) ?? 0;

    final previewDate = previewDays > 0 ? _calculateDueDate(previewDays) : null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          decoration: BoxDecoration(
            color: Color.alphaBlend(
              colorScheme.primary.withOpacity(0.10),
              colorScheme.surface.withOpacity(0.94),
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.primary.withOpacity(0.20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.notifications_active_outlined,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'یادآور نامه',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  Text('تاریخ نامه', style: theme.textTheme.bodySmall),

                  const SizedBox(height: 5),

                  Text(
                    _formatJalali(widget.letterDate),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 20),

                  TextField(
                    controller: _daysController,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.rtl,
                    decoration: InputDecoration(
                      labelText: 'چند روز بعد؟',
                      hintText: 'مثلاً 40',
                      prefixIcon: const Icon(Icons.schedule_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {});
                    },
                  ),

                  if (previewDate != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'تاریخ سررسید: ${_formatJalali(previewDate)}',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  TextField(
                    controller: _textController,
                    maxLines: 3,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      labelText: 'متن یادآور',
                      hintText: 'مثلاً پیگیری پاسخ اداره مربوطه',
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 42),
                        child: Icon(Icons.edit_note_rounded),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _saveReminder,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_alert_rounded),
                      label: Text(_saving ? 'در حال ثبت...' : 'ثبت یادآور'),
                    ),
                  ),

                  if (!_loading && _reminders.isNotEmpty) ...[
                    const SizedBox(height: 24),

                    const Text(
                      'یادآورهای این نامه',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    ..._reminders.map(_buildReminderItem),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
