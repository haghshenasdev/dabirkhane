import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:dabirkhane/services/sync/sync_service.dart';
import 'package:dabirkhane/services/sync_models.dart';

import 'package:dabirkhane/services/backup_restore_service.dart';
import 'package:dabirkhane/utils/app_settings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:shamsi_date/shamsi_date.dart';

class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({super.key});

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  BackupType? _selectedBackupType;

  late int _selectedBackupYear;
  final Set<String> _selectedBackupMonthKeys = <String>{};

  static const List<String> _jalaliMonthNames = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند',
  ];

  bool _working = false;
  double _progress = 0;
  String _progressMessage = '';

  File? _selectedRestoreFile;
  BackupInfo? _restoreInfo;

  // ============================================================
  // Backup / Restore History
  // ============================================================

  DateTime? _lastBackupAt;
  String? _lastBackupType;
  List<String> _lastBackupItems = [];

  DateTime? _lastRestoreAt;
  String? _lastRestoreType;
  List<String> _lastRestoreItems = [];

  bool _loadingHistory = true;

  bool _syncEnabled = false;
  String _syncRole = 'client';
  String _syncKey = '';
  String _syncDeviceName = '';
  String? _syncPeerHost;
  int _syncPeerPort = 39421;
  int _syncPort = 39421;
  DateTime? _syncLastSuccess;
  final TextEditingController _syncHostController = TextEditingController();
  final TextEditingController _syncPortController = TextEditingController();
  final TextEditingController _syncLocalPortController = TextEditingController();
  final TextEditingController _syncNameController = TextEditingController();
  String _localHost = '127.0.0.1';
  final TextEditingController _syncPairingController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 3, vsync: this);

    final previous = _getPreviousMonth();
    _selectedBackupYear = previous.year;
    _selectedBackupMonthKeys.add('${previous.year}/${previous.month}');

    _loadBackupHistory();
    _loadSyncSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _syncHostController.dispose();
    _syncPortController.dispose();
    _syncLocalPortController.dispose();
    _syncNameController.dispose();
    _syncPairingController.dispose();
    super.dispose();
  }

  // ============================================================
  // Load History
  // ============================================================

  Future<void> _loadBackupHistory() async {
    try {
      final backupAt = await AppSettings.getLastBackupAt();

      final backupType = await AppSettings.getLastBackupType();

      final backupItems = await AppSettings.getLastBackupItems();

      final restoreAt = await AppSettings.getLastRestoreAt();

      final restoreType = await AppSettings.getLastRestoreType();

      final restoreItems = await AppSettings.getLastRestoreItems();

      if (!mounted) return;

      setState(() {
        _lastBackupAt = backupAt;
        _lastBackupType = backupType;
        _lastBackupItems = backupItems;

        _lastRestoreAt = restoreAt;
        _lastRestoreType = restoreType;
        _lastRestoreItems = restoreItems;

        _loadingHistory = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadingHistory = false;
      });
    }
  }

  // ============================================================
  // Build
  // ============================================================

  ({int year, int month}) _getPreviousMonth() {
    final now = Jalali.now();
    if (now.month == 1) {
      return (year: now.year - 1, month: 12);
    }
    return (year: now.year, month: now.month - 1);
  }

  List<int> _backupYears() {
    final now = Jalali.now().year;
    return List<int>.generate(12, (index) => now - index);
  }

  String _monthKey(int year, int month) => '$year/$month';

  bool _isMonthSelected(int year, int month) =>
      _selectedBackupMonthKeys.contains(_monthKey(year, month));

  void _toggleBackupMonth(int year, int month) {
    final key = _monthKey(year, month);
    setState(() {
      if (_selectedBackupMonthKeys.contains(key)) {
        if (_selectedBackupMonthKeys.length > 1) {
          _selectedBackupMonthKeys.remove(key);
        }
      } else {
        _selectedBackupMonthKeys.add(key);
      }
    });
  }

  List<BackupMonth> get _selectedBackupMonths {
    final result = <BackupMonth>[];
    for (final key in _selectedBackupMonthKeys) {
      final parts = key.split('/');
      if (parts.length != 2) continue;
      final year = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      if (year != null && month != null) {
        result.add(BackupMonth(year: year, month: month));
      }
    }
    result.sort((a, b) {
      final ay = a.year * 100 + a.month;
      final by = b.year * 100 + b.month;
      return ay.compareTo(by);
    });
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(
                    colorScheme.brightness == Brightness.dark ? .92 : .86,
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: colorScheme.onSurface.withOpacity(.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(.16),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHeader(colorScheme),

                    // وضعیت آخرین عملیات
                    _buildBackupHistory(colorScheme),

                    _buildTabs(colorScheme),

                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBackupTab(colorScheme),
                          _buildRestoreTab(colorScheme),
                          _buildSyncTab(colorScheme),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Header
  // ============================================================

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.primary.withOpacity(.10),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.backup_rounded,
              color: colorScheme.primary,
              size: 25,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'پشتیبان‌گیری و بازیابی',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت امن اطلاعات و فایل‌های دبیرخانه',
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
            onPressed: _working
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // History Card
  // ============================================================

  Widget _buildBackupHistory(ColorScheme colorScheme) {
    if (_loadingHistory) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withOpacity(.55),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'در حال دریافت وضعیت پشتیبان...',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final hasBackup = _lastBackupAt != null;

    final hasRestore = _lastRestoreAt != null;

    if (!hasBackup && !hasRestore) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow.withOpacity(.55),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(.30),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'هنوز عملیات پشتیبان‌گیری یا بازیابی ثبت نشده است.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow.withOpacity(.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colorScheme.outlineVariant.withOpacity(.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 19,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 7),
                Text(
                  'آخرین وضعیت پشتیبان',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            if (hasBackup)
              _buildHistoryRow(
                colorScheme,
                icon: Icons.upload_rounded,
                iconColor: colorScheme.primary,
                title: 'آخرین پشتیبان‌گیری',
                dateTime: _lastBackupAt!,
                type: _lastBackupType,
                items: _lastBackupItems,
              ),

            if (hasBackup && hasRestore) const SizedBox(height: 9),

            if (hasRestore)
              _buildHistoryRow(
                colorScheme,
                icon: Icons.download_rounded,
                iconColor: colorScheme.secondary,
                title: 'آخرین بازیابی',
                dateTime: _lastRestoreAt!,
                type: _lastRestoreType,
                items: _lastRestoreItems,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow(
    ColorScheme colorScheme, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required DateTime dateTime,
    required String? type,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(.45),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      _formatJalaliDateTime(dateTime),
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                Text(
                  _historyTypeLabel(type),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: items
                      .map((item) => _buildHistoryChip(colorScheme, item))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryChip(ColorScheme colorScheme, String item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 13, color: colorScheme.primary),
          const SizedBox(width: 3),
          Text(
            _historyItemLabel(item),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  String _historyTypeLabel(String? type) {
    switch (type) {
      case 'database':
        return 'نوع: فقط دیتابیس';

      case 'files':
        return 'نوع: فقط فایل‌های ماه قبل';

      case 'full':
        return 'نوع: دیتابیس + فایل‌های ماه قبل';

      default:
        return 'نوع: نامشخص';
    }
  }

  String _historyItemLabel(String item) {
    switch (item) {
      case 'database':
        return 'دیتابیس';

      case 'files':
        return 'فایل‌های ماه قبل';

      default:
        return item;
    }
  }

  String _formatJalaliDateTime(DateTime dateTime) {
    final jalali = Jalali.fromDateTime(dateTime);

    final year = jalali.year.toString();

    final month = jalali.month.toString().padLeft(2, '0');

    final day = jalali.day.toString().padLeft(2, '0');

    final hour = dateTime.hour.toString().padLeft(2, '0');

    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '$year/$month/$day - $hour:$minute';
  }

  // ============================================================
  // Tabs
  // ============================================================

  Widget _buildTabs(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(.55),
        borderRadius: BorderRadius.circular(15),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: colorScheme.primary.withOpacity(.12),
          borderRadius: BorderRadius.circular(12),
        ),
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        tabs: const [
          Tab(icon: Icon(Icons.upload_rounded, size: 19), text: 'پشتیبان‌گیری'),
          Tab(icon: Icon(Icons.download_rounded, size: 19), text: 'بازیابی'),
          Tab(icon: Icon(Icons.sync_rounded, size: 19), text: 'هماهنگ‌سازی'),
        ],
      ),
    );
  }

  // ============================================================
  // Backup Tab
  // ============================================================
  Widget _buildBackupTab(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              children: [
                _buildSectionIntro(
                  colorScheme,
                  icon: Icons.cloud_upload_outlined,
                  title: 'نوع پشتیبان را انتخاب کنید',
                  description:
                      'برای پشتیبان‌گیری می‌توانید فقط دیتابیس، '
                      'فایل‌های یک ماه دلخواه یا هر دو را انتخاب کنید.',
                ),

                const SizedBox(height: 14),

                _buildBackupMonthSelector(colorScheme),

                const SizedBox(height: 14),

                _buildBackupOption(
                  colorScheme,
                  type: BackupType.database,
                  icon: Icons.storage_rounded,
                  title: 'فقط دیتابیس',
                  description:
                      'تمام اطلاعات ثبت‌شده، دسته‌بندی‌ها، '
                      'یادآورها و تاریخچه تغییرات',
                ),

                const SizedBox(height: 10),

                _buildBackupOption(
                  colorScheme,
                  type: BackupType.previousMonthFiles,
                  icon: Icons.folder_zip_rounded,
                  title: 'فقط فایل‌های ماه قبل',
                  description: 'فایل‌های نامه‌های ماه قبل به صورت ZIP',
                ),

                const SizedBox(height: 10),

                _buildBackupOption(
                  colorScheme,
                  type: BackupType.full,
                  icon: Icons.inventory_2_rounded,
                  title: 'دیتابیس + فایل‌های ماه قبل',
                  description:
                      'پشتیبان کامل شامل دیتابیس و فایل‌های ماه انتخاب‌شده در یک ZIP',
                ),

                const SizedBox(height: 18),

                _buildProgress(colorScheme),

                // کمی فاصله از دکمه ثابت پایین
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ========================================================
        // دکمه ثابت پایین
        // ========================================================
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(.30),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _working || _selectedBackupType == null
                  ? null
                  : _startBackup,
              icon: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.backup_rounded),
              label: Text(
                _working ? 'در حال ایجاد پشتیبان...' : 'شروع پشتیبان‌گیری',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackupMonthSelector(ColorScheme colorScheme) {
    final selectedMonths = _selectedBackupMonths;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(.055),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.primary.withOpacity(.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('ماه فایل‌ها', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              DropdownButton<int>(
                value: _selectedBackupYear,
                underline: const SizedBox.shrink(),
                items: _backupYears().map((year) => DropdownMenuItem(
                  value: year,
                  child: Text(year.toString()),
                )).toList(),
                onChanged: _working ? null : (value) {
                  if (value != null) setState(() => _selectedBackupYear = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'یک یا چند ماه را انتخاب کنید. برای انتخاب ماه‌های سال‌های دیگر، سال را تغییر دهید؛ انتخاب‌های قبلی باقی می‌مانند.',
            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: List.generate(12, (index) {
              final month = index + 1;
              final selected = _isMonthSelected(_selectedBackupYear, month);
              return FilterChip(
                selected: selected,
                label: Text(_jalaliMonthNames[index]),
                avatar: selected ? const Icon(Icons.check_rounded, size: 16) : null,
                onSelected: _working
                    ? null
                    : (_) => _toggleBackupMonth(_selectedBackupYear, month),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.checklist_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 7),
              Text('ماه‌های انتخاب‌شده: ${selectedMonths.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          if (selectedMonths.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectedMonths.map((m) => InputChip(
                label: Text('${m.year}/${m.month}'),
                onDeleted: _working || selectedMonths.length == 1
                    ? null
                    : () => _toggleBackupMonth(m.year, m.month),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBackupOption(
    ColorScheme colorScheme, {
    required BackupType type,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = _selectedBackupType == type;

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _working
          ? null
          : () {
              setState(() {
                _selectedBackupType = type;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withOpacity(.09)
              : colorScheme.surfaceContainerHigh.withOpacity(.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary.withOpacity(.35)
                : colorScheme.outlineVariant.withOpacity(.35),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary.withOpacity(.13)
                    : colorScheme.surfaceContainerHighest.withOpacity(.65),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? colorScheme.primary : colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSyncSettings() async {
    final enabled = await AppSettings.getSyncEnabled();
    final role = await AppSettings.getSyncRole();
    final key = await AppSettings.getSyncKey();
    final name = await AppSettings.getSyncDeviceName();
    final host = await AppSettings.getSyncPeerHost();
    final peerPort = await AppSettings.getSyncPeerPort();
    final port = await AppSettings.getSyncPort();
    final last = await AppSettings.getSyncLastSuccess();
    if (!mounted) return;
    _syncHostController.text = host ?? '';
    _syncPortController.text = peerPort.toString();
    _syncLocalPortController.text = port.toString();
    _syncNameController.text = name;
    final localHost = await _findLocalHost();
    if (!mounted) return;
    setState(() {
      _syncEnabled = enabled;
      _syncRole = role;
      _syncKey = key;
      _syncDeviceName = name;
      _syncPeerHost = host;
      _syncPeerPort = peerPort;
      _syncPort = port;
      _syncLastSuccess = last;
      _localHost = localHost;
    });
  }

  String _pairingText() => 'DABIRKHANE-SYNC|$_localHost|$_syncPort|$_syncKey';

  Future<String> _findLocalHost() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final i in interfaces) {
        for (final a in i.addresses) {
          if (!a.isLoopback && a.address.isNotEmpty) return a.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> _saveSyncSettings() async {
    final port = int.tryParse(_syncLocalPortController.text.trim()) ?? _syncPort;
    final peerPort = int.tryParse(_syncPortController.text.trim()) ?? _syncPeerPort;
    await AppSettings.setSyncEnabled(_syncEnabled);
    await AppSettings.setSyncRole(_syncRole);
    await AppSettings.setSyncDeviceName(_syncDeviceName.trim().isEmpty ? 'دبیرخانه' : _syncDeviceName.trim());
    await AppSettings.setSyncPort(port.clamp(1024, 65535).toInt());
    await AppSettings.setSyncPeerPort(peerPort.clamp(1024, 65535).toInt());
    await AppSettings.setSyncPeerHost(_syncHostController.text.trim());
    if (_syncEnabled) {
      await SyncService.instance.start();
    } else {
      await SyncService.instance.stop();
    }
    await _loadSyncSettings();
  }

  Future<void> _applyPairingCode() async {
    final value = _syncPairingController.text.trim();
    final parts = value.split('|');
    if (parts.length < 4 || parts[0] != 'DABIRKHANE-SYNC') {
      await _showResult(title: 'کد نامعتبر', message: 'کد اتصال دبیرخانه معتبر نیست.', success: false);
      return;
    }
    final host = parts[1];
    final port = int.tryParse(parts[2]);
    final key = parts.sublist(3).join('|');
    if (host.isEmpty || port == null || key.isEmpty) {
      await _showResult(title: 'کد نامعتبر', message: 'اطلاعات اتصال ناقص است.', success: false);
      return;
    }
    await AppSettings.setSyncPeerHost(host);
    await AppSettings.setSyncPeerPort(port);
    await AppSettings.setSyncKey(key);
    await AppSettings.setSyncEnabled(true);
    await _loadSyncSettings();
    await SyncService.instance.start();
    await SyncService.instance.syncNow();
  }

  Widget _buildSyncTab(ColorScheme colorScheme) {
    return AnimatedBuilder(
      animation: SyncService.statusNotifier,
      builder: (context, _) {
        final status = SyncService.statusNotifier.value;
        final statusColor = switch (status) {
          SyncStatus.connected => Colors.green,
          SyncStatus.syncing || SyncStatus.connecting => Colors.orange,
          SyncStatus.error => colorScheme.error,
          SyncStatus.disconnected => colorScheme.outline,
        };
        final statusText = switch (status) {
          SyncStatus.connected => 'متصل و هماهنگ',
          SyncStatus.syncing => 'در حال ارسال و دریافت اطلاعات...',
          SyncStatus.connecting => 'در حال اتصال...',
          SyncStatus.error => 'اتصال ناموفق',
          SyncStatus.disconnected => 'غیرفعال یا بدون اتصال',
        };
        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Column(
                  children: [
                    _buildSectionIntro(colorScheme, icon: Icons.sync_rounded, title: 'هماهنگ‌سازی امن بین دو دبیرخانه', description: 'هر دستگاه دیتابیس محلی خودش را دارد و فقط تغییرات و فایل‌های جدید بین دو دستگاه جابه‌جا می‌شوند.'),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: statusColor.withOpacity(.08), borderRadius: BorderRadius.circular(17), border: Border.all(color: statusColor.withOpacity(.22))),
                      child: Row(children: [Icon(Icons.circle, size: 12, color: statusColor), const SizedBox(width: 9), Expanded(child: Text(statusText, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))), if (status == SyncStatus.syncing || status == SyncStatus.connecting) const SizedBox(width: 14, child: CircularProgressIndicator(strokeWidth: 2))]),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      title: const Text('فعال‌سازی هماهنگ‌سازی', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      subtitle: const Text('ارتباط فقط با کلید امنیتی ثبت‌شده پذیرفته می‌شود.', style: TextStyle(fontSize: 11)),
                      value: _syncEnabled,
                      onChanged: (v) => setState(() => _syncEnabled = v),
                    ),
                    const SizedBox(height: 6),
                    _syncField(label: 'نام این دستگاه', value: _syncDeviceName, onChanged: (v) => _syncDeviceName = v, colorScheme: colorScheme, controller: _syncNameController),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _syncRole,
                      decoration: const InputDecoration(labelText: 'نقش دستگاه', border: OutlineInputBorder()),
                      items: const [DropdownMenuItem(value: 'master', child: Text('اصلی / مادر — مرجع شماره نامه')), DropdownMenuItem(value: 'client', child: Text('دستگاه دوم / متصل'))],
                      onChanged: (v) => setState(() => _syncRole = v ?? 'client'),
                    ),
                    const SizedBox(height: 10),
                    if (_syncRole == 'master') ...[
                      _buildKeyCard(colorScheme),
                      const SizedBox(height: 10),
                      _syncField(label: 'پورت این دستگاه', value: _syncPort.toString(), onChanged: (v) => _syncLocalPortController.text = v, colorScheme: colorScheme, controller: _syncLocalPortController),
                    ] else ...[
                      _syncField(label: 'IP یا نام دستگاه مادر', value: _syncHostController.text, onChanged: (v) => _syncHostController.text = v, colorScheme: colorScheme, controller: _syncHostController),
                      const SizedBox(height: 10),
                      _syncField(label: 'پورت مادر', value: _syncPeerPort.toString(), onChanged: (v) => _syncPortController.text = v, colorScheme: colorScheme, controller: _syncPortController),
                      const SizedBox(height: 10),
                      TextField(controller: _syncPairingController, maxLines: 3, decoration: InputDecoration(labelText: 'کد جفت‌سازی مادر', hintText: 'DABIRKHANE-SYNC|IP|PORT|KEY', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.paste_rounded), onPressed: () async { final d = await Clipboard.getData('text/plain'); if (d?.text != null) _syncPairingController.text = d!.text!; })),),
                      const SizedBox(height: 8),
                      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _applyPairingCode, icon: const Icon(Icons.link_rounded), label: const Text('اعمال کد و اتصال'))),
                    ],
                    if (_syncLastSuccess != null) Padding(padding: const EdgeInsets.only(top: 8), child: Align(alignment: Alignment.centerRight, child: Text('آخرین هماهنگی موفق: ${_syncLastSuccess!.toLocal()}', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)))),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant.withOpacity(.30)))),
              child: Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: _pairingText())); await _showResult(title: 'کد اتصال', message: 'کد اتصال کپی شد. آن را در دستگاه دوم وارد کنید.', success: true); }, icon: const Icon(Icons.copy_rounded), label: const Text('کپی کد اتصال'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: _working ? null : () async { await _saveSyncSettings(); await SyncService.instance.syncNow(); }, icon: const Icon(Icons.sync_rounded), label: const Text('ذخیره و هماهنگ‌سازی')))]),
            ),
          ],
        );
      },
    );
  }

  Widget _syncField({required String label, required String value, required ValueChanged<String> onChanged, required ColorScheme colorScheme, required TextEditingController controller}) {
    return TextField(controller: controller, onChanged: onChanged, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true));
  }

  Widget _buildKeyCard(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: colorScheme.primary.withOpacity(.06), borderRadius: BorderRadius.circular(17), border: Border.all(color: colorScheme.primary.withOpacity(.18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('کلید امنیتی این دستگاه', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)), const SizedBox(height: 7), SelectableText(_syncKey, style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')), const SizedBox(height: 7), Text('کد کامل اتصال برای دستگاه دوم:', style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant)), const SizedBox(height: 3), SelectableText(_pairingText(), style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'))]));
  }

  // ============================================================
  // Restore Tab
  // ============================================================

  Widget _buildRestoreTab(ColorScheme colorScheme) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              children: [
                _buildSectionIntro(
                  colorScheme,
                  icon: Icons.cloud_download_outlined,
                  title: 'بازیابی خودکار',
                  description:
                      'فایل پشتیبان را انتخاب کنید؛ نوع آن به صورت '
                      'خودکار تشخیص داده می‌شود.',
                ),

                const SizedBox(height: 16),

                _buildRestorePicker(colorScheme),

                const SizedBox(height: 14),

                if (_restoreInfo != null) _buildRestoreInfo(colorScheme),

                const SizedBox(height: 18),

                _buildProgress(colorScheme),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ========================================================
        // دکمه ثابت پایین
        // ========================================================
        Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              top: BorderSide(
                color: colorScheme.outlineVariant.withOpacity(.30),
              ),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _working || _selectedRestoreFile == null
                  ? null
                  : _startRestore,
              icon: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restore_rounded),
              label: Text(_working ? 'در حال بازیابی...' : 'شروع بازیابی'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRestorePicker(ColorScheme colorScheme) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _working ? null : _selectRestoreFile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        decoration: BoxDecoration(
          color: colorScheme.primary.withOpacity(.055),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.primary.withOpacity(.20)),
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(.10),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_open_rounded,
                size: 29,
                color: colorScheme.primary,
              ),
            ),

            const SizedBox(height: 12),

            Text(
              _selectedRestoreFile == null
                  ? 'انتخاب فایل پشتیبان'
                  : path.basename(_selectedRestoreFile!.path),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),

            const SizedBox(height: 6),

            Text(
              'فایل‌های SQLite یا ZIP',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreInfo(ColorScheme colorScheme) {
    final info = _restoreInfo!;

    IconData icon;

    switch (info.type) {
      case BackupContentType.database:
        icon = Icons.storage_rounded;
        break;

      case BackupContentType.files:
        icon = Icons.folder_zip_rounded;
        break;

      case BackupContentType.full:
        icon = Icons.inventory_2_rounded;
        break;

      case BackupContentType.unknown:
        icon = Icons.help_outline_rounded;
        break;
    }

    final valid = info.type != BackupContentType.unknown;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: valid
            ? colorScheme.primary.withOpacity(.06)
            : colorScheme.error.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: valid
              ? colorScheme.primary.withOpacity(.18)
              : colorScheme.error.withOpacity(.18),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: valid ? colorScheme.primary : colorScheme.error),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Section Intro
  // ============================================================

  Widget _buildSectionIntro(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withOpacity(.55),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary, size: 25),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Progress
  // ============================================================

  Widget _buildProgress(ColorScheme colorScheme) {
    if (!_working) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(.055),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _progressMessage,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(_progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Start Backup
  // ============================================================

  Future<void> _startBackup() async {
    final type = _selectedBackupType;

    if (type == null || _working) {
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _progressMessage = 'در حال آماده‌سازی...';
    });

    final result = await BackupRestoreService.createBackup(
      type: type,
      selectedYear: _selectedBackupYear,
      selectedMonth: _selectedBackupMonths.first.month,
      selectedMonths: _selectedBackupMonths,
      onProgress: (progress, message) {
        if (!mounted) return;

        setState(() {
          _progress = progress;
          _progressMessage = message;
        });
      },
    );

    if (!mounted) return;

    setState(() {
      _working = false;
      _progress = result.success ? 1 : 0;
      _progressMessage = result.message;
    });

    if (result.success) {
      // اطلاعات از SharedPreferences دوباره خوانده می‌شود
      await _loadBackupHistory();

      await _showResult(
        title: 'پشتیبان‌گیری',
        message: result.message,
        success: true,
      );
    } else if (result.message != 'عملیات لغو شد.') {
      await _showResult(
        title: 'پشتیبان‌گیری',
        message: result.message,
        success: false,
      );
    }
  }

  // ============================================================
  // Select Restore
  // ============================================================

  Future<void> _selectRestoreFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db', 'zip'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final selectedPath = result.files.single.path;

    if (selectedPath == null || selectedPath.isEmpty) {
      return;
    }

    final file = File(selectedPath);

    setState(() {
      _selectedRestoreFile = file;
      _restoreInfo = null;
    });

    final info = await BackupRestoreService.inspectBackup(file);

    if (!mounted) return;

    setState(() {
      _restoreInfo = info;
    });
  }

  // ============================================================
  // Start Restore
  // ============================================================

  Future<void> _startRestore() async {
    final file = _selectedRestoreFile;

    if (file == null || _working) {
      return;
    }

    final info = _restoreInfo;

    if (info == null || info.type == BackupContentType.unknown) {
      await _showResult(
        title: 'بازیابی',
        message: 'نوع فایل پشتیبان قابل تشخیص نیست.',
        success: false,
      );
      return;
    }

    final confirmed = await _confirmRestore(info);

    if (!confirmed) {
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _progressMessage = 'در حال شروع بازیابی...';
    });

    final result = await BackupRestoreService.restoreBackup(
      file,
      onProgress: (progress, message) {
        if (!mounted) return;

        setState(() {
          _progress = progress;
          _progressMessage = message;
        });
      },
    );

    if (!mounted) return;

    setState(() {
      _working = false;
      _progress = result.success ? 1 : 0;
      _progressMessage = result.message;
    });

    await _showResult(
      title: result.success ? 'بازیابی موفق' : 'خطا در بازیابی',
      message: result.message,
      success: result.success,
    );

    if (result.success && mounted) {
      await _loadBackupHistory();

      Navigator.of(context).pop(true);
    }
  }

  // ============================================================
  // Confirm Restore
  // ============================================================

  Future<bool> _confirmRestore(BackupInfo info) async {
    final colorScheme = Theme.of(context).colorScheme;

    return await showDialog<bool>(
          context: context,
          builder: (_) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: const Text('تأیید بازیابی'),
                content: Text(
                  '${info.title}\n\n'
                  '${info.description}\n\n'
                  'در صورت وجود دیتابیس، دیتابیس فعلی قبل از '
                  'جایگزینی در فایل .backup ذخیره خواهد شد.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context, false);
                    },
                    child: const Text('انصراف'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.error,
                    ),
                    onPressed: () {
                      Navigator.pop(context, true);
                    },
                    child: const Text('بله، بازیابی کن'),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  // ============================================================
  // Result Dialog
  // ============================================================

  Future<void> _showResult({
    required String title,
    required String message,
    required bool success,
  }) async {
    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (_) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(
                  success ? Icons.check_circle_outline : Icons.error_outline,
                  color: success ? colorScheme.primary : colorScheme.error,
                ),
                const SizedBox(width: 9),
                Text(title),
              ],
            ),
            content: Text(message),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('باشه'),
              ),
            ],
          ),
        );
      },
    );
  }
}
