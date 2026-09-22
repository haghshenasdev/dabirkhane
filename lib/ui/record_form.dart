import 'dart:async';
import 'dart:io';

import 'package:dabirkhane/model/reminder.dart';
import 'package:dabirkhane/providers/scan_service.dart';
import 'package:dabirkhane/ui/dialogs/record_history_dialog.dart';
import 'package:dabirkhane/ui/dialogs/share_record_dialog.dart';
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
import '../model/field_definition.dart';
import '../services/schema_service.dart';

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
  Timer? _historySuggestionDebounce;

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
  bool _compactFilesOnForm = false;
  bool _hasActiveReminder = false;
  Reminder? _todayReminder;

  // ============================================================
  // Fields
  // ============================================================

  List<String> mainFields = [
    'Shomare_Radif', 'date', 'saheb_name', 'guy',
    'sh_name_reside', 'onvan', 'comment', 'shomare_badi',
  ];

  List<String> otherFields = [
    't_name_ersali', 't_name_reside', 'wordmost2', 'from_pywa',
    'adres_name', 'goshashte',
  ];

  RecordSchema? _schema;
  bool _schemaLoading = false;

  final Map<String, List<String>> _dynamicSuggestions = {};
  final Map<String, Timer> _dynamicSuggestionTimers = {};

  Map<String, String> fieldLabels = {
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

    final cachedSchema = SchemaService.cached;
    if (cachedSchema != null) {
      _applySchema(cachedSchema);
      if (widget.record == null) {
        _setInitialValues();
      } else {
        _captureInitialState();
      }
    } else {
      _loadSchema();
    }

    _loadSuggestionSettings();
    _loadAutoSaveSetting();
    _loadScanSettings();
    _loadCompactFilesSetting();
    _loadReminderStatus();

    if (widget.record != null) {
      _loadFiles();
      _loadCategories();
    }

    _initWindowCloseProtection();
  }

  void _applySchema(RecordSchema schema) {
    final labels = <String, String>{
      for (final field in schema.fields) field.key: field.label,
    };

    final dataFields = schema.fields
        .where((f) => f.visible && f.key != '__category__')
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final field in dataFields) {
      c.putIfAbsent(
        field.key,
        () => TextEditingController(
          text: widget.record?[field.key]?.toString() ?? '',
        ),
      );
      focusNodes.putIfAbsent(field.key, FocusNode.new);
    }

    _schema = schema;
    mainFields = dataFields.map((f) => f.key).toList();
    otherFields = <String>[];
    fieldLabels = labels;
    _schemaLoading = false;
  }

  Future<void> _loadSchema() async {
    try {
      final schema = await SchemaService.preload();
      if (schema == null || !mounted) return;

      _applySchema(schema);
      setState(() {});

      if (widget.record != null) {
        _captureInitialState();
      } else {
        await _setInitialValues();
      }
    } catch (e) {
      debugPrint('Schema load error: $e');
      if (mounted) setState(() => _schemaLoading = false);
    }
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
        if (field != '__category__') field: c[field]?.text ?? '',
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
          if (field != '__category__') field: c[field]!.text,
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

  Future<void> _loadCompactFilesSetting() async {
    final value = await AppSettings.getCompactFilesOnForm();
    if (!mounted) return;
    setState(() => _compactFilesOnForm = value);
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

    if (c.containsKey('date')) {
      c['date']!.text =
          '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    }

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
          if (field != '__category__') field: c[field]!.text,
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

  Future<void> shareRecord() async {
    if (!mounted) return;

    // نامه جدیدی که هنوز ذخیره نشده است، مقدار نهایی دیتابیس را ندارد.
    // برای جلوگیری از اشتراک‌گذاری اطلاعات ناقص ابتدا ذخیره می‌کنیم.
    if (_hasUnsavedChanges) {
      final saved = await _saveDataOnly();
      if (!saved || !mounted) return;
    }

    final recordId = _savedRecordId ??
        (widget.record?['Shomare_Radif'] is int
            ? widget.record!['Shomare_Radif'] as int
            : int.tryParse(
                  widget.record?['Shomare_Radif']?.toString() ?? '',
                ) ??
                int.tryParse(c['Shomare_Radif']?.text ?? ''));

    if (recordId == null) {
      _showMessage('شماره نامه مشخص نیست.');
      return;
    }

    final result = await showDialog<ShareRecordResult>(
      context: context,
      builder: (_) => ShareRecordDialog(
        record: widget.record ?? <String, dynamic>{
          for (final entry in c.entries) entry.key: entry.value.text,
        },
        categories: selectedCategories,
      ),
    );

    if (result == null || !mounted) return;

    final values = <String>[];
    final currentRecord = await DatabaseHelper.getById(recordId);

    if (currentRecord == null) {
      _showMessage('اطلاعات نامه برای اشتراک‌گذاری پیدا نشد.');
      return;
    }

    for (final field in result.fields) {
      final value = field.key == '__category__'
          ? selectedCategories.join('، ')
          : currentRecord[field.key]?.toString().trim() ?? '';

      if (value.isEmpty) continue;

      values.add('${field.label}: $value');
    }

    final text = values.join('\n');

    if (result.includeFiles) {
      await _loadFiles();
    }

    final files = result.includeFiles
        ? filesInDirectory
            .where((file) => file.existsSync())
            .map((file) => XFile(file.path))
            .toList()
        : <XFile>[];

    final subject =
        'نامه شماره ${currentRecord['Shomare_Radif'] ?? recordId}';

    try {
      if (files.isNotEmpty) {
        await Share.shareXFiles(
          files,
          subject: subject,
          text: text.isEmpty ? subject : text,
        );
      } else {
        await Share.share(
          text.isEmpty ? subject : text,
          subject: subject,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage('خطا در اشتراک‌گذاری نامه:\n$e');
    }
  }

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
      icon: _fieldIcon(_schema?.field('guy')),
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
      icon: _fieldIcon(_schema?.field('onvan')),
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
    IconData? icon,
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
              prefixIcon: icon == null ? null : Icon(icon, size: 20),
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

  Widget _buildHistorySuggestionField(FieldDefinition definition) {
    final config = _schema!.historySuggestion;
    final suggestions = _dynamicSuggestions[definition.key] ?? const <String>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassField(
          child: TextFormField(
            controller: c[definition.key],
            focusNode: focusNodes[definition.key],
            decoration: _glassInputDecoration(
              label: definition.label,
              prefixIcon: Icon(_fieldIcon(definition), size: 20),
              suffixIcon: suggestions.isNotEmpty
                  ? IconButton(
                      tooltip: 'بستن سابقه',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _dynamicSuggestions[definition.key] = [];
                        });
                      },
                    )
                  : null,
            ),
            textDirection: TextDirection.rtl,
            minLines: 1,
            maxLines: definition.maxLines.clamp(1, 3).toInt(),
            keyboardType: TextInputType.text,
            validator: definition.required
                ? (value) => value == null || value.trim().isEmpty
                    ? 'این فیلد الزامی است'
                    : null
                : null,
            onChanged: (value) {
              _historySuggestionDebounce?.cancel();

              if (value.trim().isEmpty) {
                setState(() {
                  _dynamicSuggestions[definition.key] = [];
                });
                return;
              }

              _historySuggestionDebounce = Timer(
                const Duration(milliseconds: 350),
                () async {
                  try {
                    final rows =
                        await DatabaseHelper.searchDistinctField(
                      config.searchField ?? definition.key,
                      value.trim(),
                    );

                    if (!mounted ||
                        _schema?.historySuggestion.targetField !=
                            definition.key) {
                      return;
                    }

                    setState(() {
                      _dynamicSuggestions[definition.key] = rows;
                    });
                  } catch (e) {
                    debugPrint('History suggestion error: $e');
                  }
                },
              );
            },
            onFieldSubmitted: (_) {
              if (suggestions.isNotEmpty) {
                _selectHistorySuggestion(
                  definition,
                  suggestions.first,
                );
              } else {
                _focusNextField(definition.key);
              }
            },
          ),
        ),
        if (suggestions.isNotEmpty)
          _glassSuggestions(
            suggestions: suggestions,
            icon: Icons.history_rounded,
            onSelected: (item) {
              _selectHistorySuggestion(definition, item);
            },
          ),
        if (lastInfoText != null &&
            lastRecord != null &&
            config.targetField == definition.key)
          _buildLastRecordCard(),
      ],
    );
  }

  Future<void> _selectHistorySuggestion(
    FieldDefinition definition,
    String value,
  ) async {
    final config = _schema!.historySuggestion;
    final searchField = config.searchField ?? definition.key;

    try {
      final last = await DatabaseHelper.getLastRecordByField(
        searchField,
        value,
      );

      if (last != null) {
        final targetValue = last[definition.key]?.toString() ?? value;
        c[definition.key]!.text = targetValue;

        if (definition.key == 'saheb_name' &&
            c.containsKey('sh_name_reside')) {
          c['sh_name_reside']!.text =
              last['sh_name_reside']?.toString() ?? '';
        }

        lastRecord = last;
        lastInfoText = _buildLastRecordInfo(last);
      } else {
        c[definition.key]!.text = value;
        lastRecord = null;
        lastInfoText = null;
      }
    } catch (e) {
      c[definition.key]!.text = value;
      debugPrint('Load last record error: $e');
      lastRecord = null;
      lastInfoText = null;
    }

    if (!mounted) return;

    setState(() {
      _dynamicSuggestions[definition.key] = [];
    });

  }

  String _buildLastRecordInfo(Map<String, dynamic> record) {
    final config = _schema?.historySuggestion;
    if (config == null) return '';

    final parts = <String>[];

    for (final key in config.displayFields) {
      final definition = _schema?.field(key);
      final value = record[key]?.toString().trim() ?? '';

      if (value.isEmpty) continue;

      final label = definition?.label ?? fieldLabels[key] ?? key;
      parts.add('$label: $value');
    }

    return parts.join('  |  ');
  }

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
              prefixIcon: Icon(_fieldIcon(_schema?.field('saheb_name')), size: 20),
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
    _historySuggestionDebounce?.cancel();

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
                if (c.containsKey('sh_name_reside')) {
                  c['sh_name_reside']!.text =
                      last['sh_name_reside']?.toString() ?? '';
                }

                lastRecord = last;

                lastInfoText = _buildLastRecordInfo(last);
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
  Widget buildCategoryField([FieldDefinition? definition]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _glassField(
          margin: EdgeInsets.zero,
          child: TextFormField(
            controller: categoryController,
            focusNode: categoryFocus,
            decoration: _glassInputDecoration(
              label: definition?.label ?? 'دسته‌بندی',
              prefixIcon: Icon(_fieldIcon(definition), size: 20),

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
        color: Theme.of(context).colorScheme.surface.withOpacity(.82),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.12)),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(.84),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.12)),
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

  IconData _fieldIcon(FieldDefinition? definition) {
    const icons = <String, IconData>{
      'text': Icons.text_fields_outlined,
      'subject': Icons.subject_outlined,
      'person': Icons.person_outline,
      'person_outline': Icons.person_outline,
      'numbers': Icons.numbers_outlined,
      'event': Icons.event_outlined,
      'event_note': Icons.event_note_outlined,
      'phone': Icons.phone_outlined,
      'email': Icons.email_outlined,
      'notes': Icons.notes_outlined,
      'description': Icons.description_outlined,
      'attach_file': Icons.attach_file_outlined,
      'location_on': Icons.location_on_outlined,
      'label': Icons.label_outline,
      'history': Icons.history_outlined,
      'forward': Icons.forward_outlined,
      'link': Icons.link_outlined,
      'check_circle': Icons.check_circle_outline,
    };
    final code = definition?.icon;
    if (code != null && icons.containsKey(code)) return icons[code]!;
    final parsed = int.tryParse(code ?? '');
    if (parsed != null) return IconData(parsed, fontFamily: 'MaterialIcons');
    switch (definition?.type) {
      case FieldType.date:
      case FieldType.datetime:
        return Icons.calendar_today_outlined;
      case FieldType.number:
        return Icons.numbers_outlined;
      case FieldType.boolean:
        return Icons.toggle_on_outlined;
      case FieldType.select:
      case FieldType.multiselect:
        return Icons.list_alt_outlined;
      case FieldType.phone:
        return Icons.phone_outlined;
      case FieldType.email:
        return Icons.email_outlined;
      case FieldType.url:
        return Icons.link_outlined;
      case FieldType.multiline:
        return Icons.notes_outlined;
      case FieldType.category:
        return Icons.label_outline_rounded;
      case FieldType.file:
        return Icons.attach_file_outlined;
      case FieldType.text:
      case null:
        return Icons.text_fields_outlined;
    }
  }

  Widget buildTextField(String field) {
    final definition = _schema?.field(field);

    if (field == '__category__' || definition?.type == FieldType.category) {
      return buildCategoryField(definition);
    }

    final historyConfig = _schema?.historySuggestion;
    if (historyConfig?.enabled == true &&
        historyConfig?.targetField == field) {
      return _buildHistorySuggestionField(definition!);
    }

    if (field == 'saheb_name' && definition?.suggestions != false) {
      return buildSahebNameField();
    }
    if (field == 'guy' && definition?.suggestions != false) {
      return buildGuyField();
    }
    if (field == 'onvan' && definition?.suggestions != false) {
      return buildOnvanField();
    }

    if (definition?.type == FieldType.select) {
      return _buildSelectField(definition!);
    }
    if (definition?.type == FieldType.multiselect) {
      return _buildMultiSelectField(definition!);
    }
    if (definition?.type == FieldType.boolean) {
      return _buildBooleanField(definition!);
    }
    if (definition?.type == FieldType.date || field == 'date') {
      return _buildDynamicDateField(field, definition);
    }
    if (definition?.suggestions == true) {
      return _buildDynamicAutocompleteField(definition!);
    }

    final isMultiline = definition?.type == FieldType.multiline || field == 'comment' || field == 'adres_name';
    final maxLines = definition?.maxLines ?? (isMultiline ? 4 : 3);
    final keyboardType = definition?.type == FieldType.number
        ? TextInputType.number
        : definition?.type == FieldType.phone
            ? TextInputType.phone
            : definition?.type == FieldType.email
                ? TextInputType.emailAddress
                : definition?.type == FieldType.url
                    ? TextInputType.url
                    : isMultiline
                        ? TextInputType.multiline
                        : TextInputType.text;

    return _glassField(
      child: TextFormField(
        controller: c[field],
        focusNode: focusNodes[field],
        minLines: 1,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: _glassInputDecoration(
          label: definition?.label ?? fieldLabels[field] ?? field,
          prefixIcon: Icon(_fieldIcon(definition), size: 20),
          alignLabelWithHint: isMultiline,
        ),
        textDirection: TextDirection.rtl,
        validator: definition?.required == true
            ? (value) => (value == null || value.trim().isEmpty) ? 'این فیلد الزامی است' : null
            : null,
        onFieldSubmitted: (_) => _focusNextField(field),
      ),
    );
  }

  void _focusNextField(String field) {
    final all = [...mainFields, ...otherFields];
    final index = all.indexOf(field);
    if (index >= 0 && index < all.length - 1) {
      FocusScope.of(context).requestFocus(focusNodes[all[index + 1]]);
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  Widget _buildDynamicDateField(String field, FieldDefinition? definition) {
    return _glassField(
      child: TextFormField(
        controller: c[field],
        focusNode: focusNodes[field],
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, JalaliDateFormatter()],
        decoration: _glassInputDecoration(
          label: definition?.label ?? fieldLabels[field] ?? field,
          hint: '1405/01/15',
          prefixIcon: Icon(_fieldIcon(definition), size: 20),
        ),
        textDirection: TextDirection.rtl,
        validator: (value) {
          if (definition?.required == true && (value == null || value.trim().isEmpty)) return 'این فیلد الزامی است';
          if (value != null && value.trim().isNotEmpty && value.length != 10) return 'تاریخ معتبر وارد کنید';
          return null;
        },
        onFieldSubmitted: (_) => _focusNextField(field),
      ),
    );
  }

  Widget _buildSelectField(FieldDefinition definition) {
    return _glassField(
      child: DropdownButtonFormField<String>(
        value: definition.options.contains(c[definition.key]?.text) ? c[definition.key]?.text : null,
        decoration: _glassInputDecoration(label: definition.label, prefixIcon: Icon(_fieldIcon(definition), size: 20)),
        items: definition.options.map((item) => DropdownMenuItem(value: item, child: Text(item, textDirection: TextDirection.rtl))).toList(),
        onChanged: (value) => c[definition.key]?.text = value ?? '',
        validator: definition.required ? (value) => value == null || value.isEmpty ? 'این فیلد الزامی است' : null : null,
      ),
    );
  }

  Widget _buildMultiSelectField(FieldDefinition definition) {
    final selected = (c[definition.key]?.text ?? '').split('|').where((e) => e.isNotEmpty).toSet();
    return _glassField(
      child: InkWell(
        onTap: () async {
          final temp = {...selected};
          final result = await showDialog<Set<String>>(
            context: context,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                title: Text(definition.label, textDirection: TextDirection.rtl),
                content: SingleChildScrollView(child: Column(children: definition.options.map((item) => CheckboxListTile(
                  value: temp.contains(item), title: Text(item, textDirection: TextDirection.rtl),
                  onChanged: (v) => setState(() => v == true ? temp.add(item) : temp.remove(item)),
                )).toList())),
                actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(dialogContext, temp), child: const Text('تأیید'))],
              ),
            ),
          );
          if (result != null) setState(() => c[definition.key]!.text = result.join('|'));
        },
        child: InputDecorator(
          decoration: _glassInputDecoration(label: definition.label, prefixIcon: Icon(_fieldIcon(definition), size: 20)),
          child: Text(selected.isEmpty ? 'انتخاب کنید' : selected.join('، '), textDirection: TextDirection.rtl),
        ),
      ),
    );
  }

  Widget _buildBooleanField(FieldDefinition definition) {
    final value = c[definition.key]?.text == '1';
    return _glassField(
      child: SwitchListTile.adaptive(
        title: Text(definition.label, textDirection: TextDirection.rtl),
        secondary: Icon(_fieldIcon(definition)),
        value: value,
        onChanged: (v) => setState(() => c[definition.key]!.text = v ? '1' : '0'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  Widget _buildDynamicAutocompleteField(FieldDefinition definition) {
    final suggestions = _dynamicSuggestions[definition.key] ?? const <String>[];
    return buildSimpleAutoCompleteField(
      field: definition.key,
      label: definition.label,
      suggestions: suggestions,
      onChanged: (value) {
        _dynamicSuggestionTimers[definition.key]?.cancel();
        if (!definition.suggestions || value.trim().isEmpty) {
          if (mounted) setState(() => _dynamicSuggestions[definition.key] = []);
          return;
        }
        _dynamicSuggestionTimers[definition.key] = Timer(const Duration(milliseconds: 350), () async {
          try {
            final result = await DatabaseHelper.searchDistinctField(definition.key, value.trim());
            if (mounted) setState(() => _dynamicSuggestions[definition.key] = result);
          } catch (_) {}
        });
      },
      onSelected: (item) => setState(() { c[definition.key]!.text = item; _dynamicSuggestions[definition.key] = []; }),
      focusNode: focusNodes[definition.key]!,
      nextFocus: null,
      icon: _fieldIcon(definition),
    );
  }

  // ============================================================
  Widget _buildCompactFilesCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.035),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(.10),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.attach_file_rounded,
                    color: colorScheme.primary, size: 19),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text('پیوست‌ها',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              _compactFileAction(
                'اسکن',
                Icons.document_scanner_outlined,
                scan,
                showLabel: true,
              ),
              _compactFileAction(
                'افزودن فایل',
                Icons.attach_file_rounded,
                addFileForRecord,
                showLabel: true,
              ),
            ],
          ),
          if (filesInDirectory.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 58,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                reverse: true,
                itemCount: filesInDirectory.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final file = filesInDirectory[index];
                  final image = _isImage(file.path);
                  return InkWell(
                    borderRadius: BorderRadius.circular(13),
                    onTap: () => openFile(file),
                    child: Container(
                      width: 205,
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(.025),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: Colors.black.withOpacity(.055)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: SizedBox(
                              width: 43,
                              height: 43,
                              child: image
                                  ? Image.file(file, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _filePreviewIcon(file))
                                  : _filePreviewIcon(file),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              path.basename(file.path),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Icon(Icons.open_in_new_rounded,
                              size: 15, color: colorScheme.primary),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.only(top: 5),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('هنوز فایلی برای این نامه ثبت نشده است.',
                    style: TextStyle(fontSize: 10.5), textDirection: TextDirection.rtl),
              ),
            ),
        ],
      ),
    );
  }

  Widget _compactFileAction(
    String tooltip,
    IconData icon,
    VoidCallback onPressed, {
    bool showLabel = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    if (showLabel) {
      return Material(
        color: colorScheme.primary.withOpacity(.07),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  tooltip,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }

  // FILE TAB
  // ============================================================

  Widget _buildFilesTab() {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
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
        color: Theme.of(context).colorScheme.surface.withOpacity(.82),
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
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,

        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(.82),
          surfaceTintColor: Colors.transparent,

          title: Text(
            widget.record == null ? 'ثبت نامه' : 'ویرایش نامه',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),

          centerTitle: false,

          actions: [
            _buildShareButton(),
            const SizedBox(width: 8),
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
        bottomNavigationBar: AnimatedBuilder(
          animation: _tabController,
          builder: (context, child) {
            if (_tabController.index != 0) return const SizedBox.shrink();
            if (_autoSaveEnabled && _compactFilesOnForm && widget.record != null) {
              return const SizedBox.shrink();
            }
            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withOpacity(.92),
                  border: Border(
                    top: BorderSide(color: Colors.black.withOpacity(.06)),
                  ),
                ),
                child: _buildFormButtons(),
              ),
            );
          },
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
        color: Theme.of(context).colorScheme.surface.withOpacity(.62),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.12)),
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
    if (_schemaLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final schema = _schema;
    if (schema == null) {
      return const Center(child: Text('ساختار فرم یافت نشد', textDirection: TextDirection.rtl));
    }

    final sections = [...schema.sections]..sort((a, b) => a.order.compareTo(b.order));

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
          children: [
            _buildTodayReminderBanner(),
            if (_compactFilesOnForm) _buildCompactFilesCard(),
            ...sections.map(_buildDynamicSection),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicSection(FormSectionDefinition section) {
    final fields = section.fields.where((key) {
      final definition = _schema?.field(key);
      return definition != null && definition.visible;
    }).toList();

    if (fields.isEmpty) return const SizedBox.shrink();

    final columns = section.columns.clamp(1, 3).toInt();
    final rows = <List<String>>[];
    var current = <String>[];
    var used = 0;

    void flush() {
      if (current.isNotEmpty) rows.add(current);
      current = <String>[];
      used = 0;
    }

    for (final key in fields) {
      final definition = _schema!.field(key)!;
      final span = definition.gridSpan.clamp(1, columns).toInt();
      if (used > 0 && used + span > columns) flush();
      current.add(key);
      used += span;
      if (used >= columns) flush();
    }
    flush();

    Widget buildRow(List<String> row) {
      final children = <Widget>[];
      var usedColumns = 0;
      for (final key in row) {
        final definition = _schema!.field(key)!;
        final span = definition.gridSpan.clamp(1, columns).toInt();
        if (children.isNotEmpty) children.add(const SizedBox(width: 8));
        children.add(Expanded(flex: span, child: buildTextField(key)));
        usedColumns += span;
      }
      if (usedColumns < columns) children.add(const Spacer());
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    final content = Column(
      children: [
        for (final row in rows) ...[
          buildRow(row),
          const SizedBox(height: 8),
        ],
      ],
    );

    if (!section.collapsible) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(2),
        child: content,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Theme.of(context).colorScheme.surface.withOpacity(.52),
        border: Border.all(color: Theme.of(context).colorScheme.surface.withOpacity(.82)),
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
            tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: colorScheme.primary.withOpacity(.09),
              ),
              child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 20),
            ),
            title: Text(
              section.title,
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            children: [content],
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

        if (!_compactFilesOnForm)
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
      fillColor: Theme.of(context).colorScheme.surface.withOpacity(.68),

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
        color: Theme.of(context).colorScheme.surface.withOpacity(.38),
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
                : Theme.of(context).colorScheme.surface.withOpacity(.58),

            border: Border.all(
              color: primary
                  ? colorScheme.primary.withOpacity(.32)
                  : Theme.of(context).colorScheme.surface.withOpacity(.82),
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
              color: Theme.of(context).colorScheme.surface.withOpacity(.58),
              border: Border.all(color: Theme.of(context).colorScheme.surface.withOpacity(.82)),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Theme.of(context).colorScheme.surface.withOpacity(.86), width: 1),
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

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildExtendOption(context, 7),
                    _buildExtendOption(context, 15),
                    _buildExtendOption(context, 30),
                    _buildCustomExtendOption(context),
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

  Widget _buildCustomExtendOption(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final controller = TextEditingController();
        final value = await showDialog<int>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('تعداد روز دلخواه', textDirection: TextDirection.rtl),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              textDirection: TextDirection.rtl,
              decoration: const InputDecoration(labelText: 'تعداد روز'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () {
                  final days = int.tryParse(controller.text.trim());
                  if (days != null && days > 0) {
                    Navigator.pop(dialogContext, days);
                  }
                },
                child: const Text('تأیید'),
              ),
            ],
          ),
        );
        controller.dispose();
        if (value == null || !mounted) return;
        Navigator.pop(context, value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.secondary.withOpacity(.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.secondary.withOpacity(.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.edit_calendar_rounded, color: colorScheme.secondary),
            const SizedBox(width: 6),
            const Text('دلخواه', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
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

  Widget _buildShareButton() {
    return IconButton(
      tooltip: 'اشتراک‌گذاری نامه',
      icon: const Icon(Icons.share_outlined),
      onPressed: shareRecord,
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
    for (final timer in _dynamicSuggestionTimers.values) {
      timer.cancel();
    }

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
