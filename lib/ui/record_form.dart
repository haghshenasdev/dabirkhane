import 'dart:async';
import 'dart:io';

import 'package:dabirkhane/providers/scan_service.dart';
import 'package:dabirkhane/utils/letter_file_organizer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

    for (final field in [...mainFields, ...otherFields]) {
      c[field] = TextEditingController(
        text: widget.record?[field]?.toString() ?? '',
      );

      focusNodes[field] = FocusNode();
    }

    if (widget.record == null) {
      _setInitialValues();
    } else {
      _loadFiles();
      _loadCategories();
    }
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

    await _loadFiles();

    if (!mounted) {
      return;
    }

    _showMessage('فایل اسکن شده با موفقیت اضافه شد.');
  }

  // ============================================================
  // Initial values
  // ============================================================

  void _setInitialValues() {
    final now = Jalali.now();

    c['date']!.text =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';

    _setDefaultShomareRadif();
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

      if (!mounted) return;

      Navigator.pop(context, id);
    } catch (e, stackTrace) {
      debugPrint('save error: $e');

      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      _showMessage('خطا در ذخیره اطلاعات:\n$e');
    }
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

      _setInitialValues();

      c['date']?.text = lastDate;

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

      await ScanService.startScan(id,c['date']?.text.trim(),);
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
              suffixIcon: categoryController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.add_rounded),
                      onPressed: () {
                        _addCategory(categoryController.text);
                      },
                    )
                  : null,
            ),
            textDirection: TextDirection.rtl,
            onChanged: (value) {
              _debounceCategory?.cancel();

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
    return Scaffold(
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

  // ============================================================
  // Dispose
  // ============================================================

  @override
  void dispose() {
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
