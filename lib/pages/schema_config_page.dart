import 'package:dabirkhane/model/field_definition.dart';
import 'package:dabirkhane/services/schema_service.dart';
import 'package:flutter/material.dart';

import '../ui/home_page.dart';

class SchemaConfigPage extends StatefulWidget {
  final bool firstRun;

  const SchemaConfigPage({super.key, this.firstRun = false});

  @override
  State<SchemaConfigPage> createState() => _SchemaConfigPageState();
}

class _SchemaConfigPageState extends State<SchemaConfigPage>
    with SingleTickerProviderStateMixin {
  RecordSchema? schema;
  bool loading = true;
  bool saving = false;

  late TabController tabs;

  CardSchema? _pendingCard;

  @override
  void initState() {
    super.initState();

    tabs = TabController(length: 5, vsync: this);

    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await SchemaService.load();

      if (!mounted) return;

      setState(() {
        schema = loaded;
        _pendingCard = loaded?.card;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _message('خطا در بارگذاری ساختار دبیرخانه: $e');
    }
  }

  Future<void> _refresh() async {
    final loaded = await SchemaService.load();

    if (!mounted || loaded == null) return;

    setState(() {
      schema = loaded;
      _pendingCard = loaded.card;
    });
  }

  Future<void> _addField() async {
    if (schema == null) return;

    final result = await showDialog<FieldDefinition>(
      context: context,
      builder: (_) => _FieldEditorDialog(existing: schema!.fields),
    );

    if (result == null) return;

    try {
      await SchemaService.addField(result);

      await _refresh();

      if (mounted) {
        _message(
          'فیلد «${result.label}» اضافه شد و ستون واقعی SQLite ایجاد شد.',
        );
      }
    } catch (e) {
      if (mounted) {
        _message('خطا در افزودن فیلد: $e');
      }
    }
  }

  Future<void> _editField(FieldDefinition field) async {
    if (schema == null) return;

    final result = await showDialog<FieldDefinition>(
      context: context,
      builder: (_) =>
          _FieldEditorDialog(initial: field, existing: schema!.fields),
    );

    if (result == null) return;

    try {
      await SchemaService.updateField(result);
      await _refresh();
    } catch (e) {
      if (mounted) {
        _message('خطا در ویرایش فیلد: $e');
      }
    }
  }

  Future<void> _disableField(FieldDefinition field) async {
    final ok =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('غیرفعال‌سازی فیلد'),
            content: Text(
              'فیلد «${field.label}» از فرم و جستجو مخفی شود؟\n\n'
              'داده‌های قبلی این فیلد در دیتابیس حذف نخواهند شد.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('انصراف'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('غیرفعال کردن'),
              ),
            ],
          ),
        ) ??
        false;

    if (!ok) return;

    try {
      await SchemaService.disableField(field.key);
      await _refresh();
    } catch (e) {
      if (mounted) {
        _message('خطا در غیرفعال‌سازی فیلد: $e');
      }
    }
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, textDirection: TextDirection.rtl)),
    );
  }

  Future<void> _finish() async {
    if (schema == null || saving) return;

    setState(() {
      saving = true;
    });

    try {
      var finalSchema = schema!;

      if (_pendingCard != null) {
        finalSchema = RecordSchema(
          schemaVersion: finalSchema.schemaVersion + 1,
          fields: finalSchema.fields,
          sections: finalSchema.sections,
          defaultSearchFields: finalSchema.defaultSearchFields,
          dateField: finalSchema.dateField,
          statsGroupFields: finalSchema.statsGroupFields,
          statsEnabled: finalSchema.statsEnabled,
          filterFields: finalSchema.filterFields,
          filterColumns: finalSchema.filterColumns,
          card: _pendingCard!,
        );
      }

      await SchemaService.save(finalSchema);

      if (!mounted) return;

      if (widget.firstRun) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomePage()),
          (route) => false,
        );
      } else {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      _message('خطا در ذخیره تنظیمات: $e');
    }
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading || schema == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.firstRun ? 'راه‌اندازی دبیرخانه' : 'ساختار دبیرخانه',
          ),
          bottom: TabBar(
            controller: tabs,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.view_list_outlined), text: 'فیلدها'),
              Tab(
                icon: Icon(Icons.dashboard_customize_outlined),
                text: 'چینش فرم',
              ),
              Tab(icon: Icon(Icons.search_outlined), text: 'جستجو'),
              Tab(icon: Icon(Icons.analytics_outlined), text: 'آمار'),
              Tab(icon: Icon(Icons.credit_card_outlined), text: 'کارت نمایش'),
            ],
          ),
        ),
        body: TabBarView(
          controller: tabs,
          children: [
            _FieldsTab(
              schema: schema!,
              onAdd: _addField,
              onEdit: _editField,
              onDisable: _disableField,
            ),
            _LayoutTab(schema: schema!, onChanged: _refresh),
            _SearchTab(schema: schema!, onChanged: _refresh),
            _StatsTab(schema: schema!, onChanged: _refresh),
            _CardTab(
              schema: schema!,
              initialCard: _pendingCard ?? schema!.card,
              onChanged: (card) {
                setState(() {
                  _pendingCard = card;
                });
              },
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: saving ? null : _finish,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                saving
                    ? 'در حال ذخیره...'
                    : widget.firstRun
                    ? 'ذخیره تنظیمات و ورود به برنامه'
                    : 'ذخیره و بازگشت',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// FIELDS TAB
// ============================================================================

class _FieldsTab extends StatelessWidget {
  final RecordSchema schema;
  final VoidCallback onAdd;
  final Future<void> Function(FieldDefinition) onEdit;
  final Future<void> Function(FieldDefinition) onDisable;

  const _FieldsTab({
    required this.schema,
    required this.onAdd,
    required this.onEdit,
    required this.onDisable,
  });

  @override
  Widget build(BuildContext context) {
    final fields = [...schema.fields]
      ..sort((a, b) => a.order.compareTo(b.order));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'فیلدهای دبیرخانه',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                const SizedBox(height: 8),
                const Text(
                  'هر فیلد جدید به صورت یک ستون واقعی در جدول '
                  'daftare_andicator ایجاد می‌شود. '
                  'غیرفعال‌سازی فیلد، داده‌های قبلی آن را حذف نمی‌کند.',
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: const Text('افزودن فیلد جدید'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...fields.map(
          (field) => Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_iconFor(field.type))),
              title: Text(field.label),
              subtitle: Text(
                '${field.key} • '
                '${_typeLabel(field.type)}'
                '${field.system ? ' • سیستمی' : ''}'
                '${field.required ? ' • الزامی' : ''}'
                '${field.searchable ? ' • جستجو' : ''}',
              ),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: 'ویرایش',
                    onPressed: () => onEdit(field),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (field.deletable && field.visible)
                    IconButton(
                      tooltip: 'غیرفعال',
                      onPressed: () => onDisable(field),
                      icon: const Icon(Icons.visibility_off_outlined),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// LAYOUT TAB
// ============================================================================

class _LayoutTab extends StatefulWidget {
  final RecordSchema schema;
  final Future<void> Function() onChanged;

  const _LayoutTab({required this.schema, required this.onChanged});

  @override
  State<_LayoutTab> createState() => _LayoutTabState();
}

class _LayoutTabState extends State<_LayoutTab> {
  late List<FormSectionDefinition> sections;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    sections = [...widget.schema.sections]
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  void didUpdateWidget(covariant _LayoutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) {
      _sync();
    }
  }

  Future<void> _save() async {
    try {
      await SchemaService.setLayout(sections);
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره چینش: $e')),
        );
      }
    }
  }

  Future<void> _addSection() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('بخش جدید'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'عنوان بخش',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('افزودن'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;

    setState(() {
      sections.add(
        FormSectionDefinition(
          id: 'section_${DateTime.now().microsecondsSinceEpoch}',
          title: title,
          order: sections.length,
          fields: const [],
        ),
      );
    });
    await _save();
  }

  Future<void> _renameSection(int index) async {
    final controller = TextEditingController(text: sections[index].title);
    final title = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('نام بخش'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'عنوان بخش',
            border: OutlineInputBorder(),
          ),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('ذخیره'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    setState(() => sections[index] = sections[index].copyWith(title: title));
    await _save();
  }

  Future<void> _deleteSection(int index) async {
    final section = sections[index];
    if (section.fields.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ابتدا فیلدهای این بخش را به بخش دیگری منتقل کنید.')),
      );
      return;
    }
    if (sections.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حداقل یک بخش باید وجود داشته باشد.')),
      );
      return;
    }
    setState(() => sections.removeAt(index));
    await _save();
  }

  void _moveFieldInside(int sectionIndex, int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex--;
    final fields = [...sections[sectionIndex].fields];
    final item = fields.removeAt(oldIndex);
    fields.insert(newIndex.clamp(0, fields.length), item);
    setState(() {
      sections[sectionIndex] = sections[sectionIndex].copyWith(fields: fields);
    });
  }

  Future<void> _moveFieldToSection(String key, int targetSectionIndex) async {
    final target = sections[targetSectionIndex];
    if (target.fields.contains(key)) return;

    setState(() {
      for (var i = 0; i < sections.length; i++) {
        sections[i] = sections[i].copyWith(
          fields: sections[i].fields.where((e) => e != key).toList(),
        );
      }
      sections[targetSectionIndex] = target.copyWith(
        fields: [...target.fields, key],
      );
    });
    await _save();
  }

  Widget _fieldTile(String key, int sectionIndex, int fieldIndex) {
    final field = widget.schema.field(key);
    return KeyedSubtree(
      key: ValueKey('field-$key'),
      child: LongPressDraggable<String>(
        data: key,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 280,
          child: Card(
            child: ListTile(
              leading: Icon(_schemaIcon(field?.icon, field?.type)),
              title: Text(field?.label ?? key),
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: .35,
        child: ListTile(
          leading: Icon(_schemaIcon(field?.icon, field?.type)),
          title: Text(field?.label ?? key),
        ),
      ),
        child: ListTile(
          leading: Icon(_schemaIcon(field?.icon, field?.type)),
          title: Text(field?.label ?? key),
          subtitle: Text(
            '${key} • عرض ${field?.gridSpan ?? 1} از ${sections[sectionIndex].columns}',
          ),
          trailing: const Icon(Icons.drag_indicator),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'بخش‌ها، ترتیب فیلدها و تعداد ستون هر بخش را تنظیم کنید. '
              'برای انتقال فیلد بین بخش‌ها، آن را نگه دارید و روی بخش مقصد رها کنید.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sections.length,
          onReorder: (oldIndex, newIndex) async {
            if (newIndex > oldIndex) newIndex--;
            final item = sections.removeAt(oldIndex);
            sections.insert(newIndex, item);
            setState(() {});
            await _save();
          },
          itemBuilder: (context, index) {
            final section = sections[index];
            return DragTarget<String>(
              key: ValueKey('section-${section.id}'),
              onWillAcceptWithDetails: (details) =>
                  !section.fields.contains(details.data),
              onAcceptWithDetails: (details) =>
                  _moveFieldToSection(details.data, index),
              builder: (context, candidate, rejected) {
                final highlighted = candidate.isNotEmpty;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: highlighted
                      ? Theme.of(context).colorScheme.primary.withOpacity(.08)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.drag_indicator_rounded),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                section.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'تغییر نام بخش',
                              onPressed: () => _renameSection(index),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            if (sections.length > 1)
                              IconButton(
                                tooltip: 'حذف بخش',
                                onPressed: () => _deleteSection(index),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            DropdownButton<int>(
                              value: section.columns,
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('۱ ستون')),
                                DropdownMenuItem(value: 2, child: Text('۲ ستون')),
                                DropdownMenuItem(value: 3, child: Text('۳ ستون')),
                              ],
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() {
                                  sections[index] = section.copyWith(columns: value);
                                });
                                await _save();
                              },
                            ),
                          ],
                        ),
                        const Divider(),
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: section.fields.length,
                          onReorder: (oldIndex, newIndex) async {
                            _moveFieldInside(index, oldIndex, newIndex);
                            await _save();
                          },
                          itemBuilder: (context, fieldIndex) => _fieldTile(
                            section.fields[fieldIndex],
                            index,
                            fieldIndex,
                          ),
                        ),
                        if (section.fields.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('این بخش خالی است؛ فیلد را اینجا رها کنید.'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addSection,
          icon: const Icon(Icons.add),
          label: const Text('افزودن بخش فرم'),
        ),
      ],
    );
  }
}

// ============================================================================
// SEARCH TAB
// ============================================================================

class _SearchTab extends StatefulWidget {
  final RecordSchema schema;
  final Future<void> Function() onChanged;

  const _SearchTab({required this.schema, required this.onChanged});

  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  late Set<String> selected;
  late List<String> filterOrder;
  late int filterColumns;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    selected = widget.schema.defaultSearchFields.toSet();
    filterOrder = [...widget.schema.filterFields];
    if (filterOrder.isEmpty) {
      filterOrder = widget.schema.fields
          .where((f) => f.visible && f.filterable && !f.system)
          .map((f) => f.key)
          .toList();
    }
    filterColumns = widget.schema.filterColumns.clamp(1, 2).toInt();
  }

  @override
  void didUpdateWidget(covariant _SearchTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) {
      _sync();
    }
  }

  Future<void> _saveSearch() async {
    try {
      await SchemaService.setSearchFields(selected.toList());
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره تنظیمات جستجو: $e')),
        );
      }
    }
  }

  Future<void> _saveFilter() async {
    try {
      await SchemaService.setFilterConfig(
        fields: filterOrder,
        columns: filterColumns,
      );
      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره چینش فیلتر: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final searchFields = widget.schema.fields
        .where((f) => f.visible && f.searchable)
        .toList();
    final filterFields = filterOrder
        .map(widget.schema.field)
        .whereType<FieldDefinition>()
        .where((f) => f.visible && f.filterable && !f.system)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'فیلدهای جستجوی عمومی و فیلترهای صفحه اصلی را جداگانه تنظیم کنید.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'جستجوی عمومی',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        const SizedBox(height: 8),
        ...searchFields.map(
          (field) => CheckboxListTile(
            value: selected.contains(field.key),
            onChanged: (value) async {
              setState(() {
                if (value == true) {
                  selected.add(field.key);
                } else {
                  selected.remove(field.key);
                }
              });
              await _saveSearch();
            },
            secondary: Icon(_schemaIcon(field.icon, field.type)),
            title: Text(field.label),
            subtitle: Text(field.key),
          ),
        ),
        const Divider(height: 32),
        Row(
          children: [
            const Expanded(
              child: Text(
                'فیلترهای صفحه اصلی',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
            DropdownButton<int>(
              value: filterColumns,
              items: const [
                DropdownMenuItem(value: 1, child: Text('۱ ستون')),
                DropdownMenuItem(value: 2, child: Text('۲ ستون')),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => filterColumns = value);
                await _saveFilter();
              },
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text('ترتیب فیلترها را با کشیدن و رها کردن تغییر دهید.'),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filterFields.length,
          onReorder: (oldIndex, newIndex) async {
            if (newIndex > oldIndex) newIndex--;
            final item = filterFields.removeAt(oldIndex);
            filterFields.insert(newIndex, item);
            filterOrder = filterFields.map((f) => f.key).toList();
            setState(() {});
            await _saveFilter();
          },
          itemBuilder: (context, index) {
            final field = filterFields[index];
            return Card(
              key: ValueKey('filter-${field.key}'),
              child: ListTile(
                leading: Icon(_schemaIcon(field.icon, field.type)),
                title: Text(field.label),
                subtitle: Text(field.key),
                trailing: const Icon(Icons.drag_indicator_rounded),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          'دسته‌بندی و وضعیت یادآور فیلترهای سیستمی هستند و مستقل از این لیست باقی می‌مانند.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

// ============================================================================
// STATS TAB
// ============================================================================

class _StatsTab extends StatefulWidget {
  final RecordSchema schema;
  final Future<void> Function() onChanged;

  const _StatsTab({required this.schema, required this.onChanged});

  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> {
  late bool enabled;
  late String? dateField;
  late Set<String> groups;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _StatsTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) {
      _sync();
    }
  }

  void _sync() {
    enabled = widget.schema.statsEnabled;
    dateField = widget.schema.dateField;
    groups = widget.schema.statsGroupFields.toSet();
  }

  Future<void> _save() async {
    try {
      await SchemaService.setStatsConfig(
        enabled: enabled,
        dateField: dateField,
        groupFields: groups.toList(),
      );

      await widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطا در ذخیره تنظیمات آمار: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.schema.fields
        .where((f) => f.visible && !f.system && f.type != FieldType.file)
        .toList();

    final dates = widget.schema.fields
        .where(
          (f) =>
              f.visible &&
              (f.type == FieldType.date || f.type == FieldType.datetime),
        )
        .toList();

    final validDateValue = dates.any((f) => f.key == dateField)
        ? dateField
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: enabled,
          onChanged: (value) async {
            setState(() {
              enabled = value;
            });

            await _save();
          },
          title: const Text('فعال بودن داشبورد آمار'),
          subtitle: const Text('نمایش آمار و نمودارهای اطلاعات دبیرخانه'),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String?>(
          value: validDateValue,
          decoration: const InputDecoration(
            labelText: 'فیلد تاریخ برای نمودار ماهانه',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('بدون نمودار زمانی'),
            ),
            ...dates.map(
              (field) => DropdownMenuItem<String?>(
                value: field.key,
                child: Text(field.label),
              ),
            ),
          ],
          onChanged: (value) async {
            setState(() {
              dateField = value;
            });

            await _save();
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'فیلدهای گروه‌بندی آماری',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'حداکثر ۶ فیلد برای گروه‌بندی آماری انتخاب کنید.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 8),
        ...fields.map(
          (field) => CheckboxListTile(
            value: groups.contains(field.key),
            onChanged: (value) async {
              if (value == true && groups.length >= 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('حداکثر ۶ فیلد آماری قابل انتخاب است.'),
                  ),
                );
                return;
              }

              setState(() {
                if (value == true) {
                  groups.add(field.key);
                } else {
                  groups.remove(field.key);
                }
              });

              await _save();
            },
            title: Text(field.label),
            subtitle: Text('تعداد رکورد بر اساس ${field.label}'),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CARD TAB
// ============================================================================

class _CardTab extends StatefulWidget {
  final RecordSchema schema;
  final CardSchema? initialCard;
  final ValueChanged<CardSchema> onChanged;

  const _CardTab({
    required this.schema,
    required this.initialCard,
    required this.onChanged,
  });

  @override
  State<_CardTab> createState() => _CardTabState();
}

class _CardTabState extends State<_CardTab> {
  String? title;

  late List<String> body;
  late List<String> footer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _CardTab oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialCard != widget.initialCard) {
      _sync();
    }
  }

  void _sync() {
    final card = widget.initialCard ?? widget.schema.card;

    title = card.titleField;

    body = [...card.bodyFields];

    footer = [...card.footerFields];
  }

  void _emit() {
    widget.onChanged(
      CardSchema(
        titleField: title,
        bodyFields: [...body],
        footerFields: [...footer],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.schema.fields
        .where((f) => f.visible && f.key != 'Shomare_Radif' && f.type != FieldType.category)
        .toList();

    final bodyFields = fields.where((f) => f.key != title);

    final footerFields = fields.where((f) => f.key != title);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'ساختار کارت نمایش نامه را شخصی‌سازی کنید. '
              'شماره ردیف و وضعیت یادآور به صورت سیستمی '
              'در کارت حفظ می‌شوند.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          value: title,
          decoration: const InputDecoration(
            labelText: 'فیلد عنوان کارت',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('بدون عنوان اختصاصی'),
            ),
            ...fields.map(
              (field) => DropdownMenuItem<String?>(
                value: field.key,
                child: Text(field.label),
              ),
            ),
          ],
          onChanged: (value) {
            setState(() {
              title = value;

              if (value != null) {
                body.remove(value);
                footer.remove(value);
              }
            });

            _emit();
          },
        ),
        const SizedBox(height: 20),
        const Text(
          'فیلدهای بدنه کارت',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...bodyFields.map(
          (field) => CheckboxListTile(
            value: body.contains(field.key),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  if (!body.contains(field.key)) {
                    body.add(field.key);
                  }
                } else {
                  body.remove(field.key);
                }
              });

              _emit();
            },
            title: Text(field.label),
            subtitle: Text(field.key),
          ),
        ),
        const Divider(height: 32),
        const Text(
          'فیلدهای پایین کارت',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        ...footerFields.map(
          (field) => CheckboxListTile(
            value: footer.contains(field.key),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  if (!footer.contains(field.key)) {
                    footer.add(field.key);
                  }
                } else {
                  footer.remove(field.key);
                }
              });

              _emit();
            },
            title: Text(field.label),
            subtitle: Text(field.key),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// FIELD EDITOR
// ============================================================================

class _FieldEditorDialog extends StatefulWidget {
  final FieldDefinition? initial;
  final List<FieldDefinition>? existing;

  const _FieldEditorDialog({this.initial, this.existing});

  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  late final TextEditingController keyController;
  late final TextEditingController labelController;
  late final TextEditingController sectionController;
  late final TextEditingController optionsController;

  late FieldType type;

  bool required = false;
  bool searchable = true;
  bool suggestions = false;
  bool visible = true;
  bool filterable = true;
  int gridSpan = 1;
  String? iconCode;

  @override
  void initState() {
    super.initState();

    final field = widget.initial;

    keyController = TextEditingController(text: field?.key ?? '');

    labelController = TextEditingController(text: field?.label ?? '');

    sectionController = TextEditingController(
      text: field?.section ?? 'اطلاعات اصلی',
    );

    optionsController = TextEditingController(
      text: field?.options.join('\n') ?? '',
    );

    type = field?.type ?? FieldType.text;

    required = field?.required ?? false;
    searchable = field?.searchable ?? true;
    suggestions = field?.suggestions ?? false;
    visible = field?.visible ?? true;
    filterable = field?.filterable ?? true;
    gridSpan = field?.gridSpan ?? 1;
    iconCode = field?.icon;
  }

  bool get editing => widget.initial != null;

  bool get systemField => widget.initial?.system == true;

  @override
  void dispose() {
    keyController.dispose();
    labelController.dispose();
    sectionController.dispose();
    optionsController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(editing ? 'ویرایش فیلد' : 'افزودن فیلد'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'نام نمایشی',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyController,
                enabled: !editing,
                decoration: const InputDecoration(
                  labelText: 'کلید فنی',
                  hintText: 'مثلاً tracking_code',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.ltr,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<FieldType>(
                value: type,
                decoration: const InputDecoration(
                  labelText: 'نوع فیلد',
                  border: OutlineInputBorder(),
                ),
                items: FieldType.values
                    .where(
                      (e) =>
                          (e != FieldType.category && e != FieldType.file) ||
                          (systemField && e == type),
                    )
                    .map(
                      (e) => DropdownMenuItem<FieldType>(
                        value: e,
                        child: Text(_typeLabel(e)),
                      ),
                    )
                    .toList(),
                onChanged: systemField
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          type = value;
                        });
                      },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: sectionController,
                decoration: const InputDecoration(
                  labelText: 'بخش فرم',
                  border: OutlineInputBorder(),
                ),
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: gridSpan,
                      decoration: const InputDecoration(
                        labelText: 'عرض فیلد در فرم',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('یک ستون')),
                        DropdownMenuItem(value: 2, child: Text('دو ستون')),
                        DropdownMenuItem(value: 3, child: Text('سه ستون')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => gridSpan = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: iconCode,
                      decoration: const InputDecoration(
                        labelText: 'آیکون فیلد',
                        border: OutlineInputBorder(),
                      ),
                      items: _iconChoices.map((item) {
                        return DropdownMenuItem<String?>(
                          value: item.code,
                          child: Row(
                            children: [
                              Icon(_schemaIcon(item.code, type)),
                              const SizedBox(width: 8),
                              Text(item.label),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => iconCode = value),
                    ),
                  ),
                ],
              ),
              if (type == FieldType.select ||
                  type == FieldType.multiselect) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: optionsController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'گزینه‌ها',
                    helperText: 'هر گزینه را در یک خط وارد کنید.',
                    border: OutlineInputBorder(),
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
              const SizedBox(height: 8),
              CheckboxListTile(
                value: required,
                onChanged: (value) {
                  setState(() {
                    required = value ?? false;
                  });
                },
                title: const Text('الزامی'),
              ),
              CheckboxListTile(
                value: visible,
                onChanged: systemField
                    ? null
                    : (value) {
                        setState(() {
                          visible = value ?? true;
                        });
                      },
                title: const Text('نمایش در فرم'),
              ),
              CheckboxListTile(
                value: searchable,
                onChanged: (value) {
                  setState(() {
                    searchable = value ?? false;
                  });
                },
                title: const Text('قابل جستجو'),
              ),
              if (!systemField)
                CheckboxListTile(
                  value: filterable,
                  onChanged: (value) {
                    setState(() {
                      filterable = value ?? false;
                    });
                  },
                  title: const Text('قابل فیلتر در صفحه اصلی'),
                ),
              CheckboxListTile(
                value: suggestions,
                onChanged: (value) {
                  setState(() {
                    suggestions = value ?? false;
                  });
                },
                title: const Text('پیشنهاد تکمیل از داده‌های قبلی'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text('انصراف'),
        ),
        FilledButton(onPressed: _submit, child: const Text('ذخیره')),
      ],
    );
  }

  void _submit() {
    final key = keyController.text.trim();
    final label = labelController.text.trim();

    if (key.isEmpty) {
      _showError('کلید فنی فیلد را وارد کنید.');
      return;
    }

    if (label.isEmpty) {
      _showError('نام نمایشی فیلد را وارد کنید.');
      return;
    }

    if (!editing) {
      final exists = (widget.existing ?? const []).any(
        (field) => field.key == key,
      );

      if (exists) {
        _showError('این کلید فنی قبلاً استفاده شده است.');
        return;
      }
    }

    final section = sectionController.text.trim().isEmpty
        ? 'اطلاعات اصلی'
        : sectionController.text.trim();

    final options = optionsController.text
        .split('\n')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();

    final old = widget.initial;

    final result = FieldDefinition(
      key: old?.key ?? key,
      label: label,
      type: systemField ? old!.type : type,
      required: required,
      visible: systemField ? true : visible,
      searchable: searchable,
      sortable: old?.sortable ?? false,
      suggestions: suggestions,
      filterable: systemField ? false : filterable,
      system: old?.system ?? false,
      deletable: old?.deletable ?? true,
      section: section,
      order: old?.order ?? (widget.existing?.length ?? 0),
      maxLines: type == FieldType.multiline ? 4 : (old?.maxLines ?? 3),
      icon: iconCode,
      options: options,
      gridSpan: gridSpan,
    );

    Navigator.pop(context, result);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textDirection: TextDirection.rtl)),
    );
  }
}

// ============================================================================
// HELPERS
// ============================================================================

class _IconChoice {
  final String code;
  final String label;
  const _IconChoice(this.code, this.label);
}

const _iconChoices = <_IconChoice>[
  _IconChoice('text', 'متن'),
  _IconChoice('subject', 'موضوع'),
  _IconChoice('person', 'شخص'),
  _IconChoice('person_outline', 'شخص (خطی)'),
  _IconChoice('numbers', 'عدد'),
  _IconChoice('event', 'تاریخ'),
  _IconChoice('event_note', 'تاریخ نامه'),
  _IconChoice('phone', 'تلفن'),
  _IconChoice('email', 'ایمیل'),
  _IconChoice('notes', 'توضیحات'),
  _IconChoice('description', 'سند'),
  _IconChoice('attach_file', 'پیوست'),
  _IconChoice('location_on', 'مکان'),
  _IconChoice('label', 'برچسب'),
  _IconChoice('history', 'تاریخچه'),
  _IconChoice('forward', 'ارجاع'),
  _IconChoice('link', 'لینک'),
  _IconChoice('check_circle', 'تأیید'),
];

IconData _schemaIcon(String? code, FieldType? type) {
  if (code != null && code.trim().isNotEmpty) {
    const map = <String, IconData>{
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
    final named = map[code];
    if (named != null) return named;
    final parsed = int.tryParse(code);
    if (parsed != null) return IconData(parsed, fontFamily: 'MaterialIcons');
  }

  switch (type) {
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



String _typeLabel(FieldType type) {
  switch (type) {
    case FieldType.text:
      return 'متن';

    case FieldType.multiline:
      return 'متن چندخطی';

    case FieldType.number:
      return 'عدد';

    case FieldType.date:
      return 'تاریخ';

    case FieldType.datetime:
      return 'تاریخ و ساعت';

    case FieldType.select:
      return 'انتخابی';

    case FieldType.multiselect:
      return 'چند انتخابی';

    case FieldType.boolean:
      return 'بله / خیر';

    case FieldType.phone:
      return 'شماره تماس';

    case FieldType.email:
      return 'ایمیل';

    case FieldType.url:
      return 'لینک';

    case FieldType.category:
      return 'دسته‌بندی';

    case FieldType.file:
      return 'فایل';
  }
}

IconData _iconFor(FieldType type) {
  switch (type) {
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
      return Icons.category_outlined;

    case FieldType.file:
      return Icons.attach_file_outlined;

    case FieldType.text:
      return Icons.text_fields_outlined;
  }
}
