import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dabirkhane/utils/glass_toast.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';

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

  int reminderFilter = 0;

  Set<int> dueReminderRecordIds = {};

  int dueReminderCount = 0;

  bool isLoading = false;
  bool hasMore = true;

  int limit = 30;
  int? _lastCursorId;

  Timer? _debounce;

  bool selectionMode = false;
  Set<int> selectedIndexes = {};

  bool showAdvancedFilter = false;

  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController onvanController = TextEditingController();
  final TextEditingController _controller = TextEditingController();
  final TextEditingController commentFilterController = TextEditingController();

  final TextEditingController shomareBadiFilterController =
      TextEditingController();

  final TextEditingController categoryFilterController =
      TextEditingController();
  List<String> selectedCategoryFilters = [];
  List<String> categoryFilterSuggestions = [];
  Timer? _debounceCategoryFilter;

  @override
  void dispose() {
    _debounce?.cancel();
    _debounceCategoryFilter?.cancel();

    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    fromDateController.dispose();
    toDateController.dispose();
    onvanController.dispose();
    _controller.dispose();
    categoryFilterController.dispose();
    commentFilterController.dispose();
    shomareBadiFilterController.dispose();

    super.dispose();
  }

  Future<void> loadMore({bool reset = false}) async {
    if (isLoading) return;

    if (reset) {
      _lastCursorId = null;
      hasMore = true;

      if (mounted) {
        setState(() {
          records = [];
          filtered = [];
        });
      }
    }

    if (!hasMore) return;

    isLoading = true;

    if (mounted) {
      setState(() {});
    }

    try {
      final fromDate = fromDateController.text.trim();
      final toDate = toDateController.text.trim();
      final onvan = onvanController.text.trim();
      final comment = commentFilterController.text.trim();
      final shomareBadi = shomareBadiFilterController.text.trim();

      final selectedCategories = List<String>.from(selectedCategoryFilters);

      final data = await DatabaseHelper.getPaged(
        limit: limit,
        beforeId: _lastCursorId,
        search: query,
        fromDate: fromDate,
        toDate: toDate,
        onvan: onvan,
        comment: comment,
        shomareBadi: shomareBadi,
        categories: selectedCategories,
        reminderFilter: reminderFilter,
      );

      final mutableData = data
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (!mounted) {
        return;
      }

      if (mutableData.length < limit) {
        hasMore = false;
      }

      if (mutableData.isNotEmpty) {
        // چون مرتب‌سازی DESC است، آخرین آیتم
        // کوچک‌ترین Shomare_Radif این صفحه است.
        _lastCursorId = _getRecordId(mutableData.last);
      }

      setState(() {
        for (final item in mutableData) {
          final id = _getRecordId(item);

          if (id == null) {
            continue;
          }

          final exists = records.any((r) => _getRecordId(r) == id);

          if (!exists) {
            records.add(item);
          }
        }

        _rebuildFiltered();
        isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('loadMore error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  int? _getRecordId(Map<String, dynamic> record) {
    final value = record['Shomare_Radif'];

    if (value is int) {
      return value;
    }

    return int.tryParse(value?.toString() ?? '');
  }

  void _rebuildFiltered() {
    final q = query.trim().toLowerCase();

    filtered = records.where((r) {
      if (q.isEmpty) {
        return true;
      }

      return (r['onvan'] ?? '').toString().toLowerCase().contains(q) ||
          (r['saheb_name'] ?? '').toString().toLowerCase().contains(q) ||
          (r['Shomare_Radif'] ?? '').toString().contains(q);
    }).toList();
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
      final db = await DatabaseHelper.database;
      final File dbFile = File(db.path);

      if (!await dbFile.exists()) {
        showMessage('خطا', 'فایل دیتابیس پیدا نشد.');
        return;
      }

      // ---------------------------------------------
      // Android
      // ---------------------------------------------
      if (Platform.isAndroid) {
        final tempDir = await getTemporaryDirectory();

        final backupFile = File(
          path.join(tempDir.path, 'dabirkhane_backup.sqlite'),
        );

        // اگر فایل قبلی وجود دارد حذف شود
        if (await backupFile.exists()) {
          await backupFile.delete();
        }

        // ساخت کپی از دیتابیس
        await dbFile.copy(backupFile.path);

        // اشتراک‌گذاری
        await Share.shareXFiles(
          [XFile(backupFile.path, mimeType: 'application/x-sqlite3')],
          subject: 'پشتیبان دیتابیس دبیرخانه',
          text: 'فایل پشتیبان دیتابیس دبیرخانه',
        );

        // پاک کردن فایل موقت
        if (await backupFile.exists()) {
          await backupFile.delete();
        }

        return;
      }

      // ---------------------------------------------
      // Windows
      // ---------------------------------------------
      if (Platform.isWindows) {
        final String? dir = await FilePicker.platform.getDirectoryPath();

        if (dir == null) {
          return;
        }

        final String target = path.join(dir, 'dabirkhane.sqlite');

        final File targetFile = File(target);

        if (await targetFile.exists()) {
          await targetFile.delete();
        }

        await dbFile.copy(target);

        showMessage(
          'موفقیت',
          'پشتیبان دیتابیس با موفقیت ذخیره شد.\n\n'
              '$target',
        );

        return;
      }

      // ---------------------------------------------
      // سایر پلتفرم‌ها
      // ---------------------------------------------
      showMessage('خطا', 'پشتیبان‌گیری در این پلتفرم پشتیبانی نمی‌شود.');
    } catch (e) {
      showMessage('خطا', 'خطا در پشتیبان‌گیری دیتابیس:\n$e');
    }
  }

  Future<void> load() async {
    final data = await DatabaseHelper.getAll();

    if (!mounted) return;

    setState(() {
      records = data.map((row) => Map<String, dynamic>.from(row)).toList();

      filtered = records.where((r) {
        final q = query.toLowerCase();

        return (r['onvan'] ?? '').toString().toLowerCase().contains(q) ||
            (r['saheb_name'] ?? '').toString().toLowerCase().contains(q) ||
            r['Shomare_Radif'].toString().contains(q);
      }).toList();
    });
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
    _loadReminderStatus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    });

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      loadMore();
    }
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
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (_) => const RecordForm()),
                );

                if (result != null) {
                  final int? id = result['id'] as int?;
                  final bool scanned = result['scanned'] == true;

                  if (result['reminderChanged'] == true) {
                    await _refreshAfterRecordSaved();
                  }

                  if (id != null) {
                    await _refreshAfterRecordSaved();

                    if (!mounted) return;

                    if (scanned) {
                      GlassToast.show(
                        context,
                        'فایل اسکن شده و تغییرات نامه با موفقیت ذخیره شد.',
                      );
                    } else {
                      GlassToast.show(
                        context,
                        'تغییرات نامه با موفقیت ذخیره شد.',
                      );
                    }
                  }
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

                  const SizedBox(height: 12),

                  if (dueReminderCount > 0) _buildDueReminderBanner(),

                  const SizedBox(height: 12),

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
        // توضیحات و شماره بعد
        //-----------------------------------------
        desktop
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: commentFilterController,
                      textDirection: TextDirection.rtl,
                      decoration: decoration("توضیحات", Icons.notes_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: shomareBadiFilterController,
                      keyboardType: TextInputType.text,
                      textDirection: TextDirection.rtl,
                      decoration: decoration(
                        "شماره بعد",
                        Icons.format_list_numbered,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  TextField(
                    controller: commentFilterController,
                    textDirection: TextDirection.rtl,
                    decoration: decoration("توضیحات", Icons.notes_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: shomareBadiFilterController,
                    keyboardType: TextInputType.text,
                    textDirection: TextDirection.rtl,
                    decoration: decoration(
                      "شماره بعد",
                      Icons.format_list_numbered,
                    ),
                  ),
                ],
              ),

        const SizedBox(height: 14),

        DropdownButtonFormField<int>(
          value: reminderFilter,
          decoration: decoration(
            "وضعیت یادآور",
            Icons.notifications_none_rounded,
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('همه نامه‌ها')),
            DropdownMenuItem(value: 1, child: Text('یادآورهای موعدرسیده')),
            DropdownMenuItem(value: 2, child: Text('دارای یادآور فعال')),
            DropdownMenuItem(value: 3, child: Text('یادآورهای آینده')),
          ],
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              reminderFilter = value;
            });

            loadMore(reset: true);
          },
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
                      loadMore(reset: true);
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

                commentFilterController.clear();
                shomareBadiFilterController.clear();
                reminderFilter = 0;

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

    final recordId = _getRecordId(r);

    final hasDueReminder =
        recordId != null && dueReminderRecordIds.contains(recordId);

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
              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => RecordForm(record: r)),
              );

              if (result != null) {
                final int? id = result['id'] as int?;
                final bool scanned = result['scanned'] == true;

                if (result['reminderChanged'] == true) {
                  await _refreshAfterRecordSaved();
                }

                if (id != null) {
                  await _refreshAfterRecordSaved();

                  if (!mounted) return;

                  if (scanned) {
                    GlassToast.show(
                      context,
                      'فایل اسکن شده و تغییرات نامه با موفقیت ذخیره شد.',
                    );
                  } else {
                    GlassToast.show(
                      context,
                      'تغییرات نامه با موفقیت ذخیره شد.',
                    );
                  }
                }
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
                      crossAxisAlignment: CrossAxisAlignment.center,
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
                        if (hasDueReminder) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.orange.shade300),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              textDirection: TextDirection.rtl,
                              children: [
                                Icon(
                                  Icons.notifications_active_rounded,
                                  size: 14,
                                  color: Colors.orange.shade800,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'موعدرسیده',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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

      loadMore(reset: true);
    }

    categoryFilterController.clear();
    categoryFilterSuggestions.clear();
  }

  bool _recordMatchesCurrentFilters(Map<String, dynamic> record) {
    // ------------------------------------------------------------
    // جستجوی عمومی
    // ------------------------------------------------------------

    final q = query.trim().toLowerCase();

    if (q.isNotEmpty) {
      final matchesSearch =
          (record['guy'] ?? '').toString().toLowerCase().contains(q) ||
          (record['saheb_name'] ?? '').toString().toLowerCase().contains(q) ||
          (record['Shomare_Radif'] ?? '').toString().contains(q) ||
          (record['sh_name_reside'] ?? '').toString().toLowerCase().contains(q);

      if (!matchesSearch) {
        return false;
      }
    }

    // ------------------------------------------------------------
    // فیلتر عنوان / گیرنده
    // ------------------------------------------------------------

    final onvan = onvanController.text.trim();

    if (onvan.isNotEmpty) {
      final value = (record['onvan'] ?? '').toString();

      if (!value.contains(onvan)) {
        return false;
      }
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ شروع
    // ------------------------------------------------------------

    final fromDate = fromDateController.text.trim();

    if (fromDate.isNotEmpty) {
      final date = (record['date'] ?? '').toString();

      if (date.compareTo(fromDate) < 0) {
        return false;
      }
    }

    // ------------------------------------------------------------
    // فیلتر تاریخ پایان
    // ------------------------------------------------------------

    final toDate = toDateController.text.trim();

    if (toDate.isNotEmpty) {
      final date = (record['date'] ?? '').toString();

      if (date.compareTo(toDate) > 0) {
        return false;
      }
    }

    // ------------------------------------------------------------
    // فیلتر دسته‌بندی
    //
    // چون دسته‌بندی‌ها در جدول جدا هستند، برای رکورد جدید
    // اینجا بررسی نمی‌کنیم.
    //
    // اگر فیلتر دسته‌بندی فعال باشد، برای جلوگیری از نمایش
    // اشتباه رکورد جدید، آن را فعلاً وارد لیست نمی‌کنیم.
    // با refresh بعدی از دیتابیس وارد خواهد شد.
    // ------------------------------------------------------------

    if (selectedCategoryFilters.isNotEmpty) {
      return false;
    }

    return true;
  }

  Future<void> _refreshAfterRecordSaved() async {
    try {
      // فقط جدیدترین 30 رکورد را دوباره از دیتابیس بگیر
      final data = await DatabaseHelper.getPaged(
        limit: limit,
        beforeId: null,
        search: query,
        fromDate: fromDateController.text.trim(),
        toDate: toDateController.text.trim(),
        onvan: onvanController.text.trim(),
        comment: commentFilterController.text.trim(),
        shomareBadi: shomareBadiFilterController.text.trim(),
        categories: List<String>.from(selectedCategoryFilters),
      );

      if (!mounted) return;

      final latestRecords = data
          .map((row) => Map<String, dynamic>.from(row))
          .toList();

      if (latestRecords.isEmpty) {
        return;
      }

      setState(() {
        // رکوردهای جدید را بر اساس ID داخل لیست فعلی merge کن
        for (final newRecord in latestRecords) {
          final newId = _getRecordId(newRecord);

          if (newId == null) continue;

          final existingIndex = records.indexWhere(
            (record) => _getRecordId(record) == newId,
          );

          if (existingIndex >= 0) {
            // اگر قبلاً وجود دارد، اطلاعاتش را به‌روز کن
            records[existingIndex] = newRecord;
          } else {
            // اگر جدید است، به لیست اضافه کن
            records.add(newRecord);
          }
        }

        // مرتب‌سازی مجدد
        records.sort((a, b) {
          final aId = _getRecordId(a) ?? 0;
          final bId = _getRecordId(b) ?? 0;

          return bId.compareTo(aId);
        });

        _rebuildFiltered();

        // اگر قبلاً hasMore=false شده بود،
        // ممکن است با اضافه شدن نامه جدید دوباره رکورد دیگری
        // برای دریافت وجود داشته باشد.
        hasMore = true;
      });

      await _loadReminderStatus();
    } catch (e, stackTrace) {
      debugPrint('❌ _refreshAfterRecordSaved error: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _loadReminderStatus() async {
    try {
      final ids = await DatabaseHelper.getDueReminderRecordIds();
      final count = await DatabaseHelper.getDueRemindersCount();

      if (!mounted) return;

      setState(() {
        dueReminderRecordIds = ids;
        dueReminderCount = count;
      });
    } catch (e, stackTrace) {
      debugPrint('load reminder status error: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Widget _buildDueReminderBanner() {
    final bool reminderFilterActive = reminderFilter == 1;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            // آیکون یادآور
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                color: Colors.orange.shade800,
              ),
            ),

            const SizedBox(width: 12),

            // متن بنر
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: reminderFilterActive
                    ? null
                    : () {
                        setState(() {
                          reminderFilter = 1;
                        });

                        loadMore(reset: true);
                      },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Text(
                    '$dueReminderCount نامه دارای یادآور موعدرسیده است',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            // وقتی فیلتر فعال نیست، فلش نمایش بده
            if (!reminderFilterActive)
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Colors.orange.shade800,
              ),

            // وقتی فیلتر فعال است، دکمه برداشتن فیلتر
            if (reminderFilterActive)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    reminderFilter = 0;
                  });

                  loadMore(reset: true);
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                label: const Text('برداشتن فیلتر'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade900,
                  side: BorderSide(color: Colors.orange.shade300),
                  backgroundColor: Colors.white.withOpacity(0.65),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
