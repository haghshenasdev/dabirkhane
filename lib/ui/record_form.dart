import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:dabirkhane/pages/scanner_page.dart';
import 'package:dabirkhane/providers/scan_service.dart';

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
  // ----------------------------
  // Form
  // ----------------------------

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late TabController _tabController;

  // ----------------------------
  // Controllers
  // ----------------------------

  final Map<String, TextEditingController> controllers = {};

  final Map<String, FocusNode> focusNodes = {};

  final FocusNode firstFieldFocus = FocusNode();

  // ----------------------------
  // Suggestions
  // ----------------------------

  List<String> guySuggestions = [];

  List<String> onvanSuggestions = [];

  List<String> sahebSuggestions = [];

  List<String> categorySuggestions = [];

  Timer? guyTimer;

  Timer? onvanTimer;

  Timer? sahebTimer;

  Timer? categoryTimer;

  Timer? searchTimer;

  // ----------------------------
  // Last Record
  // ----------------------------

  Map<String, dynamic>? lastRecord;

  String? lastInfoText;

  // ----------------------------
  // Categories
  // ----------------------------

  final TextEditingController categoryController = TextEditingController();

  final FocusNode categoryFocus = FocusNode();

  List<String> selectedCategories = [];

  // ----------------------------
  // Files
  // ----------------------------

  List<File> filesInDirectory = [];

  // ----------------------------
  // Fields Order
  // ----------------------------

  final List<String> mainFields = [
    // این دو تا در UI کنار هم قرار می‌گیرند
    'Shomare_Radif',
    'date',

    // ترتیب بقیه بدون تغییر
    'saheb_name',
    'guy',
    'sh_name_reside',
    'onvan',
    'comment',
    'shomare_badi',
  ];

  final List<String> otherFields = [
    't_name_ersali',
    't_name_reside',
    'wordmost2',
    'from_pywa',
    'adres_name',
    'goshashte',
  ];

  // ----------------------------
  // Labels
  // ----------------------------

  final Map<String, String> fieldLabels = {
    'Shomare_Radif': 'شماره نامه',

    'date': 'تاریخ',

    'saheb_name': 'صاحب نامه',

    'guy': 'موضوع',

    'sh_name_reside': 'شماره تماس',

    'onvan': 'گیرنده نامه',

    'comment': 'توضیحات',

    'shomare_badi': 'شماره بعدی',

    't_name_ersali': 'تاریخ مکاتبه',

    't_name_reside': 'تاریخ نامه',

    'wordmost2': 'پیوست مکاتبه',

    'from_pywa': 'پیوست نامه',

    'adres_name': 'آدرس',

    'goshashte': 'شماره قبلی',
  };

  // ----------------------------
  // Colors (Glass Theme)
  // ----------------------------

  static const Color glassWhite = Color.fromRGBO(255, 255, 255, 0.18);

  static const Color glassBorder = Color.fromRGBO(255, 255, 255, 0.30);

  // ----------------------------
  // Init
  // ----------------------------

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this);

    _createControllers();

    if (widget.record == null) {
      _setInitialValues();
    } else {
      _loadFiles();

      _loadCategories();
    }
  }

  void _createControllers() {
    final fields = [...mainFields, ...otherFields];

    for (final field in fields) {
      controllers[field] = TextEditingController(
        text: widget.record?[field]?.toString() ?? '',
      );

      focusNodes[field] = FocusNode();
    }
  }
  // ----------------------------
  // Load Categories
  // ----------------------------

  Future<void> _loadCategories() async {
    if (widget.record == null) return;

    final id = widget.record!['Shomare_Radif'].toString();

    final result = await DatabaseHelper.getCategoriesForRecord(id);

    if (!mounted) return;

    setState(() {
      selectedCategories = result;
    });
  }

  // ----------------------------
  // Default Values
  // ----------------------------

  void _setInitialValues() {
    final now = Jalali.now();

    controllers['date']!.text =
        '${now.year}/'
        '${now.month.toString().padLeft(2, '0')}/'
        '${now.day.toString().padLeft(2, '0')}';

    _setDefaultShomareRadif();
  }

  Future<void> _setDefaultShomareRadif() async {
    final last = await DatabaseHelper.getLastShomareRadif();

    final next = (last ?? 0) + 1;

    if (!mounted) return;

    controllers['Shomare_Radif']!.text = next.toString();
  }

  // ----------------------------
  // Dispose
  // ----------------------------

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _tabController.dispose();

    guyTimer?.cancel();
    onvanTimer?.cancel();
    sahebTimer?.cancel();
    categoryTimer?.cancel();
    searchTimer?.cancel();

    for (final item in controllers.values) {
      item.dispose();
    }

    for (final item in focusNodes.values) {
      item.dispose();
    }

    categoryController.dispose();

    categoryFocus.dispose();

    firstFieldFocus.dispose();

    super.dispose();
  }

  // ----------------------------
  // App Lifecycle
  // ----------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.resumed) return;

    if (!ScanService.isWaitingForScan) return;

    final success = await ScanService.processReturnedScan();

    if (!mounted) return;

    if (success) {
      await _loadFiles();

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("فایل اسکن شده اضافه شد.")));
    }
  }

  // ----------------------------
  // Files
  // ----------------------------

  Future<Directory> getLettersDirectory() async {
    final dir = await AppSettings.getLettersDirectory();

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    return dir;
  }

  Future<void> _loadFiles() async {
    final number = normalizeNumbers(
      controllers['Shomare_Radif']?.text.trim() ?? '',
    );

    if (number.isEmpty) {
      if (mounted) {
        setState(() {
          filesInDirectory = [];
        });
      }

      return;
    }

    final directory = await getLettersDirectory();

    if (!await directory.exists()) {
      setState(() {
        filesInDirectory = [];
      });

      return;
    }

    final regex = RegExp('^$number((\\D+\\d+)|\\d+)?\$');

    final List<File> result = [];

    try {
      await for (final entity in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final filename = normalizeNumbers(
            path.basenameWithoutExtension(entity.path),
          );

          if (regex.hasMatch(filename)) {
            result.add(entity);
          }
        }
      }

      if (!mounted) return;

      setState(() {
        filesInDirectory = result;
      });
    } catch (e) {
      debugPrint("Load files error: $e");
    }
  }

  // ----------------------------
  // Number Normalize
  // ----------------------------

  String normalizeNumbers(String input) {
    const persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

    for (int i = 0; i < persian.length; i++) {
      input = input.replaceAll(persian[i], i.toString());
    }

    return input;
  }
  // ======================================================
  // Glass UI
  // ======================================================

  Widget glassContainer({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(12),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),

      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),

        child: Container(
          padding: padding,

          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.15),

            borderRadius: BorderRadius.circular(22),

            border: Border.all(color: Colors.white.withOpacity(.25)),
          ),

          child: child,
        ),
      ),
    );
  }

  Widget glassField({
    required String field,

    required String label,

    int minLines = 1,

    int maxLines = 1,

    TextInputType? keyboardType,

    List<TextInputFormatter>? inputFormatters,

    Widget? suffix,

    FormFieldValidator<String>? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),

      child: glassContainer(
        child: TextFormField(
          controller: controllers[field],

          focusNode: focusNodes[field],

          keyboardType: keyboardType,

          inputFormatters: inputFormatters,

          minLines: minLines,

          maxLines: maxLines,

          textDirection: TextDirection.rtl,

          validator: validator,

          decoration: InputDecoration(
            labelText: label,

            labelStyle: const TextStyle(color: Colors.white70),

            suffixIcon: suffix,

            border: InputBorder.none,

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,

              vertical: 14,
            ),
          ),

          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ======================================================
  // Date Field
  // ======================================================

  Widget buildDateField() {
    return glassField(
      field: 'date',

      label: 'تاریخ',

      keyboardType: TextInputType.number,

      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,

        JalaliDateFormatter(),
      ],

      validator: (value) {
        if (value == null || value.length != 10) {
          return 'تاریخ معتبر وارد کنید';
        }

        return null;
      },
    );
  }

  // ======================================================
  // Normal Text Field
  // ======================================================

  Widget buildNormalField(String field) {
    return glassField(
      field: field,

      label: fieldLabels[field] ?? field,

      minLines: field == 'comment' ? 2 : 1,

      maxLines: field == 'comment' ? 5 : 3,

      keyboardType: TextInputType.multiline,
    );
  }

  // ======================================================
  // Subject Auto Complete
  // ======================================================

  Widget buildGuyField() {
    return buildAutoComplete(
      field: 'guy',

      label: 'موضوع',

      suggestions: guySuggestions,

      onSearch: (value) {
        guyTimer?.cancel();

        guyTimer = Timer(const Duration(milliseconds: 300), () async {
          if (value.trim().isEmpty) {
            setState(() {
              guySuggestions = [];
            });

            return;
          }

          final result = await DatabaseHelper.searchDistinctField(
            'guy',
            value.trim(),
          );

          if (!mounted) return;

          setState(() {
            guySuggestions = result;
          });
        });
      },

      onSelect: (item) {
        controllers['guy']!.text = item;

        setState(() {
          guySuggestions = [];
        });
      },
    );
  }

  // ======================================================
  // Generic Auto Complete
  // ======================================================

  Widget buildAutoComplete({
    required String field,

    required String label,

    required List<String> suggestions,

    required Function(String) onSearch,

    required Function(String) onSelect,
  }) {
    return Column(
      children: [
        glassField(field: field, label: label),

        if (suggestions.isNotEmpty)
          glassContainer(
            child: ListView.builder(
              shrinkWrap: true,

              itemCount: suggestions.length,

              itemBuilder: (context, index) {
                final item = suggestions[index];

                return ListTile(
                  title: Text(
                    item,

                    textDirection: TextDirection.rtl,

                    style: const TextStyle(color: Colors.white),
                  ),

                  onTap: () {
                    onSelect(item);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
  // ======================================================
  // Saheb Name Auto Complete
  // ======================================================

  Widget buildSahebNameField() {
    return Column(
      children: [
        glassField(field: 'saheb_name', label: 'صاحب نامه'),

        if (sahebSuggestions.isNotEmpty)
          glassContainer(
            child: ListView.builder(
              shrinkWrap: true,

              itemCount: sahebSuggestions.length,

              itemBuilder: (context, index) {
                final item = sahebSuggestions[index];

                return ListTile(
                  title: Text(
                    item,

                    textDirection: TextDirection.rtl,

                    style: const TextStyle(color: Colors.white),
                  ),

                  onTap: () async {
                    controllers['saheb_name']!.text = item;

                    final last = await DatabaseHelper.getLastRecordBySahebName(
                      item,
                    );

                    if (last != null) {
                      lastRecord = last;

                      controllers['sh_name_reside']!.text =
                          last['sh_name_reside']?.toString() ?? '';

                      lastInfoText =
                          'آخرین نامه: '
                          '${last['date'] ?? ''} | '
                          '${last['guy'] ?? ''} | '
                          '${last['onvan'] ?? ''}';
                    } else {
                      lastRecord = null;

                      lastInfoText = null;
                    }

                    setState(() {
                      sahebSuggestions = [];
                    });
                  },
                );
              },
            ),
          ),

        if (lastInfoText != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),

            child: InkWell(
              onTap: () async {
                await Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (_) => RecordForm(record: lastRecord),
                  ),
                );
              },

              child: Text(
                lastInfoText!,

                textDirection: TextDirection.rtl,

                style: const TextStyle(
                  color: Colors.lightBlueAccent,

                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ======================================================
  // Category Field
  // ======================================================

  Widget buildCategoryField() {
    return Column(
      children: [
        glassContainer(
          child: TextField(
            controller: categoryController,

            focusNode: categoryFocus,

            textDirection: TextDirection.rtl,

            style: const TextStyle(color: Colors.white),

            decoration: const InputDecoration(
              labelText: 'دسته‌بندی',

              labelStyle: TextStyle(color: Colors.white70),

              border: InputBorder.none,
            ),

            onChanged: (value) {
              categoryTimer?.cancel();

              categoryTimer = Timer(
                const Duration(milliseconds: 300),

                () async {
                  if (value.trim().isEmpty) {
                    setState(() {
                      categorySuggestions = [];
                    });

                    return;
                  }

                  final result = await DatabaseHelper.searchCategories(
                    value.trim(),
                  );

                  setState(() {
                    categorySuggestions = result;
                  });
                },
              );
            },

            onSubmitted: (value) {
              _addCategory(value.trim());
            },
          ),
        ),

        if (selectedCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),

            child: Wrap(
              spacing: 8,

              runSpacing: 8,

              children: selectedCategories
                  .map(
                    (item) => Chip(
                      label: Text(item),

                      deleteIcon: const Icon(Icons.close),

                      onDeleted: () {
                        setState(() {
                          selectedCategories.remove(item);
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
          ),

        if (categorySuggestions.isNotEmpty)
          glassContainer(
            child: ListView.builder(
              shrinkWrap: true,

              itemCount: categorySuggestions.length,

              itemBuilder: (context, index) {
                final item = categorySuggestions[index];

                return ListTile(
                  title: Text(
                    item,

                    textDirection: TextDirection.rtl,

                    style: const TextStyle(color: Colors.white),
                  ),

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

    categorySuggestions = [];
  }

  // ======================================================
  // Field Builder
  // ======================================================

  Widget buildField(String field) {
    switch (field) {
      case 'saheb_name':
        return buildSahebNameField();

      case 'guy':
        return buildGuyField();

      case 'date':
        return buildDateField();

      default:
        return buildNormalField(field);
    }
  }

  // ======================================================
  // Main Form Layout
  // ======================================================

  Widget buildMainForm() {
    return Form(
      key: _formKey,

      child: ListView(
        padding: const EdgeInsets.all(16),

        children: [
          // شماره نامه + تاریخ کنار هم
          Row(
            children: [
              Expanded(child: buildField('Shomare_Radif')),

              const SizedBox(width: 12),

              Expanded(child: buildField('date')),
            ],
          ),

          // بقیه فیلدها بدون تغییر ترتیب
          ...mainFields
              .where((e) => e != 'Shomare_Radif' && e != 'date')
              .map(buildField),

          ExpansionTile(
            title: const Text(
              'سایر اطلاعات',
              style: TextStyle(color: Colors.white),
            ),

            children: [
              buildCategoryField(),

              const SizedBox(height: 12),

              ...otherFields.map(buildField),
            ],
          ),
        ],
      ),
    );
  }
  // ======================================================
  // Build
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,

      backgroundColor: Colors.transparent,

      appBar: AppBar(
        backgroundColor: Colors.transparent,

        elevation: 0,

        title: Text(widget.record == null ? 'ثبت نامه' : 'ویرایش نامه'),

        bottom: TabBar(
          controller: _tabController,

          tabs: [
            const Tab(text: 'اطلاعات فرم'),

            const Tab(text: 'فایل‌ها'),
          ],
        ),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,

            end: Alignment.bottomRight,

            colors: [Color(0xff0F2027), Color(0xff203A43), Color(0xff2C5364)],
          ),
        ),

        child: SafeArea(
          child: TabBarView(
            controller: _tabController,

            children: [buildMainForm(), buildFilesTab()],
          ),
        ),
      ),
    );
  }

  // ======================================================
  // Files Tab
  // ======================================================

  Widget buildFilesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),

          child: Wrap(
            spacing: 10,

            runSpacing: 10,

            alignment: WrapAlignment.center,

            children: [
              glassButton(
                icon: Icons.attach_file,

                text: 'افزودن فایل',

                onTap: addFileForRecord,
              ),

              glassButton(
                icon: Icons.share,

                text: 'اشتراک گذاری',

                onTap: shareFiles,
              ),

              glassButton(
                icon: Icons.camera_alt,

                text: 'اسکن فایل',

                onTap: scanDocument,
              ),

              glassButton(
                icon: Icons.refresh,

                text: 'بروزرسانی',

                onTap: _loadFiles,
              ),
            ],
          ),
        ),

        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),

            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,

              mainAxisSpacing: 12,

              crossAxisSpacing: 12,

              childAspectRatio: .60,
            ),

            itemCount: filesInDirectory.length,

            itemBuilder: (context, index) {
              final file = filesInDirectory[index];

              return buildFileCard(file);
            },
          ),
        ),
      ],
    );
  }

  // ======================================================
  // Glass Button
  // ======================================================

  Widget glassButton({
    required IconData icon,

    required String text,

    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),

      onTap: onTap,

      child: glassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),

        child: Row(
          mainAxisSize: MainAxisSize.min,

          children: [
            Icon(icon, color: Colors.white),

            const SizedBox(width: 8),

            Text(text, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  // ======================================================
  // File Card
  // ======================================================

  Widget buildFileCard(File file) {
    final image = _isImage(file.path);

    return InkWell(
      borderRadius: BorderRadius.circular(20),

      onTap: () {
        openFile(file);
      },

      child: glassContainer(
        child: Column(
          children: [
            Expanded(
              child: image
                  ? Image.file(file, fit: BoxFit.contain)
                  : const Icon(
                      Icons.insert_drive_file,

                      size: 50,

                      color: Colors.white70,
                    ),
            ),

            const SizedBox(height: 8),

            Text(
              path.basename(file.path),

              maxLines: 1,

              overflow: TextOverflow.ellipsis,

              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  bool _isImage(String filePath) {
    final ext = path.extension(filePath).toLowerCase();

    return ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'].contains(ext);
  }

  // ======================================================
  // Save
  // ======================================================

  Future<void> save() async {
    if (!_formKey.currentState!.validate()) return;

    final data = {
      for (final f in [...mainFields, ...otherFields]) f: controllers[f]!.text,
    };

    int id;

    if (widget.record == null) {
      id = await DatabaseHelper.insert(data);
    } else {
      id = widget.record!['Shomare_Radif'];

      await DatabaseHelper.update(id, data);
    }

    await DatabaseHelper.saveCategoriesForRecord(
      id.toString(),

      selectedCategories,
    );

    if (!mounted) return;

    Navigator.pop(context, id);
  }

  Future<void> saveAndStay() async {
    await save();
  }

  Future<void> saveAndScan() async {
    await save();

    final id = controllers['Shomare_Radif']!.text;

    await ScanService.startScan(int.parse(id));
  }

  // ======================================================
  // Open File
  // ======================================================

  Future<void> openFile(File file) async {
    final result = await OpenFile.open(file.path);

    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('خطا در باز کردن فایل')));
    }
  }

  // ======================================================
  // Share Files
  // ======================================================

  Future<void> shareFiles() async {
    if (filesInDirectory.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('فایلی وجود ندارد')));

      return;
    }

    await Share.shareXFiles(
      filesInDirectory.map((e) => XFile(e.path)).toList(),

      subject: 'نامه شماره ${controllers['Shomare_Radif']!.text}',
    );
  }

  // ======================================================
  // Add Files For Record
  // ======================================================

  Future<void> addFileForRecord() async {
    // درخواست دسترسی فایل
    final permission = await Permission.manageExternalStorage.request();

    if (!permission.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('برای دسترسی به فایل‌ها مجوز لازم است')),
      );

      return;
    }

    final shomareRadif = controllers['Shomare_Radif']?.text.trim();

    if (shomareRadif == null || shomareRadif.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('شماره نامه مشخص نیست')));

      return;
    }

    // انتخاب چند فایل

    final result = await FilePicker.platform.pickFiles(allowMultiple: true);

    if (result == null || result.files.isEmpty) {
      return;
    }

    final directory = await getLettersDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    for (final item in result.files) {
      if (item.path == null) continue;

      final sourceFile = File(item.path!);

      final extension = path.extension(sourceFile.path);

      // نام اولیه فایل

      String fileName = '$shomareRadif$extension';

      File target = File(path.join(directory.path, fileName));

      // اگر فایل همنام وجود داشت

      int counter = 1;

      while (await target.exists()) {
        fileName = '${shomareRadif}_$counter$extension';

        target = File(path.join(directory.path, fileName));

        counter++;
      }

      // کپی فایل

      await sourceFile.copy(target.path);
    }

    // تازه‌سازی لیست فایل‌ها

    await _loadFiles();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('فایل‌ها با موفقیت اضافه شدند')),
    );
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
}
