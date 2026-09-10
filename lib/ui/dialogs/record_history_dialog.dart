import 'dart:ui';

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
        _loading = false;
        _error = e.toString();
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 760),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface.withOpacity(
                  colorScheme.brightness == Brightness.dark ? .88 : .82,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: colorScheme.onSurface.withOpacity(.10),
                ),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.shadow.withOpacity(.14),
                    blurRadius: 35,
                    spreadRadius: 2,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  children: [
                    _buildHeader(colorScheme),
                    Container(
                      height: 1,
                      color: colorScheme.onSurface.withOpacity(.07),
                    ),
                    Expanded(child: _buildBody(colorScheme)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Header
  // --------------------------------------------------------------------------

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 17),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(.10),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: colorScheme.primary.withOpacity(.10)),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 24,
              color: colorScheme.primary,
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
                const SizedBox(height: 4),
                Text(
                  'سوابق تغییرات نامه شماره ${widget.recordId}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
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

  // --------------------------------------------------------------------------
  // Body
  // --------------------------------------------------------------------------

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

    final groups = _groupHistory(_history);

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          return _HistoryGroup(
            items: groups[index].items,
            dateTime: groups[index].dateTime,
            isLast: index == groups.length - 1,
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Grouping
  // --------------------------------------------------------------------------

  List<_HistoryGroupData> _groupHistory(List<Map<String, dynamic>> history) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final item in history) {
      final rawDate = item['created_at']?.toString() ?? '';
      final dateTime = DateTime.tryParse(rawDate);

      final key = dateTime != null ? _groupKey(dateTime) : 'unknown_$rawDate';

      grouped.putIfAbsent(key, () => []).add(item);
    }

    final result = grouped.entries.map((entry) {
      DateTime? dateTime;

      for (final item in entry.value) {
        final parsed = DateTime.tryParse(item['created_at']?.toString() ?? '');

        if (parsed != null) {
          dateTime = parsed;
          break;
        }
      }

      return _HistoryGroupData(dateTime: dateTime, items: entry.value);
    }).toList();

    result.sort((a, b) {
      if (a.dateTime == null && b.dateTime == null) {
        return 0;
      }

      if (a.dateTime == null) {
        return 1;
      }

      if (b.dateTime == null) {
        return -1;
      }

      return b.dateTime!.compareTo(a.dateTime!);
    });

    return result;
  }

  String _groupKey(DateTime dateTime) {
    return '${dateTime.year}-'
        '${dateTime.month.toString().padLeft(2, '0')}-'
        '${dateTime.day.toString().padLeft(2, '0')}-'
        '${dateTime.hour.toString().padLeft(2, '0')}-'
        '${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // --------------------------------------------------------------------------
  // Error
  // --------------------------------------------------------------------------

  Widget _buildErrorState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 44,
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
              _error ?? '',
              textAlign: TextAlign.center,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
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

  // --------------------------------------------------------------------------
  // Empty
  // --------------------------------------------------------------------------

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(.07),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_toggle_off_rounded,
                size: 38,
                color: colorScheme.primary.withOpacity(.45),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'هنوز تغییری برای این نامه ثبت نشده است.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'تغییرات بعدی نامه در این بخش نمایش داده می‌شوند.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Group
// ============================================================================

class _HistoryGroup extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final DateTime? dateTime;
  final bool isLast;

  const _HistoryGroup({
    required this.items,
    required this.dateTime,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final actions = _uniqueActions(items);

    final accentColor = _getAccentColor(actions, colorScheme);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline
        SizedBox(
          width: 28,
          child: Column(
            children: [
              const SizedBox(height: 8),

              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withOpacity(.25),
                      blurRadius: 7,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              if (!isLast)
                Container(
                  width: 1,
                  height: 210,
                  margin: const EdgeInsets.only(top: 7),
                  color: colorScheme.outlineVariant.withOpacity(.55),
                ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _buildGlassCard(context, colorScheme, actions, accentColor),
        ),
      ],
    );
  }

  Widget _buildGlassCard(
    BuildContext context,
    ColorScheme colorScheme,
    List<String> actions,
    Color accentColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 17),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            colorScheme.surfaceContainerHigh.withOpacity(.72),
            colorScheme.surfaceContainerLow.withOpacity(.48),
          ],
        ),
        border: Border.all(color: colorScheme.onSurface.withOpacity(.075)),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(.045),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(15, 14, 15, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Event header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 5,
                        children: actions.map((action) {
                          return _ActionLabel(
                            text: _actionTitle(action),
                            color: _actionColor(action, colorScheme),
                          );
                        }).toList(),
                      ),
                    ),

                    if (dateTime != null) ...[
                      const SizedBox(width: 10),
                      _DateLabel(dateTime: dateTime!),
                    ],
                  ],
                ),

                const SizedBox(height: 11),

                Container(
                  height: 1,
                  color: colorScheme.outlineVariant.withOpacity(.35),
                ),

                // Changes
                ...List.generate(items.length, (index) {
                  return _ChangeRow(
                    item: items[index],
                    isLast: index == items.length - 1,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<String> _uniqueActions(List<Map<String, dynamic>> items) {
    final result = <String>[];

    for (final item in items) {
      final action = item['action']?.toString() ?? '';

      if (action.isEmpty) {
        continue;
      }

      if (!result.contains(action)) {
        result.add(action);
      }
    }

    return result;
  }

  Color _getAccentColor(List<String> actions, ColorScheme colorScheme) {
    if (actions.isEmpty) {
      return colorScheme.primary;
    }

    return _actionColor(actions.first, colorScheme);
  }

  String _actionTitle(String action) {
    switch (action) {
      case 'create':
        return 'ایجاد نامه';

      case 'update':
        return 'ویرایش نامه';

      case 'categories':
        return 'تغییر دسته‌بندی';

      case 'reminder_create':
        return 'ایجاد یادآور';

      case 'reminder_update':
        return 'ویرایش یادآور';

      case 'reminder_complete':
        return 'تکمیل یادآور';

      case 'reminder_cancel':
        return 'لغو یادآور';

      case 'reminder_delete':
        return 'حذف یادآور';

      default:
        return 'تغییر اطلاعات';
    }
  }

  Color _actionColor(String action, ColorScheme colorScheme) {
    switch (action) {
      case 'create':
        return colorScheme.primary;

      case 'update':
        return colorScheme.tertiary;

      case 'categories':
        return colorScheme.secondary;

      case 'reminder_create':
        return colorScheme.primary;

      case 'reminder_update':
        return colorScheme.tertiary;

      case 'reminder_complete':
        return Colors.green.shade600;

      case 'reminder_cancel':
      case 'reminder_delete':
        return colorScheme.error;

      default:
        return colorScheme.primary;
    }
  }
}

// ============================================================================
// Action Label
// ============================================================================

class _ActionLabel extends StatelessWidget {
  final String text;
  final Color color;

  const _ActionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.09),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(.10)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================================
// Date
// ============================================================================
class _DateLabel extends StatelessWidget {
  final DateTime dateTime;

  const _DateLabel({required this.dateTime});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(.55),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(.45)),
      ),
      child: Text(
        _formatDateTime(dateTime),
        textDirection: TextDirection.rtl,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
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
// ============================================================================
// Change Row
// ============================================================================

class _ChangeRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final bool isLast;

  const _ChangeRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final fieldName = item['field_name']?.toString().trim() ?? '';

    final oldValue = item['old_value']?.toString() ?? '';

    final newValue = item['new_value']?.toString() ?? '';

    final hasOld = oldValue.isNotEmpty;
    final hasNew = newValue.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: isLast
          ? null
          : BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colorScheme.outlineVariant.withOpacity(.25),
                ),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fieldName.isNotEmpty)
            Text(
              fieldName,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),

          if (fieldName.isNotEmpty) const SizedBox(height: 6),

          if (hasOld || hasNew)
            _buildValues(context, oldValue, newValue)
          else
            Text(
              'تغییر انجام شد',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildValues(BuildContext context, String oldValue, String newValue) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (oldValue.isNotEmpty)
          _ValueLine(label: 'قبلی', value: oldValue, isOld: true),

        if (oldValue.isNotEmpty && newValue.isNotEmpty)
          const SizedBox(height: 4),

        if (newValue.isNotEmpty)
          _ValueLine(label: 'جدید', value: newValue, isOld: false),
      ],
    );
  }
}

// ============================================================================
// Value Line
// ============================================================================

class _ValueLine extends StatelessWidget {
  final String label;
  final String value;
  final bool isOld;

  const _ValueLine({
    required this.label,
    required this.value,
    required this.isOld,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final color = isOld ? colorScheme.error : colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(.035),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                fontSize: 11.2,
                height: 1.55,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Group Data
// ============================================================================

class _HistoryGroupData {
  final DateTime? dateTime;
  final List<Map<String, dynamic>> items;

  const _HistoryGroupData({required this.dateTime, required this.items});
}
