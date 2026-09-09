import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../db/database_helper.dart';

class RecordHistoryDialog extends StatefulWidget {
  final int recordId;

  const RecordHistoryDialog({super.key, required this.recordId});

  @override
  State<RecordHistoryDialog> createState() => _RecordHistoryDialogState();
}

class _RecordHistoryDialogState extends State<RecordHistoryDialog> {
  final ScrollController _scrollController = ScrollController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final result = await DatabaseHelper.getRecordHistory(widget.recordId);

      if (!mounted) return;

      setState(() {
        _history = result;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _retry() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    await _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 35),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850, maxHeight: 700),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(colorScheme),
              const Divider(height: 1),
              Expanded(child: _buildBody(colorScheme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.history_rounded,
              color: colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'تاریخچه تغییرات نامه',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'نامه شماره ${widget.recordId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(.55),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'بستن',
            onPressed: () {
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _buildErrorState(colorScheme);
    }

    if (_history.isEmpty) {
      return _buildEmptyState(colorScheme);
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 30),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final item = _history[index];

          return _HistoryItem(item: item, isLast: index == _history.length - 1);
        },
      ),
    );
  }

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            const Text(
              'دریافت تاریخچه با خطا مواجه شد.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(.55),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('تلاش مجدد'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_toggle_off_rounded,
              size: 55,
              color: colorScheme.onSurface.withOpacity(.25),
            ),
            const SizedBox(height: 14),
            Text(
              'هنوز تغییری برای این نامه ثبت نشده است.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface.withOpacity(.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLast;

  const _HistoryItem({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final action = item['action']?.toString() ?? '';
    final fieldName = item['field_name']?.toString();
    final oldValue = item['old_value']?.toString();
    final newValue = item['new_value']?.toString();
    final createdAt = item['created_at']?.toString();

    final dateTime = DateTime.tryParse(createdAt ?? '');

    final actionInfo = _actionInfo(action, colorScheme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline
          SizedBox(
            width: 44,
            child: _TimelineIndicator(
              color: actionInfo.color,
              lineColor: colorScheme.onSurface.withOpacity(.08),
              showLine: !isLast,
            ),
          ),

          const SizedBox(width: 12),

          // Content
          Expanded(
            child: _HistoryCard(
              item: item,
              actionInfo: actionInfo,
              dateTime: dateTime,
            ),
          ),
        ],
      ),
    );
  }

  _HistoryActionInfo _actionInfo(String action, ColorScheme colorScheme) {
    switch (action) {
      case 'create':
        return _HistoryActionInfo(
          title: 'ایجاد نامه',
          icon: Icons.add_circle_outline_rounded,
          color: colorScheme.primary,
        );

      case 'update':
        return _HistoryActionInfo(
          title: 'ویرایش نامه',
          icon: Icons.edit_note_rounded,
          color: Colors.orange,
        );

      case 'categories':
        return _HistoryActionInfo(
          title: 'تغییر دسته‌بندی',
          icon: Icons.label_outline_rounded,
          color: Colors.deepPurple,
        );

      case 'reminder_create':
        return _HistoryActionInfo(
          title: 'ایجاد یادآور',
          icon: Icons.notifications_active_outlined,
          color: Colors.blue,
        );

      case 'reminder_update':
        return _HistoryActionInfo(
          title: 'ویرایش یادآور',
          icon: Icons.notifications_none_rounded,
          color: Colors.orange,
        );

      case 'reminder_complete':
        return _HistoryActionInfo(
          title: 'تکمیل یادآور',
          icon: Icons.task_alt_rounded,
          color: Colors.green,
        );

      case 'reminder_cancel':
        return _HistoryActionInfo(
          title: 'لغو یادآور',
          icon: Icons.notifications_off_outlined,
          color: Colors.red,
        );

      case 'reminder_delete':
        return _HistoryActionInfo(
          title: 'حذف یادآور',
          icon: Icons.delete_outline_rounded,
          color: Colors.red,
        );

      default:
        return _HistoryActionInfo(
          title: 'تغییر اطلاعات',
          icon: Icons.change_circle_outlined,
          color: colorScheme.primary,
        );
    }
  }
}

class _TimelineIndicator extends StatelessWidget {
  final Color color;
  final Color lineColor;
  final bool showLine;

  const _TimelineIndicator({
    required this.color,
    required this.lineColor,
    required this.showLine,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(.11),
          ),
          child: Icon(Icons.history_rounded, size: 18, color: color),
        ),

        if (showLine)
          Container(
            width: 2,
            height: 95,
            margin: const EdgeInsets.only(top: 4),
            color: lineColor,
          ),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final _HistoryActionInfo actionInfo;
  final DateTime? dateTime;

  const _HistoryCard({
    required this.item,
    required this.actionInfo,
    required this.dateTime,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final fieldName = item['field_name']?.toString();
    final oldValue = item['old_value']?.toString();
    final newValue = item['new_value']?.toString();

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colorScheme.onSurface.withOpacity(.07)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  actionInfo.title,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              if (dateTime != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _formatDateTime(dateTime!),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.left,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colorScheme.onSurface.withOpacity(.48),
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (fieldName != null && fieldName.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: actionInfo.color.withOpacity(.07),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                fieldName,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: actionInfo.color,
                ),
              ),
            ),
          ],

          if (oldValue != null || newValue != null) ...[
            const SizedBox(height: 10),
            _buildChange(context, oldValue ?? '', newValue ?? ''),
          ],
        ],
      ),
    );
  }

  Widget _buildChange(BuildContext context, String oldValue, String newValue) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _valueBox(
          context,
          label: 'قبلی',
          value: oldValue,
          icon: Icons.remove_circle_outline_rounded,
          color: colorScheme.error,
        ),
        const SizedBox(height: 7),
        _valueBox(
          context,
          label: 'جدید',
          value: newValue,
          icon: Icons.add_circle_outline_rounded,
          color: colorScheme.primary,
        ),
      ],
    );
  }

  Widget _valueBox(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(.045),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withOpacity(.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            '$label:',
            textDirection: TextDirection.rtl,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: colorScheme.onSurface.withOpacity(.78),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDateTime(DateTime dateTime) {
    try {
      final j = Jalali.fromDateTime(dateTime);

      final date =
          '${j.year}/${j.month.toString().padLeft(2, '0')}/${j.day.toString().padLeft(2, '0')}';

      final time =
          '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';

      return '$date - $time';
    } catch (_) {
      return dateTime.toString();
    }
  }
}

class _HistoryActionInfo {
  final String title;
  final IconData icon;
  final Color color;

  const _HistoryActionInfo({
    required this.title,
    required this.icon,
    required this.color,
  });
}
