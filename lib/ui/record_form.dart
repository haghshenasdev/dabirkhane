import 'dart:async';
import 'dart:io';

import 'package:dabirkhane/model/reminder.dart';
import 'package:dabirkhane/providers/scan_service.dart';
import 'package:dabirkhane/ui/dialogs/record_history_dialog.dart';
import 'package:dabirkhane/ui/dialogs/reminder_dialog.dart';
import 'package:dabirkhane/utils/letter_file_organizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:window_manager/window_manager.dart';
import 'package:dabirkhane/services/notification_service.dart';

import '../db/database_helper.dart';
import '../utils/JalaliDateFormatter.dart';
import '../utils/app_settings.dart';

class RecordForm extends StatefulWidget {
  final Map<String, dynamic>? record;

  const RecordForm({super.key, this.record});

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        WindowListener {
  // ============================================================
  // Form
  // ============================================================

  final _formKey = GlobalKey<FormState>();
  StreamSubscription<ScanResult>? _scanSubscription;

  final Map<String, TextEditingController> c = {};
  final Map<String, FocusNode> focusNodes = {};

  final FocusNode _firstFieldFocus = FocusNode();

  late TabController _tabController;

  bool _sahebNameSuggestionsEnabled = true;
  bool _guySuggestionsEnabled = true;
  bool _onvanSuggestionsEnabled = true;
  bool _categorySuggestionsEnabled = true;
  bool _reminderChanged = false;

  // ============================================================
  // Suggestions
  // ============================================================

  List<String> guySuggestions = [];
  List<String> onvanSuggestions = [];
  List<String> sahebSuggestions = [];

  Timer? _debounceGuy;
  Timer? _debounceOnvan;
  Timer? _debounce;

  // ============================================================
  // Categories
  // ============================================================

  List<String> selectedCategories = [];
  List<String> categorySuggestions = [];

  Timer? _debounceCategory;

  final TextEditingController categoryController = TextEditingController();

  final FocusNode categoryFocus = FocusNode();

  // ============================================================
  // Files
  // ============================================================

  List<File> filesInDirectory = [];

  // ============================================================
  // Previous record info
  // ============================================================

  Map<String, dynamic>? lastRecord;
  String? lastInfoText;

  // ============================================================
  // Unsaved changes / Window close
  // ============================================================

  Map<String, String> _initialFieldValues = {};
  List<String> _initialCategories = [];
  String _initialCategoryInput = '';

  bool _ignoreWindowClose = false;
  bool _windowCloseDialogShowing = false;
  bool _isSaving = false;
  int? _savedRecordId;
  bool _autoSaveEnabled = false;
  bool _saveAndReturnAfterScan = false;
  bool _hasActiveReminder = false;
  Reminder? _todayReminder;

  // ============================================================
  // Fields
  // ============================================================

  final mainFields = [
    'Shomare_Radif',
    'date',
    'saheb_name',
    'guy',
    'sh_name_reside',
    'onvan',
    'comment',
    'shomare_badi',
  ];

  final otherFields = [
    't_name_ersali',
    't_name_reside',
    'wordmost2',
    'from_pywa',
    'adres_name',
    'goshashte',
  ];

  final Map<String, String> fieldLabels = {
    'Shomare_Radif': 'شماره نامه',
    'goshashte': 'شماره قبلی',
    'date': 'تاریخ',
    'saheb_name': 'صاحب نامه',
    'guy': 'موضوع',
    'from_pywa': 'پیوست نامه',
    'sh_name_reside': 'شماره تماس',
    't_name_reside': 'تاریخ نامه',
    'onvan': 'گیرنده نامه',
    'comment': 'توضیحات',
    'shomare_badi': 'شماره بعدی',
    'wordmost2': 'پیوست مکاتبه',
    't_name_ersali': 'تاریخ مکاتبه',
    'adres_name': 'آدرس',
  };

  // ============================================================
  // Init
  // ============================================================

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this);

    _scanSubscription = ScanService.results.listen(_onScanResult);

    _loadSuggestionSettings();
    _loadAutoSaveSetting();
    _loadScanSettings();
    _loadReminderStatus();

    for (final field in [...mainFields, ...otherFields]) {
      c[field] = TextEditingController(
        text: widget.record?[field]?.toString() ?? '',
      );

      focusNodes[field] = FocusNode();
    }

    if (widget.record == null) {
      _setInitialValues();
    } else {
      _captureInitialState();
      _loadFiles();
      _loadCategories();
    }

    _initWindowCloseProtection();
  }

  Future<void> _initWindowCloseProtection() async {
    if (!Platform.isWindows) return;

    try {
      await windowManager.ensureInitialized();

      if (!mounted) return;

      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
    } catch (e) {
      debugPrint('Window close protection init error: $e');
    }
  }

  Map<String, String> _getCurrentFieldValues() {
    return {
      for (final field in [...mainFields, ...otherFields])
        field: c[field]?.text ?? '',
    };
  }

  void _captureInitialState() {
    _initialFieldValues = _getCurrentFieldValues();
    _initialCategories = List<String>.from(selectedCategories);
    _initialCategoryInput = categoryController.text;
  }

  void _captureSavedState() {
    _captureInitialState();
  }

  bool get _hasUnsavedChanges {
    for (final field in [...mainFields, ...otherFields]) {
      if ((_initialFieldValues[field] ?? '') != (c[field]?.text ?? '')) {
        return true;
      }
    }

    if (_initialCategories.length != selectedCategories.length) {
      return true;
    }

    for (int i = 0; i < selectedCategories.length; i++) {
      if (selectedCategories[i] != _initialCategories[i]) {
        return true;
      }
    }

    if (_initialCategoryInput != categoryController.text) {
      return true;
    }

    return false;
  }

  Future<bool> _confirmExit() async {
    if (_ignoreWindowClose || !_hasUnsavedChanges) {
      return true;
    }

    // اگر ذخیره خودکار فعال باشد،
    // هنگام خروج مستقیماً اطلاعات ذخیره می‌شود.
    if (_autoSaveEnabled) {
      final saved = await _saveDataOnly();

      if (saved) {
        _ignoreWindowClose = true;
      }

      return saved;
    }

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _glassDialog(
          title: 'تغییرات ذخیره نشده',
          icon: Icons.warning_amber_rounded,
          iconColor: Colors.orange,
          content: const Text(
            'شما تغییراتی در فرم ایجاد کرده‌اید که هنوز ذخیره نشده‌اند.\n\n'
            'آیا می‌خواهید تغییرات را ذخیره کنید؟',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, height: 1.7),
          ),
          actions: [
            _dialogButton(
              label: 'ادامه ویرایش',
              onPressed: () {
                Navigator.pop(context, 'continue');
              },
            ),
            _dialogButton(
              label: 'صرف‌نظر',
              danger: true,
              onPressed: () {
                Navigator.pop(context, 'discard');
              },
            ),
            _dialogButton(
              label: 'ذخیره',
              onPressed: () {
                Navigator.pop(context, 'save');
              },
            ),
          ],
        );
      },
    );

    if (!mounted) return false;

    switch (result) {
      case 'discard':
        _ignoreWindowClose = true;
        return true;

      case 'save':
        final saved = await _saveDataOnly();
        if (saved) {
          _ignoreWindowClose = true;
        }
        return saved;

      default:
        return false;
    }
  }

  Future<bool> _saveDataOnly() async {
    if (!_formKey.currentState!.validate()) {
      return false;
    }

    if (_isSaving) {
      return false;
    }

    _isSaving = true;

    try {
      final data = {
        for (final field in [...mainFields, ...otherFields])
          field: c[field]!.text,
      };

      int id;

      if (_savedRecordId != null) {
        id = _savedRecordId!;

        await DatabaseHelper.update(id, data);
      } else if (widget.record == null) {
        id = await DatabaseHelper.insert(data);
      } else {
        id = widget.record!['Shomare_Radif'] is int
            ? widget.record!['Shomare_Radif']
            : int.parse(widget.record!['Shomare_Radif'].toString());

        await DatabaseHelper.update(id, data);
      }

      await DatabaseHelper.saveCategoriesForRecord(
        id.toString(),
        List<String>.from(selectedCategories),
      );

      if (!mounted) return false;

      _savedRecordId = id;
      _captureSavedState();
      await _loadReminderStatus();

      return true;
    } catch (e, stackTrace) {
      debugPrint('saveDataOnly error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        _showMessage('خطا در ذخیره اطلاعات:\n$e');
      }

      return false;
    } finally {
      _isSaving = false;
    }
  }

  Future<void> _handleWindowClose() async {
    if (!mounted || _windowCloseDialogShowing) {
      return;
    }

    if (_ignoreWindowClose) {
      await windowManager.destroy();
      return;
    }

    _windowCloseDialogShowing = true;

    try {
      final shouldClose = await _confirmExit();

      if (!mounted) return;

      if (shouldClose) {
        _ignoreWindowClose = true;
        await windowManager.destroy();
      }
    } finally {
      _windowCloseDialogShowing = false;
    }
  }

  @override
  void onWindowClose() {
    if (!Platform.isWindows) return;
    _handleWindowClose();
  }

  Future<void> _loadScanSettings() async {
    final value = await AppSettings.getSaveAndReturnAfterScan();

    if (!mounted) return;

    setState(() {
      _saveAndReturnAfterScan = value;
    });
  }

  Future<void> _loadSuggestionSettings() async {
    final values = await Future.wait([
      AppSettings.getFormSuggestionsEnabled('saheb_name'),
      AppSettings.getFormSuggestionsEnabled('guy'),
      AppSettings.getFormSuggestionsEnabled('onvan'),
      AppSettings.getFormSuggestionsEnabled('category'),
    ]);

    if (!mounted) return;

    setState(() {
      _sahebNameSuggestionsEnabled = values[0];
      _guySuggestionsEnabled = values[1];
      _onvanSuggestionsEnabled = values[2];
      _categorySuggestionsEnabled = values[3];
    });
  }

  Future<void> _loadAutoSaveSetting() async {
    final value = await AppSettings.getAutoSaveRecordForm();

    if (!mounted) return;

    setState(() {
      _autoSaveEnabled = value;
    });
  }

  Future<void> _onScanResult(ScanResult result) async {
    if (!mounted) {
      return;
    }

    if (result.cancelled) {
      _showMessage('اسکن لغو شد.');
      return;
    }

    if (!result.success) {
      _showMessage('اسکن با خطا پایان یافت.');
      return;
    }

    // فایل‌های اسکن شده را دوباره بارگذاری می‌کنیم
    await _loadFiles();

    if (!mounted) {
      return;
    }

    // اگر این گزینه فعال باشد،
    // بعد از موفقیت اسکن، اطلاعات نامه ذخیره و فرم بسته می‌شود.
    if (_saveAndReturnAfterScan) {
      final saved = await _saveDataOnly();

      if (!mounted) {
        return;
      }

      if (!saved) {
        // _saveDataOnly خودش پیام خطا را نمایش می‌دهد
        return;
      }

      // به سیستم پنجره/PopScope اعلام می‌کنیم
      // که بسته شدن فرم مجاز است.
      _ignoreWindowClose = true;

      Navigator.pop(context, {
        'id': _savedRecordId,
        'scanned': true,
        'reminderChanged': _reminderChanged,
      });

      return;
    }

    // رفتار قبلی
    _showMessage('فایل اسکن شده با موفقیت اضافه شد.');
  }

  // ============================================================
  // Initial values
  // ============================================================

  Future<void> _setInitialValues() async {
    final now = Jalali.now();

    c['date']!.text =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    await _setDefaultShomareRadif();

    if (!mounted) return;

    _captureInitialState();
  }

  Future<void> _setDefaultShomareRadif() async {
    final lastNumber = await DatabaseHelper.getLastShomareRadif();

    final nextNumber = (lastNumber ?? 0) + 1;

    if (!mounted) return;

    c['Shomare_Radif']!.text = nextNumber.toString();
  }

  // ============================================================
  // Categories
  // ============================================================

  Future<void> _loadCategories() async {
    final recordId = widget.record!['Shomare_Radif'].toString();

    final cats = await DatabaseHelper.getCategoriesForRecord(recordId);

    if (!mounted) return;

    setState(() {
      selectedCategories = List<String>.from(cats);
    });

    _initialCategories = List<String>.from(selectedCategories);
  }

  void _addCategory(String value) {
    final category = value.trim();

    if (category.isEmpty) return;

    if (!selectedCategories.contains(category)) {
      setState(() {
        selectedCategories.add(category);
      });
    }

    categoryController.clear();

    setState(() {
      categorySuggestions.clear();
    });
  }

  Future<void> _showCategoryPicker() async {
    // دسته‌بندی‌های موجود در دیتابیس
    final categories = await DatabaseHelper.searchCategories('');

    if (!mounted) return;

    // انتخاب‌های موقت داخل دیالوگ
    final tempSelected = <String>{...selectedCategories};

    final result = await showDialog<List<String>>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final searchController = TextEditingController();
        List<String> filteredCategories = List<String>.from(categories);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            void filterCategories(String value) {
              final query = value.trim().toLowerCase();

              setDialogState(() {
                if (query.isEmpty) {
                  filteredCategories = List<String>.from(categories);
                } else {
                  filteredCategories = categories
                      .where((item) => item.toLowerCase().contains(query))
                      .toList();
                }
              });
            }

            return Directionality(
              textDirection: TextDirection.rtl,
              child: Dialog(
                backgroundColor: Colors.transparent,
                elevation: 0,
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 30,
                ),
                child: _glassContainer(
                  padding: const EdgeInsets.all(18),
                  radius: 24,
                  opacity: .96,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 520,
                      maxHeight: 620,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // عنوان
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withOpacity(.09),
                              ),
                              child: Icon(
                                Icons.category_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: 21,
                              ),
                            ),

                            const SizedBox(width: 11),

                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'انتخاب دسته‌بندی',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${tempSelected.length} دسته انتخاب شده',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(.50),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            IconButton(
                              tooltip: 'بستن',
                              onPressed: () {
                                Navigator.pop(dialogContext);
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // جستجو
                        TextField(
                          controller: searchController,
                          onChanged: filterCategories,
                          textDirection: TextDirection.rtl,
                          decoration: _glassInputDecoration(
                            label: 'جستجوی دسته‌بندی',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      filterCategories('');
                                    },
                                    icon: const Icon(Icons.clear_rounded),
                                  )
                                : null,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // لیست دسته‌بندی‌ها
                        Expanded(
                          child: filteredCategories.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(30),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.category_outlined,
                                          size: 42,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurface
                                              .withOpacity(.25),
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'دسته‌بندی‌ای پیدا نشد',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withOpacity(.50),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: filteredCategories.length,
                                  separatorBuilder: (_, __) {
                                    return Divider(
                                      height: 1,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.outline.withOpacity(.07),
                                    );
                                  },
                                  itemBuilder: (_, index) {
                                    final category = filteredCategories[index];

                                    final isSelected = tempSelected.contains(
                                      category,
                                    );

                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          setDialogState(() {
                                            if (isSelected) {
                                              tempSelected.remove(category);
                                            } else {
                                              tempSelected.add(category);
                                            }
                                          });
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Checkbox(
                                                value: isSelected,
                                                onChanged: (value) {
                                                  setDialogState(() {
                                                    if (value == true) {
                                                      tempSelected.add(
                                                        category,
                                                      );
                                                    } else {
                                                      tempSelected.remove(
                                                        category,
                                                      );
                                                    }
                                                  });
                                                },
                                              ),

                                              const SizedBox(width: 5),

                                              Container(
                                                width: 34,
                                                height: 34,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withOpacity(.08),
                                                ),
                                                child: Icon(
                                                  Icons.label_outline_rounded,
                                                  size: 18,
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),

                                              const SizedBox(width: 10),

                                              Expanded(
                                                child: Text(
                                                  category,
                                                  textDirection:
                                                      TextDirection.rtl,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),

                        const SizedBox(height: 14),

                        // دکمه‌ها
                        Row(
                          children: [
                            Expanded(
                              child: _glassButton(
                                label: 'انصراف',
                                icon: Icons.close_rounded,
                                onPressed: () {
                                  Navigator.pop(dialogContext);
                                },
                              ),
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: _glassButton(
                                label: 'تأیید انتخاب',
                                icon: Icons.check_rounded,
                                primary: true,
                                onPressed: () {
                                  Navigator.pop(
                                    dialogContext,
                                    tempSelected.toList(),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      selectedCategories = List<String>.from(result);
      categorySuggestions.clear();
    });

    categoryController.clear();
  }

  // ============================================================
  // Files
  // ============================================================

  Future<Directory> getLettersDirectory() async {
    final lettersDir = await AppSettings.getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    return lettersDir;
  }

  Future<void> _loadFiles() async {
    final shomareRadifRaw = c['Shomare_Radif']?.text ?? '';

    final shomareRadif = normalizeNumbers(shomareRadifRaw.trim());

    if (shomareRadif.isEmpty) {
      if (!mounted) return;

      setState(() {
        filesInDirectory = [];
      });

      return;
    }

    final lettersDir = await getLettersDirectory();

    if (!await lettersDir.exists()) {
      if (!mounted) return;

      setState(() {
        filesInDirectory = [];
      });

      return;
    }

    final regex = RegExp('^$shomareRadif((\\D+\\d+)|\\d+)?\$');

    final List<File> matchedFiles = [];

    try {
      await for (final entity in lettersDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;

        final nameRaw = path.basenameWithoutExtension(entity.path);

        final name = normalizeNumbers(nameRaw);

        if (regex.hasMatch(name)) {
          matchedFiles.add(entity);
        }
      }

      matchedFiles.sort((a, b) => a.path.compareTo(b.path));

      if (!mounted) return;

      setState(() {
        filesInDirectory = List<File>.from(matchedFiles);
      });
    } catch (e) {
      debugPrint('Error while loading files: $e');
    }
  }

  String normalizeNumbers(String input) {
    const persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

    for (int i = 0; i < persianDigits.length; i++) {
      input = input.replaceAll(persianDigits[i], i.toString());
    }

    return input;
  }

  Future<void> addFileForRecord() async {
    final status = await Permission.manageExternalStorage.request();

    if (!status.isGranted) {
      if (!mounted) return;

      _showMessage('برای دسترسی به فایل‌ها مجوز لازم را بدهید');

      return;
    }

    final shomareRadif = c['Shomare_Radif']?.text.trim();

    if (shomareRadif == null || shomareRadif.isEmpty) {
      _showMessage('شماره ثبت مشخص نیست');

      return;
    }

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null || result.files.isEmpty) {
      return;
    }

    final lettersDir = await getLettersDirectory();

    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    final date = c['date']?.text.trim() ?? '';

    final targetDirectory = await LetterFileOrganizer.getDirectoryForDate(date);

    if (targetDirectory == null) {
      _showMessage(
        'تاریخ نامه معتبر نیست.\n'
        'لطفاً تاریخ را به صورت 1405/01/01 وارد کنید.',
      );
      return;
    }

    for (final file in result.files) {
      if (file.path == null) continue;

      final pickedFile = File(file.path!);

      final ext = path.extension(pickedFile.path);

      String targetName = '$shomareRadif$ext';

      File targetFile = File(path.join(targetDirectory.path, targetName));

      int index = 1;

      while (await targetFile.exists()) {
        targetName = '${shomareRadif}_$index$ext';

        targetFile = File(path.join(targetDirectory.path, targetName));

        index++;
      }

      await pickedFile.copy(targetFile.path);
    }

    await _loadFiles();

    if (!mounted) return;

    _showMessage('فایل‌ها با موفقیت اضافه شدند');
  }

  Future<void> openFile(File file) async {
    final result = await OpenFile.open(file.path);

    if (result.type != ResultType.done) {
      if (!mounted) return;

      _showMessage('خطا در باز کردن فایل');
    }
  }

  Future<void> deleteFile(File file) async {
    final fileName = path.basename(file.path);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return _glassDialog(
          title: 'حذف فایل',
          icon: Icons.delete_outline_rounded,
          iconColor: Colors.red,
          content: Text(
            'آیا از حذف فایل «$fileName» مطمئن هستید؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            _dialogButton(
              label: 'انصراف',
              onPressed: () {
                Navigator.pop(context, false);
              },
            ),
            _dialogButton(
              label: 'حذف',
              danger: true,
              onPressed: () {
                Navigator.pop(context, true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      if (await file.exists()) {
        await file.delete();
      }

      if (!mounted) return;

      setState(() {
        filesInDirectory.removeWhere((item) => item.path == file.path);
      });

      _showMessage('فایل «$fileName» حذف شد');
    } catch (e) {
      if (!mounted) return;

      _showMessage('خطا در حذف فایل:\n$e');
    }
  }

  // ============================================================
  // Save
  // ============================================================

  Future<void> save() async {
    final saved = await _saveDataOnly();

    if (!saved || !mounted) return;

    _ignoreWindowClose = true;

    final id = widget.record == null
        ? int.parse(c['Shomare_Radif']!.text)
        : widget.record!['Shomare_Radif'] is int
        ? widget.record!['Shomare_Radif']
        : int.parse(widget.record!['Shomare_Radif'].toString());

    Navigator.pop(context, {
      'id': id,
      'scanned': false,
      'reminderChanged': _reminderChanged,
    });
  }

  Future<void> saveAndStay() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      final data = {
        for (final field in [...mainFields, ...otherFields])
          field: c[field]!.text,
      };

      int id;

      if (widget.record == null) {
        id = await DatabaseHelper.insert(data);
      } else {
        id = widget.record!['Shomare_Radif'] is int
            ? widget.record!['Shomare_Radif']
            : int.parse(widget.record!['Shomare_Radif'].toString());

        await DatabaseHelper.update(id, data);
      }

      await DatabaseHelper.saveCategoriesForRecord(
        id.toString(),
        List<String>.from(selectedCategories),
      );

      final lastDate = c['date']?.text ?? '';

      for (final controller in c.values) {
        controller.clear();
      }

      setState(() {
        selectedCategories.clear();
        categorySuggestions.clear();
        filesInDirectory.clear();
        lastRecord = null;
        lastInfoText = null;
      });

      await _setInitialValues();

      c['date']?.text = lastDate;
      _captureSavedState();

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _firstFieldFocus.requestFocus();
        }
      });

      if (!mounted) return;

      _showMessage('اطلاعات با موفقیت ذخیره شد');
    } catch (e, stackTrace) {
      debugPrint('saveAndStay error: $e');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showMessage('خطا در ذخیره اطلاعات:\n$e');
    }
  }

  // ============================================================
  // Scan
  // ============================================================

  Future<void> scan() async {
    final id = c['Shomare_Radif']!.text.trim();

    if (id.isEmpty) {
      _showMessage('مقدار آیدی نامه معتبر نیست.');
      return;
    }

    try {
      await ScanService.deleteOldScans(int.parse(id));

      await ScanService.startScan(id, c['date']?.text.trim());
    } catch (e) {
      debugPrint('Open Scanner Error: $e');

      if (!mounted) {
        return;
      }

      _showMessage('خطا در باز کردن اسکنر\n$e');
    }
  }

  // ============================================================
  // Share
  // ============================================================

  Future<void> shareFiles() async {
    if (filesInDirectory.isEmpty) {
      _showMessage('فایلی برای اشتراک گذاری وجود ندارد');

      return;
    }

    final files = filesInDirectory.map((e) => XFile(e.path)).toList();

    await Share.shareXFiles(
      files,
      subject: 'نامه شماره ${c['Shomare_Radif']!.text}',
      text: 'نامه شماره ${c['Shomare_Radif']!.text}',
    );
  }

  // ============================================================
  // Lifecycle
  // ============================================================

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) {
      return;
    }

    if (!ScanService.isWaitingForScan) {
      return;
    }

    final ok = await ScanService.processReturnedScan();

    if (!mounted) return;

    if (ok) {
      await _loadFiles();

      if (!mounted) return;

      _showMessage('فایل اسکن شده اضافه شد.');
    }
  }

  // ============================================================
  // Autocomplete - Guy
  // ============================================================

  Widget buildGuyField() {
    return buildSimpleAutoCompleteField(
      field: 'guy',
      label: 'موضوع',
      suggestions: guySuggestions,
      onChanged: (value) {
        _debounceGuy?.cancel();

        if (!_guySuggestionsEnabled) {
          if (guySuggestions.isNotEmpty) {
            setState(() {
              guySuggestions.clear();
            });
          }
          return;
        }

        _debounceGuy = Timer(const Duration(milliseconds: 300), () async {
          if (value.trim().isEmpty) {
            setState(() => guySuggestions.clear());
            return;
          }

          final res = await DatabaseHelper.searchDistinctField(
            'guy',
            value.trim(),
          );

          if (!mounted || !_guySuggestionsEnabled) return;

          setState(() {
            guySuggestions = res;
          });
        });
      },
      onSelected: (item) {
        c['guy']!.text = item;

        setState(() {
          guySuggestions.clear();
        });
      },
      focusNode: focusNodes['guy']!,
      nextFocus: focusNodes['saheb_name'],
    );
  }

  // ============================================================
  // Autocomplete - Onvan
  // ============================================================

  Widget buildOnvanField() {
    return buildSimpleAutoCompleteField(
      field: 'onvan',
      label: 'گیرنده نامه',
      suggestions: onvanSuggestions,
      onChanged: (value) {
        _debounceOnvan?.cancel();

        if (!_onvanSuggestionsEnabled) {
          if (onvanSuggestions.isNotEmpty) {
            setState(() {
              onvanSuggestions.clear();
            });
          }
          return;
        }

        _debounceOnvan = Timer(const Duration(milliseconds: 300), () async {
          if (value.trim().isEmpty) {
            setState(() => onvanSuggestions.clear());
            return;
          }

          final res = await DatabaseHelper.searchDistinctField(
            'onvan',
            value.trim(),
          );

          if (!mounted || !_onvanSuggestionsEnabled) return;

          setState(() {
            onvanSuggestions = res;
          });
        });
      },
      onSelected: (item) {
        c['onvan']!.text = item;

        setState(() {
          onvanSuggestions.clear();
        });
      },
      focusNode: focusNodes['onvan']!,
      nextFocus: null,
    );
  }

  // ============================================================
  // Generic autocomplete
  // ============================================================

  Widget buildSimpleAutoCompleteField({
    required String field,
    required String label,
    required List<String> suggestions,
    required void Function(String) onChanged,
    required void Function(String) onSelected,
    required FocusNode focusNode,
    FocusNode? nextFocus,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassField(
          child: TextFormField(
            controller: c[field],
            focusNode: focusNode,
            decoration: _glassInputDecoration(
              label: label,
              suffixIcon: suggestions.isNotEmpty
                  ? IconButton(
                      tooltip: 'بستن پیشنهادها',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          suggestions.clear();
                        });
                      },
                    )
                  : null,
            ),
            textDirection: TextDirection.rtl,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            onChanged: onChanged,
            onFieldSubmitted: (_) {
              if (suggestions.isNotEmpty) {
                onSelected(suggestions.first);
              }

              if (nextFocus != null) {
                FocusScope.of(context).requestFocus(nextFocus);
              } else {
                focusNode.unfocus();
              }
            },
          ),
        ),

        if (suggestions.isNotEmpty)
          _glassSuggestions(
            suggestions: suggestions,
            onSelected: onSelected,
            icon: Icons.history_rounded,
          ),
      ],
    );
  }

  // ============================================================
  // Saheb name
  // ============================================================

  Widget buildSahebNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassField(
          child: TextFormField(
            focusNode: _firstFieldFocus,
            controller: c['saheb_name'],
            decoration: _glassInputDecoration(
              label: 'صاحب نامه',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              suffixIcon: sahebSuggestions.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          sahebSuggestions.clear();
                        });
                      },
                    )
                  : null,
            ),
            textDirection: TextDirection.rtl,
            minLines: 1,
            maxLines: 3,
            keyboardType: TextInputType.multiline,
            onChanged: (value) {
              _debounce?.cancel();

              if (!_sahebNameSuggestionsEnabled) {
                if (sahebSuggestions.isNotEmpty) {
                  setState(() {
                    sahebSuggestions.clear();
                  });
                }
                return;
              }

              _debounce = Timer(const Duration(milliseconds: 400), () async {
                if (value.trim().isEmpty) {
                  setState(() {
                    sahebSuggestions.clear();
                  });
                  return;
                }

                final res = await DatabaseHelper.searchSahebName(value.trim());

                if (!mounted || !_sahebNameSuggestionsEnabled) {
                  return;
                }

                setState(() {
                  sahebSuggestions = res;
                });
              });
            },
          ),
        ),

        if (sahebSuggestions.isNotEmpty)
          _glassSuggestions(
            suggestions: sahebSuggestions,
            icon: Icons.person_outline_rounded,
            onSelected: (item) async {
              c['saheb_name']!.text = item;

              final last = await DatabaseHelper.getLastRecordBySahebName(item);

              if (last != null) {
                c['sh_name_reside']!.text =
                    last['sh_name_reside']?.toString() ?? '';

                lastRecord = last;

                lastInfoText =
                    'آخرین نامه: ${last['date'] ?? '—'} | '
                    '${last['guy'] ?? '—'} | '
                    '${last['onvan'] ?? '—'}';
              } else {
                lastRecord = null;
                lastInfoText = null;
              }

              if (!mounted) return;

              setState(() {
                sahebSuggestions.clear();
              });
            },
          ),

        if (lastInfoText != null && lastRecord != null) _buildLastRecordCard(),
      ],
    );
  }

  // ============================================================
  // Last record
  // ============================================================

  Widget _buildLastRecordCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: colorScheme.primary.withOpacity(.055),
        border: Border.all(color: colorScheme.primary.withOpacity(.12)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RecordForm(record: lastRecord)),
            );
          },
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.primary.withOpacity(.10),
                ),
                child: Icon(
                  Icons.history_rounded,
                  size: 19,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  lastInfoText!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(.68),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Category
  // ============================================================
  Widget buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassField(
          margin: EdgeInsets.zero,
          child: TextFormField(
            controller: categoryController,
            focusNode: categoryFocus,
            decoration: _glassInputDecoration(
              label: 'دسته‌بندی',
              prefixIcon: const Icon(Icons.label_outline_rounded),

              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // دکمه انتخاب از دسته‌بندی‌های موجود
                  IconButton(
                    tooltip: 'انتخاب از دسته‌بندی‌های موجود',
                    icon: const Icon(Icons.list_alt_rounded),
                    onPressed: _showCategoryPicker,
                  ),

                  // دکمه افزودن دسته‌بندی تایپ‌شده
                  if (categoryController.text.trim().isNotEmpty)
                    IconButton(
                      tooltip: 'افزودن دسته‌بندی',
                      icon: const Icon(Icons.add_rounded),
                      onPressed: () {
                        _addCategory(categoryController.text);
                      },
                    ),
                ],
              ),
            ),
            textDirection: TextDirection.rtl,
            onChanged: (value) {
              _debounceCategory?.cancel();

              // برای اینکه ظاهر دکمه + با تایپ تغییر کند
              setState(() {});

              if (!_categorySuggestionsEnabled) {
                if (categorySuggestions.isNotEmpty) {
                  setState(() {
                    categorySuggestions.clear();
                  });
                }
                return;
              }

              _debounceCategory = Timer(
                const Duration(milliseconds: 300),
                () async {
                  if (value.trim().isEmpty) {
                    if (!mounted) return;

                    setState(() {
                      categorySuggestions.clear();
                    });

                    return;
                  }

                  final res = await DatabaseHelper.searchCategories(
                    value.trim(),
                  );

                  if (!mounted || !_categorySuggestionsEnabled) {
                    return;
                  }

                  setState(() {
                    categorySuggestions = res;
                  });
                },
              );
            },
            onFieldSubmitted: (value) {
              _addCategory(value);
            },
          ),
        ),

        if (selectedCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 8),
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: selectedCategories.map((cat) {
                return _categoryChip(cat);
              }).toList(),
            ),
          ),

        if (categorySuggestions.isNotEmpty) _glassCategorySuggestions(),
      ],
    );
  }

  Widget _categoryChip(String category) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: colorScheme.primary.withOpacity(.08),
        border: Border.all(color: colorScheme.primary.withOpacity(.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 5, right: 12, top: 5, bottom: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              category,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  selectedCategories.remove(category);
                });
              },
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassCategorySuggestions() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(.82),
        border: Border.all(color: Colors.white.withOpacity(.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.055),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: categorySuggestions.length,
          separatorBuilder: (_, __) =>
              Divider(height: 1, color: colorScheme.outline.withOpacity(.07)),
          itemBuilder: (_, index) {
            final item = categorySuggestions[index];

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _addCategory(item);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withOpacity(.08),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(item, textDirection: TextDirection.rtl),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ============================================================
  // Suggestions glass
  // ============================================================

  Widget _glassSuggestions({
    required List<String> suggestions,
    required void Function(String) onSelected,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 3, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(.84),
        border: Border.all(color: Colors.white.withOpacity(.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.065),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'پیشنهادها',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withOpacity(.55),
                    ),
                  ),
                ],
              ),
            ),
            ...suggestions.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;

              return Column(
                children: [
                  if (index != 0)
                    Divider(
                      height: 1,
                      color: colorScheme.outline.withOpacity(.07),
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onSelected(item);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 18,
                              color: colorScheme.primary.withOpacity(.75),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 11,
                              color: colorScheme.onSurface.withOpacity(.22),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Text fields
  // ============================================================

  Widget buildTextField(String field) {
    if (field == 'saheb_name') {
      return buildSahebNameField();
    }

    if (field == 'guy') {
      return buildGuyField();
    }

    if (field == 'onvan') {
      return buildOnvanField();
    }

    // ==========================================================
    // Date
    // ==========================================================

    if (field == 'date') {
      return _glassField(
        child: TextFormField(
          controller: c[field],
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            JalaliDateFormatter(),
          ],
          decoration: _glassInputDecoration(
            label: 'تاریخ',
            hint: '1405/01/15',
            prefixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          textDirection: TextDirection.rtl,
          validator: (value) {
            if (value == null || value.length != 10) {
              return 'تاریخ معتبر وارد کنید';
            }

            return null;
          },
        ),
      );
    }

    // ==========================================================
    // Comment
    // ==========================================================

    if (field == 'comment') {
      return _glassField(
        child: TextFormField(
          controller: c[field],
          decoration: _glassInputDecoration(
            label: fieldLabels[field] ?? field,
            prefixIcon: const Icon(Icons.notes_outlined),
            alignLabelWithHint: true,
          ),
          textDirection: TextDirection.rtl,
          minLines: 1,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
        ),
      );
    }

    // ==========================================================
    // Other fields
    // ==========================================================

    return _glassField(
      child: TextFormField(
        controller: c[field],
        focusNode: focusNodes[field],
        minLines: 1,
        maxLines: 3,
        keyboardType: TextInputType.multiline,
        decoration: _glassInputDecoration(label: fieldLabels[field] ?? field),
        textDirection: TextDirection.rtl,
        onFieldSubmitted: (_) {
          final currentIndex = mainFields.contains(field)
              ? mainFields.indexOf(field)
              : otherFields.indexOf(field);

          final fields = mainFields.contains(field) ? mainFields : otherFields;

          if (currentIndex >= 0 && currentIndex < fields.length - 1) {
            FocusScope.of(
              context,
            ).requestFocus(focusNodes[fields[currentIndex + 1]]);
          } else {
            FocusScope.of(context).unfocus();
          }
        },
      ),
    );
  }

  // ============================================================
  // FILE TAB
  // ============================================================

  Widget _buildFilesTab() {
    return Container(
      color: const Color(0xffEEF3F8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: _buildFilesHeader(),
          ),

          Expanded(
            child: filesInDirectory.isEmpty
                ? _buildEmptyFilesState()
                : _buildFilesGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    return _glassContainer(
      padding: const EdgeInsets.all(14),
      radius: 22,
      opacity: .72,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: colorScheme.primary.withOpacity(.09),
                ),
                child: Icon(
                  Icons.folder_copy_outlined,
                  color: colorScheme.primary,
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'فایل‌های نامه',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      filesInDirectory.isEmpty
                          ? 'هنوز فایلی اضافه نشده است'
                          : '${filesInDirectory.length} فایل پیوست شده',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withOpacity(.52),
                      ),
                    ),
                  ],
                ),
              ),

              _fileCountBadge(),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _glassButton(
                  label: 'افزودن فایل',
                  icon: Icons.attach_file_rounded,
                  onPressed: addFileForRecord,
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: _glassButton(
                  label: 'اشتراک‌گذاری',
                  icon: Icons.share_rounded,
                  onPressed: shareFiles,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: _glassButton(
                  label: 'اسکن فایل',
                  icon: Icons.document_scanner_outlined,
                  onPressed: scan,
                  primary: true,
                ),
              ),

              const SizedBox(width: 8),

              _squareGlassButton(
                icon: Icons.refresh_rounded,
                tooltip: 'بروزرسانی لیست',
                onPressed: _loadFiles,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fileCountBadge() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: colorScheme.primary.withOpacity(.09),
        border: Border.all(color: colorScheme.primary.withOpacity(.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            size: 15,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 5),
          Text(
            filesInDirectory.length.toString(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Empty files
  // ============================================================

  Widget _buildEmptyFilesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _glassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 34),
          radius: 24,
          opacity: .68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).colorScheme.primary.withOpacity(.08),
                ),
                child: Icon(
                  Icons.folder_open_outlined,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary.withOpacity(.65),
                ),
              ),

              const SizedBox(height: 18),

              const Text(
                'فایلی وجود ندارد',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),

              const SizedBox(height: 8),

              Text(
                'برای این نامه هنوز فایلی ثبت نشده است.',
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(.52),
                ),
              ),

              const SizedBox(height: 20),

              _glassButton(
                label: 'افزودن فایل',
                icon: Icons.add_rounded,
                onPressed: addFileForRecord,
                primary: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Files grid
  // ============================================================

  Widget _buildFilesGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .64,
      ),
      itemCount: filesInDirectory.length,
      itemBuilder: (context, index) {
        final file = filesInDirectory[index];

        return _buildFileCard(file);
      },
    );
  }

  // ============================================================
  // File card
  // ============================================================

  Widget _buildFileCard(File file) {
    final isImg = _isImage(file.path);

    final fileName = path.basename(file.path);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: _glassContainer(
        padding: EdgeInsets.zero,
        radius: 20,
        opacity: .76,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => openFile(file),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Container(
                          margin: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(15),
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withOpacity(.50),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: isImg
                              ? Image.file(
                                  file,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _filePreviewIcon(file);
                                  },
                                )
                              : _filePreviewIcon(file),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 12),
                        child: Text(
                          fileName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                top: 9,
                right: 9,
                child: _fileActionButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'حذف فایل',
                  danger: true,
                  onPressed: () => deleteFile(file),
                ),
              ),

              Positioned(
                top: 9,
                left: 9,
                child: _fileActionButton(
                  icon: Icons.open_in_new_rounded,
                  tooltip: 'باز کردن',
                  onPressed: () => openFile(file),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filePreviewIcon(File file) {
    final icon = _fileIcon(file.path);

    final color = _fileIconColor(file.path);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(.10),
            ),
            child: Icon(icon, size: 34, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            path.extension(file.path).replaceFirst('.', '').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String filePath) {
    final ext = path.extension(filePath).toLowerCase();

    switch (ext) {
      case '.pdf':
        return Icons.picture_as_pdf_outlined;

      case '.doc':
      case '.docx':
        return Icons.description_outlined;

      case '.xls':
      case '.xlsx':
        return Icons.table_chart_outlined;

      case '.ppt':
      case '.pptx':
        return Icons.slideshow_outlined;

      case '.txt':
        return Icons.article_outlined;

      case '.zip':
      case '.rar':
      case '.7z':
        return Icons.folder_zip_outlined;

      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileIconColor(String filePath) {
    final ext = path.extension(filePath).toLowerCase();

    switch (ext) {
      case '.pdf':
        return Colors.red.shade400;

      case '.doc':
      case '.docx':
        return Colors.blue.shade500;

      case '.xls':
      case '.xlsx':
        return Colors.green.shade500;

      case '.ppt':
      case '.pptx':
        return Colors.orange.shade500;

      case '.zip':
      case '.rar':
      case '.7z':
        return Colors.deepPurple.shade400;

      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Widget _fileActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(.82),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: Icon(
              icon,
              size: 18,
              color: danger ? Colors.red.shade400 : colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Main build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !mounted) return;

        final shouldPop = await _confirmExit();

        if (!mounted || !shouldPop) return;

        _ignoreWindowClose = true;
        Navigator.of(context).pop({'id': _savedRecordId, 'scanned': false});
      },
      child: Scaffold(
        backgroundColor: const Color(0xffEEF3F8),

        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Colors.white.withOpacity(.82),
          surfaceTintColor: Colors.transparent,

          title: Text(
            widget.record == null ? 'ثبت نامه' : 'ویرایش نامه',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),

          centerTitle: false,

          actions: [
            _buildHistoryButton(),
            const SizedBox(width: 8),
            _buildReminderButton(),
            const SizedBox(width: 8),
            _buildAutoSaveButton(),
            const SizedBox(width: 12),
          ],

          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
              child: _buildGlassTabBar(),
            ),
          ),
        ),

        body: TabBarView(
          controller: _tabController,
          children: [_buildFormTab(), _buildFilesTab()],
        ),
      ),
    );
  }

  // ============================================================
  // Glass TabBar
  // ============================================================

  Widget _buildGlassTabBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.85)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          return TabBar(
            controller: _tabController,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: const EdgeInsets.all(5),
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: colorScheme.primary.withOpacity(.12),
              border: Border.all(color: colorScheme.primary.withOpacity(.16)),
            ),
            labelColor: colorScheme.primary,
            unselectedLabelColor: colorScheme.onSurface.withOpacity(.48),
            labelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(
                icon: Icon(Icons.edit_note_rounded, size: 19),
                text: 'اطلاعات فرم',
              ),
              Tab(
                icon: Icon(Icons.attach_file_rounded, size: 19),
                text: 'فایل‌ها',
              ),
            ],
          );
        },
      ),
    );
  }

  // ============================================================
  // Form tab
  // ============================================================

  Widget _buildFormTab() {
    return Container(
      color: const Color(0xffEEF3F8),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
          children: [
            _buildTodayReminderBanner(),
            // ==========================================================
            // شماره نامه + تاریخ
            // ==========================================================
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: buildTextField('Shomare_Radif')),

                const SizedBox(width: 8),

                Expanded(child: buildTextField('date')),
              ],
            ),

            // ==========================================================
            // سایر فیلدهای اصلی
            // ==========================================================
            buildTextField('saheb_name'),
            buildTextField('guy'),
            buildTextField('sh_name_reside'),
            buildTextField('onvan'),
            buildTextField('comment'),
            buildTextField('shomare_badi'),

            const SizedBox(height: 2),

            _buildOtherInformation(),

            const SizedBox(height: 4),

            _buildFormButtons(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Other information
  // ============================================================

  Widget _buildOtherInformation() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withOpacity(.52),
        border: Border.all(color: Colors.white.withOpacity(.82)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.primary.withOpacity(.09),
              ),
              child: Icon(
                Icons.tune_rounded,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
            title: const Text(
              'سایر اطلاعات',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            subtitle: Text(
              'اطلاعات تکمیلی نامه',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurface.withOpacity(.48),
              ),
            ),
            children: [
              buildCategoryField(),

              const SizedBox(height: 12),

              ...otherFields.map(buildTextField),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Form buttons
  // ============================================================

  Widget _buildFormButtons() {
    return Row(
      children: [
        if (widget.record == null) ...[
          Expanded(
            child: _glassButton(
              label: 'ذخیره و جدید',
              icon: Icons.add_rounded,
              onPressed: saveAndStay,
            ),
          ),
          const SizedBox(width: 9),
        ],

        if (!_autoSaveEnabled)
          Expanded(
            child: _glassButton(
              label: 'ذخیره',
              icon: Icons.check_rounded,
              onPressed: save,
              primary: true,
            ),
          ),

        const SizedBox(width: 9),

        Expanded(
          child: _glassButton(
            label: 'اسکن',
            icon: Icons.document_scanner_outlined,
            onPressed: scan,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Glass field
  // ============================================================
  InputDecoration _glassInputDecoration({
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    bool alignLabelWithHint = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: alignLabelWithHint,

      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,

      floatingLabelBehavior: FloatingLabelBehavior.auto,

      filled: true,
      fillColor: Colors.white.withOpacity(.68),

      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),

      labelStyle: TextStyle(
        color: colorScheme.onSurface.withOpacity(.58),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),

      floatingLabelStyle: TextStyle(
        color: colorScheme.primary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),

      hintStyle: TextStyle(
        color: colorScheme.onSurface.withOpacity(.28),
        fontSize: 12,
      ),

      hintTextDirection: TextDirection.rtl,

      prefixIconColor: colorScheme.onSurface.withOpacity(.40),

      suffixIconColor: colorScheme.primary.withOpacity(.65),

      border: _inputBorder(colorScheme.outline.withOpacity(.16)),

      enabledBorder: _inputBorder(colorScheme.outline.withOpacity(.16)),

      focusedBorder: _inputBorder(
        colorScheme.primary.withOpacity(.60),
        width: 1.4,
      ),

      errorBorder: _inputBorder(Colors.red.withOpacity(.50)),

      focusedErrorBorder: _inputBorder(Colors.red.withOpacity(.75), width: 1.4),

      errorStyle: const TextStyle(fontSize: 10, height: 1.1),
    );
  }

  OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),

      borderSide: BorderSide(color: color, width: width),

      gapPadding: 7,
    );
  }

  Widget _glassField({
    required Widget child,
    EdgeInsetsGeometry margin = const EdgeInsets.only(bottom: 7),
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(17),
        color: Colors.white.withOpacity(.38),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================
  // Glass button
  // ============================================================

  Widget _glassButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final foreground = primary ? colorScheme.onPrimary : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onPressed,
        child: Ink(
          height: 50,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),

            color: primary
                ? colorScheme.primary.withOpacity(.88)
                : Colors.white.withOpacity(.58),

            border: Border.all(
              color: primary
                  ? colorScheme.primary.withOpacity(.32)
                  : Colors.white.withOpacity(.82),
            ),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(primary ? .07 : .035),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: foreground),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Square glass button
  // ============================================================

  Widget _squareGlassButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onPressed,
          child: Ink(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: Colors.white.withOpacity(.58),
              border: Border.all(color: Colors.white.withOpacity(.82)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.035),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, size: 21, color: colorScheme.primary),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Glass container
  // ============================================================

  Widget _glassContainer({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
    double radius = 20,
    double opacity = .72,
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(.86), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.045),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  // ============================================================
  // Dialog
  // ============================================================

  Widget _glassDialog({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget content,
    required List<Widget> actions,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: _glassContainer(
        padding: const EdgeInsets.all(20),
        radius: 24,
        opacity: .94,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: iconColor.withOpacity(.09),
                  ),
                  child: Icon(icon, color: iconColor, size: 21),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    title,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            content,

            const SizedBox(height: 18),

            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required String label,
    required VoidCallback onPressed,
    bool danger = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onPressed,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: danger
                  ? Colors.red.withOpacity(.10)
                  : colorScheme.primary.withOpacity(.08),
              border: Border.all(
                color: danger
                    ? Colors.red.withOpacity(.16)
                    : colorScheme.primary.withOpacity(.14),
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: danger ? Colors.red.shade600 : colorScheme.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Utils
  // ============================================================

  bool _isImage(String filePath) {
    final ext = path.extension(filePath).toLowerCase();

    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext);
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: TextDirection.rtl),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Widget _buildAutoSaveButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final newValue = !_autoSaveEnabled;

            await AppSettings.setAutoSaveRecordForm(newValue);

            if (!mounted) return;

            setState(() {
              _autoSaveEnabled = newValue;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _autoSaveEnabled
                  ? colorScheme.primary.withOpacity(.10)
                  : Colors.black.withOpacity(.035),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _autoSaveEnabled
                    ? colorScheme.primary.withOpacity(.25)
                    : Colors.black.withOpacity(.07),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _autoSaveEnabled ? Icons.save : Icons.save_outlined,
                  size: 18,
                  color: _autoSaveEnabled
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(.50),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderButton() {
    final colorScheme = Theme.of(context).colorScheme;

    final activeColor = colorScheme.primary;
    final inactiveColor = colorScheme.onSurface.withOpacity(.50);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _openReminderDialog,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: _hasActiveReminder
              ? activeColor.withOpacity(.10)
              : Colors.black.withOpacity(.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hasActiveReminder
                ? activeColor.withOpacity(.25)
                : Colors.black.withOpacity(.07),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hasActiveReminder
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              size: 18,
              color: _hasActiveReminder ? activeColor : inactiveColor,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReminderDialog() async {
    int? recordId = _savedRecordId;

    // اگر نامه قبلاً ذخیره شده است
    if (recordId == null && widget.record != null) {
      final value = widget.record!['Shomare_Radif'];

      if (value != null) {
        recordId = value is int ? value : int.tryParse(value.toString());
      }
    }

    // اگر نامه جدید هنوز ذخیره نشده است،
    // ابتدا آن را ذخیره می‌کنیم تا ID داشته باشیم.
    if (recordId == null) {
      final saved = await _saveDataOnly();

      if (!saved || !mounted) {
        return;
      }

      recordId = _savedRecordId;
    }

    if (recordId == null || !mounted) {
      return;
    }

    final letterDateText = c['date']?.text.trim() ?? '';

    final letterDate = _parseLetterDate(letterDateText);

    if (letterDate == null) {
      _showMessage('تاریخ نامه معتبر نیست.');
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return ReminderDialog(recordId: recordId!, letterDate: letterDate);
      },
    );

    // وضعیت یادآور بعد از اضافه/حذف یادآور دوباره بررسی شود.
    await _loadReminderStatus();
  }

  DateTime? _parseLetterDate(String value) {
    try {
      final parts = value.trim().split(RegExp(r'[/\-.]'));

      if (parts.length != 3) {
        return null;
      }

      final year = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final day = int.parse(parts[2]);

      final jalali = Jalali(year, month, day);

      return jalali.toDateTime();
    } catch (e) {
      debugPrint('Parse letter date error: $e');
      return null;
    }
  }

  Future<void> _loadReminderStatus() async {
    int? recordId = _savedRecordId;

    if (recordId == null && widget.record != null) {
      final value = widget.record!['Shomare_Radif'];

      if (value != null) {
        recordId = value is int ? value : int.tryParse(value.toString());
      }
    }

    if (recordId == null) {
      if (!mounted) return;

      setState(() {
        _hasActiveReminder = false;
        _todayReminder = null;
      });

      return;
    }

    try {
      final reminders = await DatabaseHelper.getPendingRemindersForRecord(
        recordId,
      );

      final now = DateTime.now();

      final todayReminder = reminders.cast<Reminder?>().firstWhere(
        (reminder) =>
            reminder != null &&
            reminder.dueDate.year == now.year &&
            reminder.dueDate.month == now.month &&
            reminder.dueDate.day == now.day,
        orElse: () => null,
      );

      if (!mounted) return;

      setState(() {
        _hasActiveReminder = reminders.isNotEmpty;
        _todayReminder = todayReminder;
      });
    } catch (e, stackTrace) {
      debugPrint('load reminder status error: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Widget _buildTodayReminderBanner() {
    final reminder = _todayReminder;

    if (reminder == null || !reminder.isPending) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withOpacity(.25)),
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
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.orange,
                  size: 21,
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'موعد پیگیری این نامه امروز است',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      reminder.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(.68),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              // تمدید
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _extendTodayReminder(reminder);
                  },
                  icon: const Icon(Icons.update_rounded, size: 17),
                  label: const Text('تمدید'),
                ),
              ),

              const SizedBox(width: 8),

              // انجام شد
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await _completeTodayReminder(reminder);
                  },
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: const Text('انجام شد'),
                ),
              ),

              const SizedBox(width: 8),

              // مدیریت یادآور
              IconButton(
                tooltip: 'مدیریت یادآور',
                onPressed: _openReminderDialog,
                icon: const Icon(Icons.more_horiz_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _completeTodayReminder(Reminder reminder) async {
    if (reminder.id == null) return;

    try {
      await NotificationService.instance.cancelReminder(reminder.id!);

      await DatabaseHelper.completeReminder(reminder.id!);

      _reminderChanged = true;

      await _loadReminderStatus();

      if (!mounted) return;

      _showMessage('پیگیری نامه انجام شد.');
    } catch (e, stackTrace) {
      debugPrint('complete today reminder error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showMessage('خطا در انجام یادآور:\n$e');
    }
  }

  Future<void> _extendTodayReminder(Reminder reminder) async {
    if (reminder.id == null) return;

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

                const SizedBox(height: 18),

                Row(
                  children: [
                    Expanded(child: _buildExtendOption(context, 7)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildExtendOption(context, 15)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildExtendOption(context, 30)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selectedDays == null) return;

    try {
      final now = DateTime.now();

      // چون موعد امروز/گذشته است،
      // تمدید از امروز محاسبه می‌شود.
      final rawDate = now.add(Duration(days: selectedDays));

      final newDueDate = DateTime(
        rawDate.year,
        rawDate.month,
        rawDate.day,
        9,
        0,
      );

      await NotificationService.instance.cancelReminder(reminder.id!);

      final updatedReminder = reminder.copyWith(
        dueDate: newDueDate,
        status: ReminderStatus.pending,
        completedAt: null,
      );

      await DatabaseHelper.updateReminder(updatedReminder);

      await NotificationService.instance.scheduleReminder(
        reminderId: reminder.id!,
        recordId: reminder.recordId,
        dueDate: newDueDate,
        text: reminder.text,
      );

      _reminderChanged = true;
      await _loadReminderStatus();

      if (!mounted) return;

      _showMessage('پیگیری برای $selectedDays روز تمدید شد.');
    } catch (e, stackTrace) {
      debugPrint('extend today reminder error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showMessage('خطا در تمدید یادآور:\n$e');
    }
  }

  Widget _buildExtendOption(BuildContext context, int days) {
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

  Future<void> _saveCategoryHistory(int recordId) async {
    final oldCategories = List<String>.from(_initialCategories);

    final newCategories = List<String>.from(selectedCategories);

    final oldValue = oldCategories.join('، ');
    final newValue = newCategories.join('، ');

    if (oldValue == newValue) {
      return;
    }

    await DatabaseHelper.addRecordHistory(
      recordId: recordId,
      action: 'categories',
      fieldName: 'دسته‌بندی',
      oldValue: oldValue,
      newValue: newValue,
    );
  }

  Future<void> _showRecordHistory() async {
    final rawId = widget.record?['Shomare_Radif'];

    if (rawId == null) {
      return;
    }

    final recordId = rawId is int ? rawId : int.tryParse(rawId.toString());

    if (recordId == null) {
      _showMessage('شماره نامه معتبر نیست.');
      return;
    }

    await showDialog(
      context: context,
      builder: (_) {
        return RecordHistoryDialog(recordId: recordId);
      },
    );
  }

  Widget _buildHistoryButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _showRecordHistory,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.035),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black.withOpacity(.07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 18,
              color: colorScheme.onSurface.withOpacity(.50),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
    if (Platform.isWindows) {
      try {
        windowManager.removeListener(this);
        windowManager.setPreventClose(false);
      } catch (e) {
        debugPrint('Window close protection dispose error: $e');
      }
    }

    _debounce?.cancel();
    _debounceGuy?.cancel();
    _debounceOnvan?.cancel();
    _debounceCategory?.cancel();

    for (final controller in c.values) {
      controller.dispose();
    }

    for (final node in focusNodes.values) {
      node.dispose();
    }

    categoryController.dispose();
    categoryFocus.dispose();
    _firstFieldFocus.dispose();

    _tabController.dispose();

    _scanSubscription?.cancel();

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
}
