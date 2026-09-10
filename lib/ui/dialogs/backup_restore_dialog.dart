import 'dart:io';
import 'dart:ui';

import 'package:dabirkhane/services/backup_restore_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;


class BackupRestoreDialog extends StatefulWidget {
  const BackupRestoreDialog({
    super.key,
  });

  @override
  State<BackupRestoreDialog> createState() =>
      _BackupRestoreDialogState();
}

class _BackupRestoreDialogState
    extends State<BackupRestoreDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  BackupType? _selectedBackupType;

  bool _working = false;
  double _progress = 0;
  String _progressMessage = '';

  File? _selectedRestoreFile;
  BackupInfo? _restoreInfo;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 22,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 720,
            maxHeight: 760,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 20,
                sigmaY: 20,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surface.withOpacity(
                    colorScheme.brightness ==
                            Brightness.dark
                        ? .92
                        : .86,
                  ),
                  borderRadius:
                      BorderRadius.circular(30),
                  border: Border.all(
                    color: colorScheme.onSurface
                        .withOpacity(.10),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow
                          .withOpacity(.16),
                      blurRadius: 40,
                      offset:
                          const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHeader(colorScheme),
                    _buildTabs(colorScheme),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildBackupTab(
                            colorScheme,
                          ),
                          _buildRestoreTab(
                            colorScheme,
                          ),
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

  Widget _buildHeader(
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        14,
        14,
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.primary
                  .withOpacity(.10),
              borderRadius:
                  BorderRadius.circular(16),
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
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  'پشتیبان‌گیری و بازیابی',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'مدیریت امن اطلاعات و فایل‌های دبیرخانه',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme
                        .onSurfaceVariant,
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
            icon: const Icon(
              Icons.close_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(
    ColorScheme colorScheme,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest
            .withOpacity(.55),
        borderRadius:
            BorderRadius.circular(15),
      ),
      child: TabBar(
        controller: _tabController,
        dividerColor: Colors.transparent,
        indicatorSize:
            TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: colorScheme.primary
              .withOpacity(.12),
          borderRadius:
              BorderRadius.circular(12),
        ),
        labelColor: colorScheme.primary,
        unselectedLabelColor:
            colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        tabs: const [
          Tab(
            icon: Icon(
              Icons.upload_rounded,
              size: 19,
            ),
            text: 'پشتیبان‌گیری',
          ),
          Tab(
            icon: Icon(
              Icons.download_rounded,
              size: 19,
            ),
            text: 'بازیابی',
          ),
        ],
      ),
    );
  }

  Widget _buildBackupTab(
    ColorScheme colorScheme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        24,
      ),
      child: Column(
        children: [
          _buildSectionIntro(
            colorScheme,
            icon: Icons.cloud_upload_outlined,
            title: 'نوع پشتیبان را انتخاب کنید',
            description:
                'برای پشتیبان‌گیری می‌توانید فقط دیتابیس، '
                'فایل‌های ماه قبل یا هر دو را انتخاب کنید.',
          ),
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
            description:
                'فایل‌های نامه‌های ماه قبل به صورت ZIP',
          ),
          const SizedBox(height: 10),
          _buildBackupOption(
            colorScheme,
            type: BackupType.full,
            icon: Icons.inventory_2_rounded,
            title: 'دیتابیس + فایل‌های ماه قبل',
            description:
                'پشتیبان کامل شامل دیتابیس و فایل‌های ماه قبل در یک ZIP',
          ),
          const SizedBox(height: 18),
          _buildProgress(colorScheme),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed:
                  _working || _selectedBackupType == null
                      ? null
                      : _startBackup,
              icon: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.backup_rounded,
                    ),
              label: Text(
                _working
                    ? 'در حال ایجاد پشتیبان...'
                    : 'شروع پشتیبان‌گیری',
              ),
            ),
          ),
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
    final selected =
        _selectedBackupType == type;

    return InkWell(
      borderRadius:
          BorderRadius.circular(18),
      onTap: _working
          ? null
          : () {
              setState(() {
                _selectedBackupType = type;
              });
            },
      child: AnimatedContainer(
        duration:
            const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
                  .withOpacity(.09)
              : colorScheme
                  .surfaceContainerHigh
                  .withOpacity(.55),
          borderRadius:
              BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? colorScheme.primary
                    .withOpacity(.35)
                : colorScheme.outlineVariant
                    .withOpacity(.35),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(
                milliseconds: 180,
              ),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary
                        .withOpacity(.13)
                    : colorScheme
                        .surfaceContainerHighest
                        .withOpacity(.65),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                color: selected
                    ? colorScheme.primary
                    : colorScheme
                        .onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          FontWeight.w800,
                      color:
                          colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outline,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreTab(
    ColorScheme colorScheme,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        18,
        18,
        18,
        24,
      ),
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
          _buildRestorePicker(
            colorScheme,
          ),
          const SizedBox(height: 14),
          if (_restoreInfo != null)
            _buildRestoreInfo(
              colorScheme,
            ),
          const SizedBox(height: 18),
          _buildProgress(colorScheme),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed:
                  _working ||
                          _selectedRestoreFile ==
                              null
                      ? null
                      : _startRestore,
              icon: _working
                  ? const SizedBox(
                      width: 19,
                      height: 19,
                      child:
                          CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.restore_rounded,
                    ),
              label: Text(
                _working
                    ? 'در حال بازیابی...'
                    : 'شروع بازیابی',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestorePicker(
    ColorScheme colorScheme,
  ) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(20),
      onTap: _working
          ? null
          : _selectRestoreFile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 25,
        ),
        decoration: BoxDecoration(
          color: colorScheme.primary
              .withOpacity(.055),
          borderRadius:
              BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.primary
                .withOpacity(.20),
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: colorScheme.primary
                    .withOpacity(.10),
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
                  : path.basename(
                      _selectedRestoreFile!
                          .path,
                    ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'فایل‌های SQLite یا ZIP',
              style: TextStyle(
                fontSize: 11.5,
                color: colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestoreInfo(
    ColorScheme colorScheme,
  ) {
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

    final valid =
        info.type != BackupContentType.unknown;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: valid
            ? colorScheme.primary
                .withOpacity(.06)
            : colorScheme.error
                .withOpacity(.06),
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: valid
              ? colorScheme.primary
                  .withOpacity(.18)
              : colorScheme.error
                  .withOpacity(.18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: valid
                ? colorScheme.primary
                : colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  info.title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info.description,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionIntro(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme
            .surfaceContainerLow
            .withOpacity(.55),
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color: colorScheme.outlineVariant
              .withOpacity(.35),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: colorScheme.primary,
            size: 25,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(
    ColorScheme colorScheme,
  ) {
    if (!_working) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colorScheme.primary
            .withOpacity(.055),
        borderRadius:
            BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _progressMessage,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(_progress * 100).round()}%',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      FontWeight.w800,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius:
                BorderRadius.circular(20),
            child:
                LinearProgressIndicator(
              value: _progress <= 0
                  ? null
                  : _progress,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startBackup() async {
    final type = _selectedBackupType;

    if (type == null || _working) {
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _progressMessage =
          'در حال آماده‌سازی...';
    });

    final result =
        await BackupRestoreService.createBackup(
      type: type,
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
      _progressMessage =
          result.message;
    });

    if (result.success) {
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

  Future<void> _selectRestoreFile() async {
    final result =
        await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'sqlite',
        'db',
        'zip',
      ],
      allowMultiple: false,
    );

    if (result == null ||
        result.files.isEmpty) {
      return;
    }

    final selectedPath =
        result.files.single.path;

    if (selectedPath == null ||
        selectedPath.isEmpty) {
      return;
    }

    final file = File(selectedPath);

    setState(() {
      _selectedRestoreFile = file;
      _restoreInfo = null;
    });

    final info =
        await BackupRestoreService.inspectBackup(
      file,
    );

    if (!mounted) return;

    setState(() {
      _restoreInfo = info;
    });
  }

  Future<void> _startRestore() async {
    final file = _selectedRestoreFile;

    if (file == null || _working) {
      return;
    }

    final info = _restoreInfo;

    if (info == null ||
        info.type ==
            BackupContentType.unknown) {
      await _showResult(
        title: 'بازیابی',
        message:
            'نوع فایل پشتیبان قابل تشخیص نیست.',
        success: false,
      );
      return;
    }

    final confirmed =
        await _confirmRestore(info);

    if (!confirmed) {
      return;
    }

    setState(() {
      _working = true;
      _progress = 0;
      _progressMessage =
          'در حال شروع بازیابی...';
    });

    final result =
        await BackupRestoreService.restoreBackup(
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
      _progressMessage =
          result.message;
    });

    await _showResult(
      title: result.success
          ? 'بازیابی موفق'
          : 'خطا در بازیابی',
      message: result.message,
      success: result.success,
    );

    if (result.success && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<bool> _confirmRestore(
    BackupInfo info,
  ) async {
    final colorScheme =
        Theme.of(context).colorScheme;

    return await showDialog<bool>(
          context: context,
          builder: (_) {
            return Directionality(
              textDirection:
                  TextDirection.rtl,
              child: AlertDialog(
                title: const Text(
                  'تأیید بازیابی',
                ),
                content: Text(
                  '${info.title}\n\n'
                  '${info.description}\n\n'
                  'در صورت وجود دیتابیس، دیتابیس فعلی قبل از '
                  'جایگزینی در فایل .backup ذخیره خواهد شد.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                        false,
                      );
                    },
                    child:
                        const Text('انصراف'),
                  ),
                  FilledButton(
                    style:
                        FilledButton.styleFrom(
                      backgroundColor:
                          colorScheme.error,
                    ),
                    onPressed: () {
                      Navigator.pop(
                        context,
                        true,
                      );
                    },
                    child:
                        const Text('بله، بازیابی کن'),
                  ),
                ],
              ),
            );
          },
        ) ??
        false;
  }

  Future<void> _showResult({
    required String title,
    required String message,
    required bool success,
  }) async {
    if (!mounted) return;

    final colorScheme =
        Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      builder: (_) {
        return Directionality(
          textDirection:
              TextDirection.rtl,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(
                  success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  color: success
                      ? colorScheme.primary
                      : colorScheme.error,
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