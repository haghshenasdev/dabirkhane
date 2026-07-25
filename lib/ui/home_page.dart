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

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        loadMore();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: selectionMode
            ? Text('${selectedIndexes.length} مورد انتخاب شده')
            : const Text('دبیرخانه'),
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
                TextButton.icon(
                  icon: const Icon(Icons.done_all),
                  label: const Text('انتخاب همه'),
                  onPressed: () {
                    setState(() {
                      selectedIndexes = Set.from(
                        List.generate(records.length, (i) => i),
                      );
                    });
                  },
                ),

                TextButton.icon(
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('خروجی CSV'),
                  onPressed: exportSelectedToCsv,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {
                      load(); // یا load();
                    });
                  },
                  tooltip: 'تازه سازی',
                ),
                IconButton(
                  icon: const Icon(Icons.bar_chart_rounded),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatsPage()),
                    );
                  },
                  tooltip: 'آمار',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward_rounded),
                  onPressed: importDb,
                  tooltip: 'بازیابی اطلاعات',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: exportDb,
                  tooltip: 'پشتیبان گیری از اطلاعات',
                ),
                IconButton(
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
          : FloatingActionButton(
              child: const Icon(Icons.add),
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

      body: Column(
        children: [
          // 🔍 سرچ + فیلتر پیشرفته
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    // 🔎 فیلد جستجو
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          labelText: 'جستجو...',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          // وقتی متن نوشته شده دکمه پاک‌کن نمایش داده می‌شود
                          suffixIcon: _controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _controller.clear();
                                    query = '';
                                    loadMore(reset: true);
                                  },
                                )
                              : null,
                        ),
                        onChanged: (v) {
                          if (_debounce?.isActive ?? false) _debounce!.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 500),
                            () {
                              query = v;
                              loadMore(reset: true);
                            },
                          );
                        },
                      ),
                    ),

                    const SizedBox(width: 8),

                    // 🔽 دکمه باز شدن فیلتر
                    IconButton(
                      icon: Icon(
                        showAdvancedFilter
                            ? Icons.expand_less
                            : Icons.filter_alt_outlined,
                      ),
                      tooltip: 'فیلتر تاریخ',
                      onPressed: () {
                        setState(() {
                          showAdvancedFilter = !showAdvancedFilter;
                        });
                      },
                    ),
                  ],
                ),

                // 🟢 فیلتر بازشو
                AnimatedCrossFade(
                  firstChild: const SizedBox(),
                  secondChild: Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            // از تاریخ
                            Expanded(
                              child: TextField(
                                controller: fromDateController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'از تاریخ (مثال: 14040101)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),

                            // تا تاریخ
                            Expanded(
                              child: TextField(
                                controller: toDateController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'تا تاریخ (مثال: 14041229)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: onvanController,
                                decoration: const InputDecoration(
                                  labelText: 'گیرنده نامه',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        /// 🔹 فیلتر دسته‌بندی
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: categoryFilterController,
                              decoration: const InputDecoration(
                                labelText: 'دسته‌بندی',
                                border: OutlineInputBorder(),
                              ),
                              onChanged: (value) {
                                _debounceCategoryFilter?.cancel();
                                _debounceCategoryFilter = Timer(
                                  const Duration(milliseconds: 300),
                                  () async {
                                    if (value.trim().isEmpty) {
                                      setState(
                                        () => categoryFilterSuggestions.clear(),
                                      );
                                      return;
                                    }

                                    final res =
                                        await DatabaseHelper.searchCategories(
                                          value.trim(),
                                        );

                                    setState(
                                      () => categoryFilterSuggestions = res,
                                    );
                                  },
                                );
                              },
                              onSubmitted: (value) {
                                _addCategoryFilter(value.trim());
                              },
                            ),

                            /// نمایش چیپ‌ها
                            if (selectedCategoryFilters.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: selectedCategoryFilters.map((cat) {
                                    return Chip(
                                      label: Text(cat),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 18,
                                      ),
                                      onDeleted: () {
                                        setState(() {
                                          selectedCategoryFilters.remove(cat);
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ),

                            /// پیشنهادها
                            if (categoryFilterSuggestions.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  color: Colors.white,
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: categoryFilterSuggestions.length,
                                  itemBuilder: (_, i) {
                                    final item = categoryFilterSuggestions[i];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        item,
                                        textDirection: TextDirection.rtl,
                                      ),
                                      onTap: () {
                                        _addCategoryFilter(item);
                                      },
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.search),
                              label: const Text('اعمال فیلتر'),
                              onPressed: () {
                                loadMore(reset: true);
                              },
                            ),
                            const SizedBox(width: 10),
                            TextButton(
                              child: const Text('پاک کردن'),
                              onPressed: () {
                                fromDateController.clear();
                                toDateController.clear();
                                onvanController.clear();
                                selectedCategoryFilters.clear();
                                categoryFilterController.clear();
                                loadMore(reset: true);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  crossFadeState: showAdvancedFilter
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 250),
                ),
              ],
            ),
          ),

          // 📄 لیست کارت‌ها
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: records.length + (hasMore ? 1 : 0),
              itemBuilder: (_, i) {
                if (i >= records.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final r = records[i];
                final isSelected = selectedIndexes.contains(i);

                return Card(
                  color: isSelected ? Colors.blue.withOpacity(0.15) : null,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  elevation: isSelected ? 4 : 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSelected
                        ? const BorderSide(color: Colors.blue, width: 1.5)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),

                    // 👆 کلیک کوتاه
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
                          MaterialPageRoute(
                            builder: (_) => RecordForm(record: r),
                          ),
                        );

                        if (id != null) {
                          await refreshOneRecord(id);
                        }
                      }
                    },

                    // ✋ کلیک طولانی
                    onLongPress: () {
                      setState(() {
                        selectionMode = true;
                        selectedIndexes.add(i);
                      });
                    },

                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              /// سطر اول: guy و صاحب
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth > 400;
                                  if (isWide) {
                                    return Row(
                                      textDirection: TextDirection.rtl,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          r['guy'] ?? '—',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              r['saheb_name'] ?? '—',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          r['guy'] ?? '—',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.person_outline,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                r['saheb_name'] ?? '—',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),

                              const SizedBox(height: 10),

                              /// سطر دوم: تاریخ و ردیف
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isWide = constraints.maxWidth > 400;
                                  if (isWide) {
                                    return Row(
                                      textDirection: TextDirection.rtl,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(r['date'] ?? '—'),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons
                                                  .confirmation_number_outlined,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'ردیف ${r['Shomare_Radif']}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  } else {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.calendar_today,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(r['date'] ?? '—'),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons
                                                  .confirmation_number_outlined,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'ردیف ${r['Shomare_Radif']}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),

                        // ✅ آیکن انتخاب
                        if (selectionMode)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Icon(
                              isSelected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: isSelected ? Colors.blue : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
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
