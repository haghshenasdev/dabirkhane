import 'dart:async';
import 'dart:io';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:dabirkhane/pages/scanner_page.dart';

import '../utils/JalaliDateFormatter.dart';
import '../utils/app_settings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import '../db/database_helper.dart';
import 'package:shamsi_date/shamsi_date.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

class RecordForm extends StatefulWidget {
  final Map<String, dynamic>? record;
  RecordForm({this.record});

  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> c = {};
  Map<String, dynamic>? lastRecord;
  String? lastInfoText;
  List<String> guySuggestions = [];
  List<String> onvanSuggestions = [];
  Timer? _debounceGuy;
  Timer? _debounceOnvan;
  final Map<String, FocusNode> focusNodes = {};
  List<File> filesInDirectory = [];
  late TabController _tabController;
  List<String> sahebSuggestions = [];
  Timer? _debounce;
  final FocusNode _firstFieldFocus = FocusNode();

  //دسته بندی
  List<String> selectedCategories = [];
  List<String> categorySuggestions = [];
  Timer? _debounceCategory;
  final TextEditingController categoryController = TextEditingController();
  final FocusNode categoryFocus = FocusNode();

  final mainFields = [
    'Shomare_Radif',
    'date',
    'saheb_name',
    'guy',
    'sh_name_reside',
    'onvan',
  ];

  final otherFields = [
    'comment',
    't_name_ersali',
    'shomare_badi',
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    for (var f in [...mainFields, ...otherFields]) {
      c[f] = TextEditingController(text: widget.record?[f]?.toString() ?? '');
      focusNodes[f] = FocusNode();
    }

    if (widget.record == null) {
      _setInitialValues();
    } else {
      _loadFiles(); // بارگذاری فایل‌ها
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    final recordId = widget.record!['Shomare_Radif'].toString();

    final cats = await DatabaseHelper.getCategoriesForRecord(recordId);

    setState(() {
      selectedCategories = cats;
    });
  }

  void _setInitialValues() {
    final now = Jalali.now();
    c['date']!.text =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    _setDefaultShomareRadif();
  }

  Future<void> _setDefaultShomareRadif() async {
    final lastNumber = await DatabaseHelper.getLastShomareRadif();
    final nextNumber = (lastNumber ?? 0) + 1;
    c['Shomare_Radif']!.text = nextNumber.toString();
  }

  // بارگذاری فایل‌ها از پوشه 'letters'
  Future<void> _loadFiles() async {
    final shomareRadifRaw = c['Shomare_Radif']?.text ?? '';
    final shomareRadif = normalizeNumbers(shomareRadifRaw.trim());

    if (shomareRadif.isEmpty) {
      setState(() {
        filesInDirectory = [];
      });
      return;
    }

    final lettersDir = await getLettersDirectory();

    if (!await lettersDir.exists()) {
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
        if (entity is File) {
          final nameRaw = path.basenameWithoutExtension(entity.path);
          final name = normalizeNumbers(nameRaw);

          if (regex.hasMatch(name)) {
            matchedFiles.add(entity);
          }
        }
      }

      if (mounted) {
        setState(() {
          filesInDirectory = matchedFiles;
        });
      }
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

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      for (var f in [...mainFields, ...otherFields]) f: c[f]!.text,
    };

    if (widget.record == null) {
      await DatabaseHelper.insert(data);
    } else {
      await DatabaseHelper.update(widget.record!['Shomare_Radif'], data);
    }

    await DatabaseHelper.saveCategoriesForRecord(
      c['Shomare_Radif']!.text,
      selectedCategories,
    );

    Navigator.pop(context, true);
  }

  Future<Directory> getLettersDirectory() async {
    final lettersDir = await AppSettings.getLettersDirectory();
    if (!await lettersDir.exists()) {
      await lettersDir.create();
    }
    return lettersDir;
  }

  // تابع برای باز کردن فایل
  Future<void> openFile(File file) async {
    // برای باز کردن فایل با استفاده از اپلیکیشن‌های پیش‌فرض دستگاه
    final result = await OpenFile.open(file.path);

    if (result.type != ResultType.done) {
      // اگر باز کردن فایل با خطا مواجه شد، می‌توانید این پیام را نمایش دهید
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطا در باز کردن فایل')));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceGuy?.cancel();
    _debounceOnvan?.cancel();
    _debounceCategory?.cancel();

    for (var controller in c.values) {
      controller.dispose();
    }

    for (var node in focusNodes.values) {
      node.dispose();
    }

    categoryController.dispose();
    categoryFocus.dispose();
    _firstFieldFocus.dispose();
    _tabController.dispose();

    super.dispose();
  }

  Future<void> addFileForRecord() async {
    // درخواست مجوز ذخیره‌سازی
    PermissionStatus status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('برای دسترسی به فایل‌ها مجوز لازم را بدهید')),
      );
      return;
    }

    final shomareRadif = c['Shomare_Radif']?.text.trim();
    if (shomareRadif == null || shomareRadif.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('شماره ثبت مشخص نیست')));
      return;
    }

    // انتخاب چند فایل
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final lettersDir = await getLettersDirectory();
    if (!await lettersDir.exists()) {
      await lettersDir.create(recursive: true);
    }

    for (final file in result.files) {
      if (file.path == null) continue;

      final pickedFile = File(file.path!);
      final ext = path.extension(pickedFile.path);

      // پیدا کردن نام مناسب فایل
      String targetName = '$shomareRadif$ext';
      File targetFile = File(path.join(lettersDir.path, targetName));

      int index = 1;
      while (await targetFile.exists()) {
        targetName = '${shomareRadif}_$index$ext';
        targetFile = File(path.join(lettersDir.path, targetName));
        index++;
      }

      // کپی فایل
      await pickedFile.copy(targetFile.path);
    }

    // رفرش لیست فایل‌ها
    await _loadFiles();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('فایل‌ها با موفقیت اضافه شدند')));
  }

  Future<void> scanDocument() async {
    //by default way they fetch pdf for android and png for iOS
    dynamic result;
    try {
      result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ScanerPage()),
      );
    } on PlatformException {
      result = 'دریافت فایل های اسکن شده شکست خورد.';
    } catch (error) {
      result = error.toString();
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.toString())));
  }

  Widget buildGuyField() {
    return buildSimpleAutoCompleteField(
      field: 'guy',
      label: 'موضوع',
      suggestions: guySuggestions,
      onChanged: (value) {
        _debounceGuy?.cancel();
        _debounceGuy = Timer(const Duration(milliseconds: 300), () async {
          if (value.trim().isEmpty) {
            setState(() => guySuggestions.clear());
            return;
          }
          final res = await DatabaseHelper.searchDistinctField(
            'guy',
            value.trim(),
          );
          setState(() => guySuggestions = res);
        });
      },
      onSelected: (item) {
        c['guy']!.text = item;
        setState(() => guySuggestions.clear());
      },
      focusNode: focusNodes['guy']!,
      nextFocus: focusNodes['saheb_name'],
    );
  }

  Widget buildOnvanField() {
    return buildSimpleAutoCompleteField(
      field: 'onvan',
      label: 'گیرنده نامه',
      suggestions: onvanSuggestions,
      onChanged: (value) {
        _debounceOnvan?.cancel();
        _debounceOnvan = Timer(const Duration(milliseconds: 300), () async {
          if (value.trim().isEmpty) {
            setState(() => onvanSuggestions.clear());
            return;
          }
          final res = await DatabaseHelper.searchDistinctField(
            'onvan',
            value.trim(),
          );
          setState(() => onvanSuggestions = res);
        });
      },
      onSelected: (item) {
        c['onvan']!.text = item;
        setState(() => onvanSuggestions.clear());
      },
      focusNode: focusNodes['onvan']!,
      nextFocus: null, // فرض کنیم آخرین فیلد هست
    );
  }

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
        TextFormField(
          controller: c[field],
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.rtl,
          onChanged: onChanged,
          onFieldSubmitted: (_) {
            // وقتی اینتر زده شد:
            if (suggestions.isNotEmpty) {
              onSelected(suggestions[0]);
            }
            if (nextFocus != null) {
              FocusScope.of(context).requestFocus(nextFocus);
            } else {
              focusNode.unfocus();
            }
          },
        ),
        if (suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: Icon(Icons.close, size: 20, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        suggestions.clear();
                      });
                    },
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: suggestions.length,
                  itemBuilder: (_, i) {
                    final item = suggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(item, textDirection: TextDirection.rtl),
                      onTap: () {
                        onSelected(item);
                        setState(() => suggestions.clear());
                      },
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  //ویدجت دسته بندی
  Widget buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: categoryController,
          focusNode: categoryFocus,
          decoration: InputDecoration(
            labelText: "دسته‌بندی",
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            _debounceCategory?.cancel();
            _debounceCategory = Timer(
              const Duration(milliseconds: 300),
              () async {
                if (value.trim().isEmpty) {
                  setState(() => categorySuggestions.clear());
                  return;
                }

                final res = await DatabaseHelper.searchCategories(value.trim());
                setState(() => categorySuggestions = res);
              },
            );
          },
          onFieldSubmitted: (value) {
            _addCategory(value.trim());
          },
        ),

        /// 🔹 نمایش تگ‌های انتخاب شده
        if (selectedCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: selectedCategories.map((cat) {
                return Chip(
                  label: Text(cat),
                  deleteIcon: Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      selectedCategories.remove(cat);
                    });
                  },
                );
              }).toList(),
            ),
          ),

        /// 🔹 پیشنهادها
        if (categorySuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: categorySuggestions.length,
              itemBuilder: (_, i) {
                final item = categorySuggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(item, textDirection: TextDirection.rtl),
                  onTap: () {
                    _addCategory(item);
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  void _addCategory(String value) {
    if (value.isEmpty) return;

    if (!selectedCategories.contains(value)) {
      setState(() {
        selectedCategories.add(value);
      });
    }

    categoryController.clear();
    categorySuggestions.clear();
  }

  /// 🔹 فیلد مخصوص صاحب نامه با اتوکامپلیت
  Widget buildSahebNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          focusNode: _firstFieldFocus,
          controller: c['saheb_name'],
          decoration: InputDecoration(
            labelText: 'صاحب نامه',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.rtl,
          onChanged: (value) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 400), () async {
              final res = await DatabaseHelper.searchSahebName(value.trim());
              setState(() {
                sahebSuggestions = res;
              });
            });
          },
        ),

        // 🔽 لیست پیشنهادها
        if (sahebSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    icon: Icon(Icons.close, size: 20, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        sahebSuggestions.clear();
                      });
                    },
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: sahebSuggestions.length,
                  itemBuilder: (_, i) {
                    final item = sahebSuggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(item, textDirection: TextDirection.rtl),
                      onTap: () async {
                        c['saheb_name']!.text = item;

                        final last =
                            await DatabaseHelper.getLastRecordBySahebName(item);

                        if (last != null) {
                          c['sh_name_reside']!.text =
                              last['sh_name_reside']?.toString() ?? '';

                          lastRecord = last;

                          lastInfoText =
                              'آخرین نامه: ${last['date'] ?? '—'} | ${last['guy'] ?? '—'} | ${last['onvan'] ?? '—'}';
                        } else {
                          lastRecord = null;
                          lastInfoText = null;
                        }

                        setState(() {
                          sahebSuggestions.clear();
                        });
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        if (lastInfoText != null && lastRecord != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 4),
            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RecordForm(record: lastRecord),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_new, size: 14, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      lastInfoText!,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget buildTextField(String field) {
    if (field == 'saheb_name') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: buildSahebNameField(),
      );
    }

    if (field == 'guy') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: buildGuyField(),
      );
    }

    if (field == 'onvan') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: buildOnvanField(),
      );
    }

    // 🔹 فیلد تاریخ با فرمت شمسی
    if (field == 'date') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          controller: c[field],
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            JalaliDateFormatter(),
          ],
          decoration: InputDecoration(
            labelText: 'تاریخ',
            hintText: '1404/01/15',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.rtl,
          validator: (v) {
            if (v == null || v.length != 10) {
              return 'تاریخ معتبر وارد کنید';
            }
            return null;
          },
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: c[field],
        decoration: InputDecoration(
          labelText: fieldLabels[field] ?? field,
          border: OutlineInputBorder(),
        ),
        textDirection: TextDirection.rtl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.record == null ? 'ثبت نامه' : 'ویرایش نامه'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: "اطلاعات فرم"),
            Tab(text: "فایل‌ها"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // تب اول: اطلاعات فرم
          Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.all(12),
              children: [
                ...mainFields.map((field) => buildTextField(field)),

                const SizedBox(height: 10),
                buildCategoryField(),
                const SizedBox(height: 10),

                ExpansionTile(
                  title: Text('سایر اطلاعات'),
                  children: otherFields.map(buildTextField).toList(),
                ),
                Row(
                  children: [
                    if (widget.record == null)
                      Expanded(
                        child: ElevatedButton(
                          onPressed: saveAndStay,
                          child: const Text('ذخیره و جدید'),
                        ),
                      ),
                    if (widget.record == null) const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: save,
                        child: const Text('ذخیره'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // تب دوم: لیست فایل‌ها
          Column(
            children: [
              // دکمه‌ها برای افزودن فایل و اسکن فایل
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.attach_file),
                      label: const Text('افزودن فایل'),
                      onPressed: addFileForRecord,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt),
                      label: const Text('اسکن فایل'),
                      onPressed: scanDocument,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('بروزرسانی لیست'),
                      onPressed: _loadFiles,
                    ),
                  ],
                ),
              ),

              // نمایش لیست فایل‌ها
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180, // عرض هر کارت
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    // برای اینکه کارت‌ها نسبت طول به عرض مناسب داشته باشند و فضای متن هم جا شود
                    // مقدار کم‌تر مقدار کارت را بلندتر می‌کند (تماشاگر نسبت 9:16 برای تصویر داخلیش است)
                    // با مقدار ~0.55 تا 0.6 کارتی بلندتر می‌شود تا تصویر 9:16 بتواند جا بگیرد.
                    childAspectRatio: 0.55,
                  ),
                  itemCount: filesInDirectory.length,
                  itemBuilder: (context, index) {
                    final file = filesInDirectory[index];
                    final isImg = _isImage(file.path);
                    final fileName = path.basename(file.path);

                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: InkWell(
                        onTap: () => openFile(file),
                        borderRadius: BorderRadius.circular(12),
                        child: Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // ناحیه تصویر با نسبت عمودی 9:16
                              Expanded(
                                child: AspectRatio(
                                  aspectRatio: 5 / 7,
                                  child: isImg
                                      ? Image.file(
                                          file,
                                          width: double.infinity,
                                          height: double.infinity,
                                          fit:
                                              BoxFit.contain, // جلوگیری از کراپ
                                        )
                                      : Container(
                                          color: Colors.grey[200],
                                          child: const Center(
                                            child: Icon(
                                              Icons.insert_drive_file,
                                              size: 40,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              // متن زیر تصویر
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  fileName,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
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
            ],
          ),
        ],
      ),
    );
  }

  bool _isImage(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext);
  }

  Future<void> saveAndStay() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      for (var f in [...mainFields, ...otherFields]) f: c[f]!.text,
    };

    if (widget.record == null) {
      await DatabaseHelper.insert(data);
    } else {
      await DatabaseHelper.update(widget.record!['Shomare_Radif'], data);
    }

    await DatabaseHelper.saveCategoriesForRecord(
      c['Shomare_Radif']!.text,
      selectedCategories,
    );

    // 🔹 تاریخ رکورد فعلی را نگه می‌داریم
    final String lastDate = c['date']?.text ?? '';

    // پاک کردن فیلدها
    for (var controller in c.values) {
      controller.clear();
    }

    // دوباره ست کردن مقادیر پیشفرض
    _setInitialValues();
    // 🔹 برگرداندن تاریخ قبلی
    c['date']?.text = lastDate;

    // فوکوس برگردد به اولین فیلد
    Future.delayed(const Duration(milliseconds: 100), () {
      _firstFieldFocus.requestFocus();
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('اطلاعات ذخیره شد')));
  }
}
