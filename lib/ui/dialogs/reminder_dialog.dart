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
  int? _processingReminderId;

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

  // ============================================================
  // Load
  // ============================================================

  Future<void> _loadReminders() async {
    try {
      final reminders = await DatabaseHelper.getRemindersForRecord(
        widget.recordId,
      );

      reminders.sort((a, b) => b.dueDate.compareTo(a.dueDate));

      if (!mounted) return;

      setState(() {
        _reminders = reminders;
        _loading = false;
      });
    } catch (e) {
      debugPrint('load reminders error: $e');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });
    }
  }

  // ============================================================
  // Date
  // ============================================================

  DateTime _calculateDueDate(int days) {
    final rawDate = widget.letterDate.add(Duration(days: days));

    // همیشه ساعت ۹ صبح
    return DateTime(rawDate.year, rawDate.month, rawDate.day, 9, 0);
  }

  DateTime _normalizeToNine(DateTime date) {
    return DateTime(date.year, date.month, date.day, 9, 0);
  }

  String _formatJalali(DateTime date) {
    final jalali = Jalali.fromDateTime(date);

    return '${jalali.year}/${jalali.month.toString().padLeft(2, '0')}/${jalali.day.toString().padLeft(2, '0')}';
  }

  bool _isDue(Reminder reminder) {
    return reminder.isPending && !reminder.dueDate.isAfter(DateTime.now());
  }

  // ============================================================
  // Save new reminder
  // ============================================================

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

      await NotificationService.instance.rebuildDailyReminderForDate(dueDate);

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
    } catch (e, stackTrace) {
      debugPrint('save reminder error: $e');
      debugPrintStack(stackTrace: stackTrace);

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

  // ============================================================
  // Complete
  // ============================================================

  Future<void> _completeReminder(Reminder reminder) async {
    if (reminder.id == null) return;
    if (!reminder.isPending) return;

    setState(() {
      _processingReminderId = reminder.id;
    });

    try {
      await DatabaseHelper.completeReminder(reminder.id!);

      await NotificationService.instance.rebuildDailyReminderForDate(
        reminder.dueDate,
      );

      await _loadReminders();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'پیگیری نامه انجام شد.',
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('complete reminder error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showError('خطا در ثبت انجام شدن یادآور:\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _processingReminderId = null;
        });
      }
    }
  }

  // ============================================================
  // Extend
  // ============================================================

  Future<void> _extendReminder(Reminder reminder, int days) async {
    if (reminder.id == null) return;
    if (!reminder.isPending) return;

    setState(() {
      _processingReminderId = reminder.id;
    });

    try {
      final now = DateTime.now();

      // اگر موعد قبلی گذشته باشد، تمدید از امروز حساب می‌شود.
      // اگر هنوز نرسیده باشد، از موعد فعلی حساب می‌شود.
      final baseDate = reminder.dueDate.isAfter(now) ? reminder.dueDate : now;

      final rawDate = baseDate.add(Duration(days: days));

      final newDueDate = _normalizeToNine(rawDate);

      final oldDueDate = reminder.dueDate;

      final updatedReminder = reminder.copyWith(
        dueDate: newDueDate,
        status: ReminderStatus.pending,
        completedAt: null,
      );

      await DatabaseHelper.updateReminder(updatedReminder);

      // روز قبلی ممکن است تعداد Reminderهایش کم شده باشد.
      await NotificationService.instance.rebuildDailyReminderForDate(
        oldDueDate,
      );

      // روز جدید ممکن است تعداد Reminderهایش زیاد شده باشد.
      await NotificationService.instance.rebuildDailyReminderForDate(
        newDueDate,
      );
      await _loadReminders();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'یادآور تا ${_formatJalali(newDueDate)} تمدید شد.',
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e, stackTrace) {
      debugPrint('extend reminder error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showError('خطا در تمدید یادآور:\n$e');
    } finally {
      if (mounted) {
        setState(() {
          _processingReminderId = null;
        });
      }
    }
  }

  Future<void> _showExtendMenu(Reminder reminder) async {
    if (reminder.id == null || !reminder.isPending) return;

    final selectedDays = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withOpacity(.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                const Text(
                  'تمدید پیگیری',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 8),

                Text(
                  'موعد جدید را انتخاب کنید',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(.60),
                  ),
                ),

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(child: _extendChoice(context, days: 7)),
                    const SizedBox(width: 8),
                    Expanded(child: _extendChoice(context, days: 15)),
                    const SizedBox(width: 8),
                    Expanded(child: _extendChoice(context, days: 30)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedDays == null) return;

    await _extendReminder(reminder, selectedDays);
  }

  Widget _extendChoice(BuildContext context, {required int days}) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.pop(context, days);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.primary.withOpacity(.16)),
        ),
        child: Column(
          children: [
            Icon(Icons.update_rounded, color: colorScheme.primary),
            const SizedBox(height: 5),
            Text(
              '$days روز',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Delete
  // ============================================================

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

    try {
      final dueDate = reminder.dueDate;

      await DatabaseHelper.deleteReminder(reminder.id!);

      await NotificationService.instance.rebuildDailyReminderForDate(dueDate);

      if (!mounted) return;

      await _loadReminders();
    } catch (e) {
      if (!mounted) return;

      _showError('خطا در حذف یادآور:\n$e');
    }
  }

  // ============================================================
  // Reminder item
  // ============================================================

  Widget _buildReminderItem(Reminder reminder) {
    final colorScheme = Theme.of(context).colorScheme;

    final due = _isDue(reminder);
    final processing = _processingReminderId == reminder.id;

    final Color itemColor;

    if (reminder.isCompleted) {
      itemColor = Colors.green;
    } else if (due) {
      itemColor = Colors.orange.shade700;
    } else {
      itemColor = colorScheme.primary;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: itemColor.withOpacity(.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: itemColor.withOpacity(.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                reminder.isCompleted
                    ? Icons.check_circle_rounded
                    : due
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: itemColor,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: reminder.isCompleted
                            ? colorScheme.onSurface.withOpacity(.60)
                            : null,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      reminder.isCompleted
                          ? 'انجام شده • ${_formatJalali(reminder.dueDate)}'
                          : due
                          ? 'موعد پیگیری رسیده • ${_formatJalali(reminder.dueDate)}'
                          : 'سررسید: ${_formatJalali(reminder.dueDate)} ساعت ۰۹:۰۰',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        color: itemColor.withOpacity(.80),
                        fontWeight: due && reminder.isPending
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),

              IconButton(
                tooltip: 'حذف',
                onPressed: processing ? null : () => _deleteReminder(reminder),
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
              ),
            ],
          ),

          // فقط برای یادآور موعدرسیده دکمه‌های عملیاتی نمایش داده شوند
          if (due && reminder.isPending) ...[
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: processing
                        ? null
                        : () => _showExtendMenu(reminder),
                    icon: const Icon(Icons.update_rounded, size: 18),
                    label: const Text('تمدید'),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: processing
                        ? null
                        : () => _completeReminder(reminder),
                    icon: processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: const Text('انجام شد'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ============================================================
  // Error
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================

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
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
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
                  // ======================================================
                  // Header
                  // ======================================================
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(.14),
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

                  // ======================================================
                  // Letter date
                  // ======================================================
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

                  // ======================================================
                  // Days
                  // ======================================================
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
                      'تاریخ سررسید: ${_formatJalali(previewDate)} ساعت ۰۹:۰۰',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ======================================================
                  // Text
                  // ======================================================
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

                  // ======================================================
                  // Add
                  // ======================================================
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

                  // ======================================================
                  // Existing reminders
                  // ======================================================
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
