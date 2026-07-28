import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../pages/settings_page.dart';
import '../pages/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../db/database_helper.dart';
import 'record_form.dart';
import 'package:file_selector/file_selector.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> filtered = [];
  String query = '';
  final ScrollController _scrollController = ScrollController();

  bool isLoading = false;
  bool hasMore = true;

  int limit = 30;
  int offset = 0;

  Timer? _debounce;

  bool selectionMode = false;
  Set<int> selectedIndexes = {};

  bool showAdvancedFilter = false;

  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController onvanController = TextEditingController();
  final TextEditingController _controller = TextEditingController();

  final TextEditingController categoryFilterController =
      TextEditingController();
  List<String> selectedCategoryFilters = [];
  List<String> categoryFilterSuggestions = [];
  Timer? _debounceCategoryFilter;

  Future<void> loadMore({bool reset = false}) async {
    if (isLoading) return;

    if (reset) {
      offset = 0;
      hasMore = true;
      records = [];
    }

    if (!hasMore) return;

    isLoading = true;
    setState(() {});
    final fromDate = fromDateController.text.trim();
    final toDate = toDateController.text.trim();
    final onvan = onvanController.text.trim();
    final selectedCategories = selectedCategoryFilters;

    final data = await DatabaseHelper.getPaged(
      limit: limit,
      offset: offset,
      search: query,
      fromDate: fromDate,
      toDate: toDate,
      onvan: onvan,
      categories: selectedCategories,
    );

    if (data.length < limit) {
      hasMore = false;
    }

    offset += data.length;
    records.addAll(data);

    isLoading = false;
    setState(() {});
  }

  Future<bool> confirmImport() async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('هشدار'),
            content: Text(
              'با این کار دیتابیس فعلی جایگزین می‌شود.\n'
              'آیا مطمئن هستید؟',
            ),
            actions: [
              TextButton(
                child: Text('انصراف'),
                onPressed: () => Navigator.pop(context, false),
              ),
              ElevatedButton(
                child: Text('بله، ادامه بده'),
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        ) ??
        false;
  }

  void showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: Text('باشه'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> importDb() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['sqlite', 'db'],
    );

    if (result == null) return;

    // تأیید کاربر
    final ok = await confirmImport();
    if (!ok) return;

    try {
      // 1️⃣ مسیر دیتابیس را بگیر (بدون باز کردنش)
      final String targetPath = await DatabaseHelper.getDbPath();
      final File targetFile = File(targetPath);

      // 2️⃣ اگر دیتابیس باز است، ببند
      await DatabaseHelper.closeDb();

      // 3️⃣ حذف فایل قبلی
      if (await targetFile.exists()) {
        final backupPath = '$targetPath.backup';
        await targetFile.copy(backupPath);
        await targetFile.delete();
      }

      // 4️⃣ کپی دیتابیس جدید
      final File selectedFile = File(result.files.single.path!);
      await selectedFile.copy(targetPath);

      // 5️⃣ دیتابیس جدید باز شود
      await DatabaseHelper.database;

      // 6️⃣ بارگذاری مجدد دیتا
      await load();

      showMessage('موفقیت', 'دیتابیس با موفقیت جایگزین شد.');
    } catch (e) {
      showMessage(
        'خطا',
        'ویندوز اجازه جایگزینی فایل را نداد.\n'
            'لطفاً مطمئن شوید فایل دیتابیس در برنامه یا جای دیگری باز نباشد.\n\n$e',
      );
      debugPrint(e.toString());
    }
  }

  Future<void> exportDb() async {
    try {
      String? dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;

      final db = await DatabaseHelper.database;
      final File dbFile = File(db.path);

      final String target = '$dir/dabirkhane.sqlite';

      if (await File(target).exists()) {
        await File(target).delete();
      }

      await dbFile.copy(target);

      showMessage('موفقیت', 'دیتابیس با موفقیت ذخیره شد.');
    } catch (e) {
      showMessage('خطا', 'خطا در اکسپورت دیتابیس:\n$e');
    }
  }

  Future<void> load() async {
    records = await DatabaseHelper.getAll();
    applyFilter();
  }

  void applyFilter() {
    filtered = records.where((r) {
      final q = query.toLowerCase();
      return (r['onvan'] ?? '').toString().toLowerCase().contains(q) ||
          (r['saheb_name'] ?? '').toString().toLowerCase().contains(q) ||
          r['Shomare_Radif'].toString().contains(q);
    }).toList();
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    loadMore();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusScope.of(context).unfocus();
    });

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final bool desktop = width > 1100;
    final bool tablet = width > 700;

    return Scaffold(
      backgroundColor: const Color(0xffEEF3F8),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,

        title: selectionMode
            ? Text(
                "${selectedIndexes.length} مورد انتخاب شده",
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text(
                "دبیرخانه",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    selectionMode = false;
                    selectedIndexes.clear();
                  });
                },
              )
            : null,

        actions: selectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.done_all),
                  tooltip: "انتخاب همه",
                  onPressed: () {
                    setState(() {
                      selectedIndexes = Set.from(
                        List.generate(records.length, (i) => i),
                      );
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.table_chart),
                  tooltip: "CSV",
                  onPressed: exportSelectedToCsv,
                ),
              ]
            : [
                IconButton(
                  tooltip: "بروزرسانی",
                  icon: const Icon(Icons.refresh),
                  onPressed: () => loadMore(reset: true),
                ),
                IconButton(
                  tooltip: "آمار",
                  icon: const Icon(Icons.bar_chart),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatsPage()),
                    );
                  },
                ),
                IconButton(
                  tooltip: "بازیابی",
                  icon: const Icon(Icons.download),
                  onPressed: importDb,
                ),
                IconButton(
                  tooltip: "پشتیبان گیری",
                  icon: const Icon(Icons.upload),
                  onPressed: exportDb,
                ),
                IconButton(
                  tooltip: "تنظیمات",
                  icon: const Icon(Icons.settings),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsPage()),
                    );
                  },
                ),
              ],
      ),

      floatingActionButton: selectionMode
          ? null
          : FloatingActionButton.extended(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text("ثبت نامه"),
              onPressed: () async {
                final id = await Navigator.push<int>(
                  context,
                  MaterialPageRoute(builder: (_) => RecordForm()),
                );

                if (id != null) {
                  await refreshOneRecord(id);
                }
              },
            ),

      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 1450 : double.infinity,
            ),

            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: desktop ? 32 : 12,
                vertical: desktop ? 24 : 12,
              ),

              child: Column(
                children: [
                  //----------------------------------------------------
                  // Search Panel
                  //----------------------------------------------------
                  Container(
                    padding: const EdgeInsets.all(18),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(.06),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),

                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,

                                decoration: InputDecoration(
                                  hintText: "جستجوی نامه...",

                                  prefixIcon: const Icon(Icons.search),

                                  filled: true,

                                  fillColor: Colors.grey.shade100,

                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),

                                  suffixIcon: _controller.text.isEmpty
                                      ? null
                                      : IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            _controller.clear();
                                            query = "";
                                            loadMore(reset: true);
                                          },
                                        ),
                                ),

                                onChanged: (v) {
                                  _debounce?.cancel();

                                  _debounce = Timer(
                                    const Duration(milliseconds: 400),
                                    () {
                                      query = v;
                                      loadMore(reset: true);
                                    },
                                  );
                                },
                              ),
                            ),

                            const SizedBox(width: 12),

                            FilledButton.icon(
                              onPressed: () {
                                setState(() {
                                  showAdvancedFilter = !showAdvancedFilter;
                                });
                              },
                              icon: Icon(
                                showAdvancedFilter
                                    ? Icons.expand_less
                                    : Icons.filter_alt_outlined,
                              ),
                              label: const Text("فیلتر"),
                            ),
                          ],
                        ),

                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 250),

                          firstChild: const SizedBox.shrink(),

                          secondChild: Padding(
                            padding: const EdgeInsets.only(top: 18),

                            child: buildAdvancedFilter(),
                          ),

                          crossFadeState: showAdvancedFilter
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  //----------------------------------------------------
                  // List
                  //----------------------------------------------------
                  Expanded(
                    child: records.isEmpty && !isLoading
                        ? const Center(
                            child: Text(
                              "هیچ نامه‌ای ثبت نشده است",
                              style: TextStyle(fontSize: 18),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            itemCount: records.length + (hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i >= records.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }

                              return buildRecordCard(records[i], i);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildAdvancedFilter() {
    InputDecoration decoration(String label, IconData icon) {
      return InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: Colors.grey.shade100,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.blue, width: 1.4),
        ),
      );
    }

    final desktop = MediaQuery.of(context).size.width > 900;

    return Column(
      children: [
        //-----------------------------------------
        // تاریخ
        //-----------------------------------------
        desktop
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: fromDateController,
                      keyboardType: TextInputType.number,
                      decoration: decoration("از تاریخ", Icons.calendar_month),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: TextField(
                      controller: toDateController,
                      keyboardType: TextInputType.number,
                      decoration: decoration("تا تاریخ", Icons.event),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: fromDateController,
                    keyboardType: TextInputType.number,
                    decoration: decoration("از تاریخ", Icons.calendar_month),
                  ),

                  const SizedBox(height: 12),

                  TextField(
                    controller: toDateController,
                    keyboardType: TextInputType.number,
                    decoration: decoration("تا تاریخ", Icons.event),
                  ),
                ],
              ),

        const SizedBox(height: 14),

        //-----------------------------------------
        // گیرنده
        //-----------------------------------------
        TextField(
          controller: onvanController,
          decoration: decoration("گیرنده نامه", Icons.person_outline),
        ),

        const SizedBox(height: 14),

        //-----------------------------------------
        // دسته بندی
        //-----------------------------------------
        TextField(
          controller: categoryFilterController,
          decoration: decoration("دسته بندی", Icons.category_outlined),

          onChanged: (value) {
            _debounceCategoryFilter?.cancel();

            _debounceCategoryFilter = Timer(
              const Duration(milliseconds: 300),
              () async {
                if (value.trim().isEmpty) {
                  setState(() {
                    categoryFilterSuggestions.clear();
                  });

                  return;
                }

                final result = await DatabaseHelper.searchCategories(
                  value.trim(),
                );

                setState(() {
                  categoryFilterSuggestions = result;
                });
              },
            );
          },

          onSubmitted: (v) {
            _addCategoryFilter(v.trim());
          },
        ),

        //-----------------------------------------
        // چیپ ها
        //-----------------------------------------
        if (selectedCategoryFilters.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),

            child: Align(
              alignment: Alignment.centerRight,

              child: Wrap(
                spacing: 8,
                runSpacing: 8,

                children: selectedCategoryFilters.map((cat) {
                  return Chip(
                    label: Text(cat),

                    backgroundColor: Colors.blue.shade50,

                    deleteIcon: const Icon(Icons.close),

                    onDeleted: () {
                      setState(() {
                        selectedCategoryFilters.remove(cat);
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ),

        //-----------------------------------------
        // پیشنهادها
        //-----------------------------------------
        if (categoryFilterSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 10),

            decoration: BoxDecoration(
              color: Colors.white,

              borderRadius: BorderRadius.circular(14),

              border: Border.all(color: Colors.grey.shade300),
            ),

            child: ListView.separated(
              shrinkWrap: true,

              physics: const NeverScrollableScrollPhysics(),

              itemCount: categoryFilterSuggestions.length,

              separatorBuilder: (_, __) =>
                  Divider(height: 1, color: Colors.grey.shade300),

              itemBuilder: (_, i) {
                final item = categoryFilterSuggestions[i];

                return ListTile(
                  dense: true,

                  leading: const Icon(Icons.label_outline, color: Colors.blue),

                  title: Text(item, textDirection: TextDirection.rtl),

                  onTap: () {
                    _addCategoryFilter(item);
                  },
                );
              },
            ),
          ),

        const SizedBox(height: 20),

        //-----------------------------------------
        // دکمه ها
        //-----------------------------------------
        Wrap(
          spacing: 12,
          runSpacing: 12,

          alignment: WrapAlignment.end,

          children: [
            FilledButton.icon(
              icon: const Icon(Icons.search),

              label: const Text("اعمال فیلتر"),

              onPressed: () {
                loadMore(reset: true);
              },
            ),

            OutlinedButton.icon(
              icon: const Icon(Icons.clear),

              label: const Text("پاک کردن"),

              onPressed: () {
                fromDateController.clear();
                toDateController.clear();
                onvanController.clear();

                categoryFilterController.clear();

                selectedCategoryFilters.clear();

                categoryFilterSuggestions.clear();

                query = "";

                _controller.clear();

                loadMore(reset: true);
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget buildRecordCard(Map<String, dynamic> r, int i) {
    final isSelected = selectedIndexes.contains(i);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),

          onTap: () async {
            if (selectionMode) {
              setState(() {
                if (isSelected) {
                  selectedIndexes.remove(i);
                } else {
                  selectedIndexes.add(i);
                }

                if (selectedIndexes.isEmpty) {
                  selectionMode = false;
                }
              });
            } else {
              final id = await Navigator.push<int>(
                context,
                MaterialPageRoute(builder: (_) => RecordForm(record: r)),
              );

              if (id != null) {
                await refreshOneRecord(id);
              }
            }
          },

          onLongPress: () {
            setState(() {
              selectionMode = true;
              selectedIndexes.add(i);
            });
          },

          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),

            padding: const EdgeInsets.all(18),

            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),

              color: isSelected
                  ? Colors.blue.withOpacity(.10)
                  : Colors.white.withOpacity(.72),

              border: Border.all(
                color: isSelected ? Colors.blue : Colors.white,
                width: isSelected ? 2 : 1.2,
              ),

              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),

            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    //----------------------------------------------------
                    // عنوان
                    //----------------------------------------------------
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Expanded(
                          child: Text(
                            r["guy"] ?? "—",
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const SizedBox(width: 10),

                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.mail_outline,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    //----------------------------------------------------
                    // صاحب نامه
                    //----------------------------------------------------
                    Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        const Icon(
                          Icons.person_outline,
                          size: 18,
                          color: Colors.blueGrey,
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child: Text(
                            r["saheb_name"] ?? "—",
                            textAlign: TextAlign.right,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontSize: 15),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Divider(color: Colors.grey.shade300, height: 1),

                    const SizedBox(height: 14),

                    //----------------------------------------------------
                    // پایین کارت
                    //----------------------------------------------------
                    LayoutBuilder(
                      builder: (_, c) {
                        return Row(
                          textDirection: TextDirection.rtl,

                          children: [
                            _recordChip(Icons.calendar_today, r["date"] ?? "—"),

                            const Spacer(),

                            _recordChip(
                              Icons.confirmation_number_outlined,
                              "ردیف ${r["Shomare_Radif"]}",
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),

                //----------------------------------------------------
                // انتخاب
                //----------------------------------------------------
                if (selectionMode)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        isSelected
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        key: ValueKey(isSelected),
                        color: isSelected ? Colors.blue : Colors.grey,
                        size: 28,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _recordChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey),

          const SizedBox(width: 6),

          Text(
            text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> exportSelectedToCsv() async {
    if (selectedIndexes.isEmpty) return;

    final selectedRecords = selectedIndexes
        .where((i) => i >= 0 && i < records.length)
        .map((i) => records[i])
        .toList();

    if (selectedRecords.isEmpty) return;

    final headers = selectedRecords.first.keys
        .map((e) => e.toString())
        .toList();

    final StringBuffer csv = StringBuffer();
    csv.writeln(headers.join(','));

    for (final record in selectedRecords) {
      final row = headers
          .map((h) {
            final value = record[h]?.toString() ?? '';
            final escaped = value.replaceAll('"', '""');
            return '"$escaped"';
          })
          .join(',');

      csv.writeln(row);
    }

    final now = Jalali.now();
    final formattedDate =
        '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';

    final fileName = 'خروجی دبیرخانه-$formattedDate.csv';

    final path = await getSaveLocation(
      suggestedName: fileName,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );

    if (path == null) return;

    final bytes = const Utf8Encoder().convert(csv.toString());
    final bom = [0xEF, 0xBB, 0xBF];
    await File(path.path).writeAsBytes([...bom, ...bytes], flush: true);

    debugPrint('✅ CSV فارسی ذخیره شد: $path');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('✅ خروجی ذخیره شد: ${path.path}')));
  }

  void _addCategoryFilter(String value) {
    if (value.isEmpty) return;

    if (!selectedCategoryFilters.contains(value)) {
      setState(() {
        selectedCategoryFilters.add(value);
      });
    }

    categoryFilterController.clear();
    categoryFilterSuggestions.clear();
  }

  Future<void> refreshOneRecord(int id) async {
    final record = await DatabaseHelper.getById(id);

    if (record == null) return;

    final index = records.indexWhere((e) => e['Shomare_Radif'] == id);

    setState(() {
      if (index == -1) {
        records.insert(0, record);
      } else {
        load();
      }
    });
  }
}
