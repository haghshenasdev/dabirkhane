import 'dart:async';
import 'dart:io';

import 'package:dabirkhane/services/csv_export_service.dart';
import 'package:dabirkhane/services/excel_export_service.dart';
import 'package:dabirkhane/ui/dialogs/backup_restore_dialog.dart';
import 'package:dabirkhane/ui/dialogs/csv_export_dialog.dart';
import 'package:dabirkhane/utils/glass_toast.dart';

import '../pages/settings_page.dart';
import '../pages/stats_page.dart';
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../db/database_helper.dart';
import 'record_form.dart';

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

  int limit = 10;
  int? _lastCursorId;

  Timer? _debounce;

  bool selectionMode = false;

  // ------------------------------------------------------------
  // انتخاب رکوردها
  //
  // دیگر بر اساس index نیست.
  // ID واقعی رکورد (Shomare_Radif) ذخیره می‌شود.
  // ------------------------------------------------------------

  Set<int> selectedRecordIds = {};

  // وقتی true باشد یعنی تمام نتایج فیلتر فعلی انتخاب شده‌اند.
  //
  // در این حالت لازم نیست همه رکوردها را از دیتابیس بخوانیم.
  bool selectAllMode = false;

  // اگر selectAllMode فعال باشد، این IDها استثنا هستند
  // یعنی کاربر این رکوردها را از انتخاب خارج کرده است.
  Set<int> _excludedSelectedIds = {};

  bool showAdvancedFilter = false;

  final TextEditingController fromDateController = TextEditingController();
  final TextEditingController toDateController = TextEditingController();
  final TextEditingController onvanController = TextEditingController();
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
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
    _searchFocusNode.dispose();
    categoryFilterController.dispose();
    commentFilterController.dispose();
    shomareBadiFilterController.dispose();

    super.dispose();
  }

  // ============================================================
  // مدیریت انتخاب
  // ============================================================

  bool _isRecordSelected(int? id) {
    if (id == null) {
      return false;
    }

    // اگر انتخاب همه فعال است:
    // همه انتخاب هستند به جز مواردی که در excluded هستند.
    if (selectAllMode) {
      return !_excludedSelectedIds.contains(id);
    }

    return selectedRecordIds.contains(id);
  }

  int get _selectedCountOnLoadedRecords {
    if (selectAllMode) {
      return records.where((record) {
        final id = _getRecordId(record);
        return id != null && !_excludedSelectedIds.contains(id);
      }).length;
    }

    return selectedRecordIds.length;
  }

  void _enterSelectionMode(int recordId) {
    setState(() {
      selectionMode = true;

      selectAllMode = false;
      _excludedSelectedIds.clear();

      selectedRecordIds.add(recordId);
    });
  }

  void _toggleRecordSelection(int recordId) {
    setState(() {
      if (selectAllMode) {
        if (_excludedSelectedIds.contains(recordId)) {
          // دوباره انتخابش کن
          _excludedSelectedIds.remove(recordId);
        } else {
          // از انتخاب همه خارجش کن
          _excludedSelectedIds.add(recordId);
        }

        return;
      }

      if (selectedRecordIds.contains(recordId)) {
        selectedRecordIds.remove(recordId);
      } else {
        selectedRecordIds.add(recordId);
      }

      if (selectedRecordIds.isEmpty) {
        selectionMode = false;
      }
    });
  }

  void _selectAllFilteredRecords() {
    setState(() {
      selectionMode = true;

      // خیلی مهم:
      // هیچ رکورد دیگری از دیتابیس خوانده نمی‌شود.
      selectAllMode = true;

      // رکوردهایی که کاربر از انتخاب همه خارج کرده بود پاک می‌شوند.
      _excludedSelectedIds.clear();

      // در حالت selectAll دیگر نیازی به نگهداری ID تک تک رکوردها نداریم.
      selectedRecordIds.clear();
    });
  }

  void _clearSelection() {
    setState(() {
      selectionMode = false;
      selectAllMode = false;

      selectedRecordIds.clear();
      _excludedSelectedIds.clear();
    });
  }

  // وقتی جستجو یا فیلتر عوض می‌شود، انتخاب قبلی را پاک می‌کنیم.
  //
  // چون انتخاب همه مربوط به «نتیجه فیلتر قبلی» بوده است.
  void _clearSelectionForFilterChange() {
    if (!selectionMode &&
        !selectAllMode &&
        selectedRecordIds.isEmpty &&
        _excludedSelectedIds.isEmpty) {
      return;
    }

    selectionMode = false;
    selectAllMode = false;
    selectedRecordIds.clear();
    _excludedSelectedIds.clear();
  }

  // ============================================================
  // Pagination
  // ============================================================

  Future<void> loadMore({bool reset = false}) async {
    if (isLoading) return;

    if (reset) {
      _lastCursorId = null;
      hasMore = true;

      // تغییر فیلتر = پایان انتخاب قبلی
      _clearSelectionForFilterChange();

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
                selectAllMode
                    ? "همه نتایج انتخاب شده"
                    : "${selectedRecordIds.length} مورد انتخاب شده",
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : const Text(
                "دبیرخانه",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,

        actions: selectionMode
            ? [
                IconButton(
                  icon: Icon(selectAllMode ? Icons.deselect : Icons.done_all),
                  tooltip: selectAllMode ? "لغو انتخاب همه" : "انتخاب همه",
                  onPressed: () {
                    if (selectAllMode) {
                      _clearSelection();
                    } else {
                      _selectAllFilteredRecords();
                    }
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
                    _unfocusSearch();

                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StatsPage()),
                    );
                  },
                ),

                IconButton(
                  tooltip: 'پشتیبان‌گیری و بازیابی',
                  icon: const Icon(Icons.backup_rounded),
                  onPressed: () async {
                    _unfocusSearch();

                    final result = await showDialog<bool>(
                      context: context,
                      builder: (_) => const BackupRestoreDialog(),
                    );

                    if (result == true && mounted) {
                      await loadMore(reset: true);
                      await _loadReminderStatus();
                    }

                    _unfocusSearch();
                  },
                ),

                IconButton(
                  tooltip: "تنظیمات",
                  icon: const Icon(Icons.settings),
                  onPressed: () async {
                    _unfocusSearch();

                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SettingsPage()),
                    );

                    _unfocusSearch();
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
                _unfocusSearch();

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

                _unfocusSearch();
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
                                focusNode: _searchFocusNode,
                                autofocus: false,

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

                                            _clearSelectionForFilterChange();

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

                                      _clearSelectionForFilterChange();

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

    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;

    final bool desktop = width > 900;

    // ارتفاع ثابت و محدود برای قسمت فیلتر
    final double filterHeight = desktop
        ? 250
        : (height * 0.38).clamp(260.0, 400.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),

      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ==========================================================
          // فقط یک Scrollable داریم
          // ==========================================================
          SizedBox(
            height: filterHeight,

            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),

              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,

              children: [
                // ======================================================
                // تاریخ‌ها
                // همیشه کنار هم
                // ======================================================
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: fromDateController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.rtl,
                        decoration: decoration(
                          "از تاریخ",
                          Icons.calendar_month,
                        ),
                      ),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: TextField(
                        controller: toDateController,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.rtl,
                        decoration: decoration("تا تاریخ", Icons.event),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ======================================================
                // گیرنده
                // ======================================================
                TextField(
                  controller: onvanController,
                  textDirection: TextDirection.rtl,
                  decoration: decoration("گیرنده نامه", Icons.person_outline),
                ),

                const SizedBox(height: 12),

                // ======================================================
                // توضیحات + شماره بعد
                // ======================================================
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: commentFilterController,
                        textDirection: TextDirection.rtl,
                        decoration: decoration("توضیحات", Icons.notes_outlined),
                      ),
                    ),

                    const SizedBox(width: 10),

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
                ),

                const SizedBox(height: 12),

                // ======================================================
                // وضعیت یادآور
                // ======================================================
                DropdownButtonFormField<int>(
                  value: reminderFilter,
                  isExpanded: true,

                  decoration: decoration(
                    "وضعیت یادآور",
                    Icons.notifications_none_rounded,
                  ),

                  items: const [
                    DropdownMenuItem(value: 0, child: Text('همه نامه‌ها')),
                    DropdownMenuItem(
                      value: 1,
                      child: Text('یادآورهای موعدرسیده'),
                    ),
                    DropdownMenuItem(
                      value: 2,
                      child: Text('دارای یادآور فعال'),
                    ),
                    DropdownMenuItem(value: 3, child: Text('یادآورهای آینده')),
                  ],

                  onChanged: (value) {
                    if (value == null) return;

                    _clearSelectionForFilterChange();

                    setState(() {
                      reminderFilter = value;
                    });

                    loadMore(reset: true);
                  },
                ),

                const SizedBox(height: 12),

                // ======================================================
                // دسته بندی
                // ======================================================
                TextField(
                  controller: categoryFilterController,
                  textDirection: TextDirection.rtl,

                  decoration: decoration("دسته بندی", Icons.category_outlined),

                  onChanged: (value) {
                    _debounceCategoryFilter?.cancel();

                    _debounceCategoryFilter = Timer(
                      const Duration(milliseconds: 300),
                      () async {
                        if (value.trim().isEmpty) {
                          if (!mounted) return;

                          setState(() {
                            categoryFilterSuggestions.clear();
                          });

                          return;
                        }

                        final result = await DatabaseHelper.searchCategories(
                          value.trim(),
                        );

                        if (!mounted) return;

                        setState(() {
                          categoryFilterSuggestions = result;
                        });
                      },
                    );
                  },

                  onSubmitted: (value) {
                    _addCategoryFilter(value.trim());
                  },
                ),

                // ======================================================
                // دسته‌بندی‌های انتخاب شده
                // ======================================================
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
                              _clearSelectionForFilterChange();

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

                // ======================================================
                // پیشنهادهای دسته‌بندی
                //
                // هیچ ScrollView داخلی نداریم.
                // ======================================================
                if (categoryFilterSuggestions.isNotEmpty)
                  Container(
                    width: double.infinity,

                    margin: const EdgeInsets.only(top: 10),

                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade300),
                    ),

                    child: Column(
                      mainAxisSize: MainAxisSize.min,

                      children: [
                        for (
                          int i = 0;
                          i < categoryFilterSuggestions.length;
                          i++
                        ) ...[
                          ListTile(
                            dense: true,

                            leading: const Icon(
                              Icons.label_outline,
                              color: Colors.blue,
                            ),

                            title: Text(
                              categoryFilterSuggestions[i],
                              textDirection: TextDirection.rtl,
                            ),

                            onTap: () {
                              _addCategoryFilter(categoryFilterSuggestions[i]);
                            },
                          ),

                          if (i < categoryFilterSuggestions.length - 1)
                            Divider(height: 1, color: Colors.grey.shade300),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ==========================================================
          // جداکننده
          // ==========================================================
          Divider(height: 1, color: Colors.grey.shade300),

          // ==========================================================
          // دکمه‌ها
          // خارج از ListView
          // ==========================================================
          Padding(
            padding: const EdgeInsets.all(12),

            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text("اعمال فیلتر"),

                    onPressed: () {
                      _clearSelectionForFilterChange();

                      _unfocusSearch();

                      loadMore(reset: true);
                    },
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.clear),
                    label: const Text("پاک کردن"),

                    onPressed: () {
                      _clearSelectionForFilterChange();

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

                      _unfocusSearch();

                      loadMore(reset: true);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRecordCard(Map<String, dynamic> r, int i) {
    final recordId = _getRecordId(r);

    final isSelected = _isRecordSelected(recordId);

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
              if (recordId == null) return;

              _toggleRecordSelection(recordId);
            } else {
              _unfocusSearch();

              final result = await Navigator.push<Map<String, dynamic>>(
                context,
                MaterialPageRoute(builder: (_) => RecordForm(record: r)),
              );

              _unfocusSearch();

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
            if (recordId == null) return;

            _enterSelectionMode(recordId);
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

  // ============================================================
  // CSV
  // ============================================================
  Future<void> exportSelectedToCsv() async {
    // ------------------------------------------------------------
    // انتخاب رکوردها
    // ------------------------------------------------------------

    List<Map<String, dynamic>> selectedRecords;

    if (selectAllMode) {
      selectedRecords = records.where((record) {
        final id = _getRecordId(record);

        if (id == null) {
          return false;
        }

        return !_excludedSelectedIds.contains(id);
      }).toList();
    } else {
      selectedRecords = records.where((record) {
        final id = _getRecordId(record);

        return id != null && selectedRecordIds.contains(id);
      }).toList();
    }

    if (selectedRecords.isEmpty) {
      return;
    }

    // ------------------------------------------------------------
    // نمایش دیالوگ انتخاب فیلد و فرمت خروجی
    // ------------------------------------------------------------

    final result = await showDialog<ExportDialogResult>(
      context: context,
      builder: (_) {
        return CsvExportDialog(
          recordCount: selectAllMode
              ? _selectedCountOnLoadedRecords
              : selectedRecords.length,
        );
      },
    );

    if (!mounted || result == null) {
      return;
    }

    final selectedFields = result.fields;
    final format = result.format;

    if (selectedFields.isEmpty) {
      return;
    }

    // ------------------------------------------------------------
    // نام فایل
    // ------------------------------------------------------------

    final now = Jalali.now();

    final formattedDate =
        '${now.year}_'
        '${now.month.toString().padLeft(2, '0')}_'
        '${now.day.toString().padLeft(2, '0')}';

    // ------------------------------------------------------------
    // ایجاد خروجی
    // ------------------------------------------------------------

    try {
      if (format == ExportFormat.csv) {
        final fileName = 'خروجی دبیرخانه-$formattedDate.csv';

        await CsvExportService.instance.export(
          records: selectedRecords,
          fields: selectedFields,
          fileName: fileName,
        );

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid
                  ? 'فایل CSV آماده و برای اشتراک‌گذاری ارسال شد.'
                  : 'فایل CSV با موفقیت ایجاد شد.',
            ),
          ),
        );
      } else if (format == ExportFormat.excel) {
        final fileName = 'خروجی دبیرخانه-$formattedDate.xlsx';

        await ExcelExportService.instance.export(
          records: selectedRecords,
          fields: selectedFields,
          fileName: fileName,
        );

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Platform.isAndroid
                  ? 'فایل Excel آماده و برای اشتراک‌گذاری ارسال شد.'
                  : 'فایل Excel با موفقیت ایجاد شد.',
            ),
          ),
        );
      }

      _clearSelection();
    } catch (e, stackTrace) {
      debugPrint('Export error: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) {
        return;
      }

      final formatName = format == ExportFormat.excel ? 'Excel' : 'CSV';

      showMessage('خطا', 'ایجاد خروجی $formatName با خطا مواجه شد.\n\n$e');
    }
  }
  // ============================================================
  // دسته بندی
  // ============================================================

  void _addCategoryFilter(String value) {
    if (value.isEmpty) return;

    _clearSelectionForFilterChange();

    if (!selectedCategoryFilters.contains(value)) {
      setState(() {
        selectedCategoryFilters.add(value);
      });

      loadMore(reset: true);
    }

    categoryFilterController.clear();
    categoryFilterSuggestions.clear();
  }

  // ============================================================
  // بررسی فیلتر
  // ============================================================

  bool _recordMatchesCurrentFilters(Map<String, dynamic> record) {
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

    final onvan = onvanController.text.trim();

    if (onvan.isNotEmpty) {
      final value = (record['onvan'] ?? '').toString();

      if (!value.contains(onvan)) {
        return false;
      }
    }

    final fromDate = fromDateController.text.trim();

    if (fromDate.isNotEmpty) {
      final date = (record['date'] ?? '').toString();

      if (date.compareTo(fromDate) < 0) {
        return false;
      }
    }

    final toDate = toDateController.text.trim();

    if (toDate.isNotEmpty) {
      final date = (record['date'] ?? '').toString();

      if (date.compareTo(toDate) > 0) {
        return false;
      }
    }

    if (selectedCategoryFilters.isNotEmpty) {
      return false;
    }

    return true;
  }

  // ============================================================
  // Refresh بعد از ذخیره رکورد
  // ============================================================

  Future<void> _refreshAfterRecordSaved() async {
    try {
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
        for (final newRecord in latestRecords) {
          final newId = _getRecordId(newRecord);

          if (newId == null) {
            continue;
          }

          final existingIndex = records.indexWhere(
            (record) => _getRecordId(record) == newId,
          );

          if (existingIndex >= 0) {
            records[existingIndex] = newRecord;
          } else {
            records.add(newRecord);
          }
        }

        records.sort((a, b) {
          final aId = _getRecordId(a) ?? 0;

          final bId = _getRecordId(b) ?? 0;

          return bId.compareTo(aId);
        });

        _rebuildFiltered();

        hasMore = true;
      });

      await _loadReminderStatus();
    } catch (e, stackTrace) {
      debugPrint('❌ _refreshAfterRecordSaved error: $e');

      debugPrintStack(stackTrace: stackTrace);
    }
  }

  // ============================================================
  // Reminder
  // ============================================================

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

            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(12),

                onTap: reminderFilterActive
                    ? null
                    : () {
                        _clearSelectionForFilterChange();

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

            if (!reminderFilterActive)
              Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 16,
                color: Colors.orange.shade800,
              ),

            if (reminderFilterActive)
              OutlinedButton.icon(
                onPressed: () {
                  _clearSelectionForFilterChange();

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

  // ============================================================
  // بستن کیبورد
  // ============================================================

  void _unfocusSearch() {
    if (!mounted) return;

    _searchFocusNode.unfocus();

    FocusScope.of(context).unfocus();
  }
}
