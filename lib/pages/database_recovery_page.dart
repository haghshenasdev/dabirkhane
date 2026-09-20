import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db/database_helper.dart';

class DatabaseRecoveryPage extends StatefulWidget {
  final Object error;
  final StackTrace? stackTrace;
  final Future<void> Function() onRetry;

  const DatabaseRecoveryPage({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  @override
  State<DatabaseRecoveryPage> createState() => _DatabaseRecoveryPageState();
}

class _DatabaseRecoveryPageState extends State<DatabaseRecoveryPage> {
  bool busy = false;
  String? status;
  Map<String, dynamic>? diagnostics;
  String? automaticBackupPath;

  String get errorText => widget.error.toString();

  String get diagnosticText {
    final buffer = StringBuffer()
      ..writeln('دبیرخانه - گزارش خطای دیتابیس')
      ..writeln('زمان: ${DateTime.now().toIso8601String()}')
      ..writeln('مسیر دیتابیس: ${diagnostics?['path'] ?? 'نامشخص'}')
      ..writeln('خطا:')
      ..writeln(errorText)
      ..writeln()
      ..writeln('StackTrace:')
      ..writeln(widget.stackTrace?.toString() ?? 'در دسترس نیست');

    if (diagnostics != null) {
      buffer
        ..writeln()
        ..writeln('Diagnostics:')
        ..writeln(JsonEncoder.withIndent('  ').convert(diagnostics));
    }

    return buffer.toString();
  }

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    try {
      final value = await DatabaseHelper.getDiagnostics();
      final dbPath = value['path']?.toString();
      final backupPath =
          dbPath == null ? null : '$dbPath.backup';
      if (!mounted) return;
      setState(() {
        diagnostics = value;
        automaticBackupPath =
            backupPath != null && File(backupPath).existsSync()
                ? backupPath
                : null;
      });
    } catch (_) {}
  }

  Future<void> _run(Future<void> Function() action) async {
    if (busy) return;

    setState(() {
      busy = true;
      status = null;
    });

    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() => status = 'خطا:\n$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copyDiagnostics() async {
    await Clipboard.setData(ClipboardData(text: diagnosticText));
    if (!mounted) return;
    setState(() => status = 'گزارش خطا در کلیپ‌بورد کپی شد.');
  }

  Future<void> _saveDiagnostics() async {
    await _run(() async {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره گزارش خطای دبیرخانه',
        fileName: 'dabirkhane_database_error.txt',
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (target == null) return;
      await File(target).writeAsString(diagnosticText, flush: true);

      if (!mounted) return;
      setState(() => status = 'گزارش خطا ذخیره شد.');
    });
  }

  Future<void> _backupDatabase() async {
    await _run(() async {
      final target = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیره نسخه خام دیتابیس',
        fileName: 'dabirkhane_database_backup.sqlite',
        type: FileType.custom,
        allowedExtensions: ['sqlite', 'db'],
      );

      if (target == null) return;

      await DatabaseHelper.backupRawDatabase(File(target));

      if (!mounted) return;
      setState(() => status = 'نسخه پشتیبان دیتابیس ذخیره شد.');
    });
  }

  Future<void> _restoreDatabase() async {
    final selected = await FilePicker.platform.pickFiles(
      dialogTitle: 'انتخاب نسخه سالم دیتابیس',
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db', 'backup'],
      allowMultiple: false,
    );

    if (selected == null || selected.files.single.path == null) return;

    final file = File(selected.files.single.path!);

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('بازیابی دیتابیس'),
            content: const Text(
              'قبل از جایگزینی، نسخه فعلی دیتابیس با پسوند recovery ذخیره می‌شود.\n\n'
              'آیا می‌خواهید دیتابیس انتخاب‌شده جایگزین شود؟',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('جایگزین کن'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _run(() async {
      await DatabaseHelper.replaceDatabaseFile(file);

      if (!mounted) return;
      setState(() => status = 'دیتابیس جایگزین شد. در حال بررسی...');
      await widget.onRetry();
    });
  }

  Future<void> _restoreAutomaticBackup() async {
    final backupPath = automaticBackupPath;
    if (backupPath == null) return;

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('بازگردانی نسخه خودکار'),
            content: const Text(
              'یک فایل .backup از نسخه قبلی دیتابیس پیدا شد. '
              'آیا همین نسخه جایگزین شود؟',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('بازیابی'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await _run(() async {
      await DatabaseHelper.replaceDatabaseFile(File(backupPath));
      if (!mounted) return;
      setState(() => status = 'نسخه خودکار جایگزین شد. در حال بررسی...');
      await widget.onRetry();
    });
  }

  Future<void> _retry() async {
    await _run(() async {
      await widget.onRetry();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = diagnostics?['path']?.toString();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('بازیابی و عیب‌یابی دیتابیس'),
          automaticallyImplyLeading: false,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.storage_rounded,
                          size: 54,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'دیتابیس با موفقیت باز نشد',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'اطلاعات نامه‌ها حذف نشده است. ابتدا می‌توانید دوباره تلاش کنید یا از فایل دیتابیس نسخه پشتیبان بگیرید. '
                          'در صورت داشتن نسخه سالم، آن را بازیابی کنید.',
                          textAlign: TextAlign.center,
                        ),
                        if (path != null) ...[
                          const SizedBox(height: 14),
                          SelectableText(
                            path,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.error_outline_rounded),
                    title: const Text('جزئیات خطا'),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      SelectableText(
                        errorText,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 12),
                      ExpansionTile(
                        title: const Text('StackTrace'),
                        children: [
                          SelectableText(
                            widget.stackTrace?.toString() ?? 'موجود نیست',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('بررسی فنی دیتابیس'),
                    childrenPadding: const EdgeInsets.all(16),
                    children: [
                      if (diagnostics == null)
                        const CircularProgressIndicator()
                      else
                        SelectableText(
                          JsonEncoder.withIndent('  ')
                              .convert(diagnostics),
                          textDirection: TextDirection.ltr,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (status != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(status!, textAlign: TextAlign.center),
                    ),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: busy ? null : _retry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('دوباره تلاش کن'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _backupDatabase,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('پشتیبان خام از دیتابیس فعلی'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _restoreDatabase,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('بازیابی یک دیتابیس سالم'),
                ),
                if (automaticBackupPath != null)
                  OutlinedButton.icon(
                    onPressed: busy ? null : _restoreAutomaticBackup,
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('بازیابی نسخه خودکار .backup'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _copyDiagnostics,
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('کپی گزارش خطا'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: busy ? null : _saveDiagnostics,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('ذخیره گزارش خطا به صورت فایل'),
                ),
                const SizedBox(height: 18),
                const Text(
                  'نکته: در Migrationهای جدید، برنامه نباید برای بازسازی صف همگام‌سازی همه نامه‌های قدیمی را در مسیر باز شدن پردازش کند. '
                  'این عملیات از مسیر شروع برنامه جدا شده است تا دیتابیس‌های بزرگ باعث گیر کردن برنامه نشوند.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, height: 1.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
