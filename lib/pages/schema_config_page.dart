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
  late TabController tabs;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 5, vsync: this);
    _load();
  }

  Future<void> _load() async {
    final loaded = await SchemaService.load();
    if (!mounted) return;
    setState(() {
      schema = loaded;
      loading = false;
    });
  }

  Future<void> _refresh() async => _load();

  Future<void> _addField() async {
    final result = await showDialog<FieldDefinition>(
      context: context,
      builder: (_) => const _FieldEditorDialog(),
    );
    if (result == null) return;
    try {
      await SchemaService.addField(result);
      await _refresh();
      if (mounted) _message('فیلد اضافه شد. ستون واقعی SQLite نیز ایجاد شد.');
    } catch (e) {
      if (mounted) _message('خطا: $e');
    }
  }

  Future<void> _editField(FieldDefinition field) async {
    final result = await showDialog<FieldDefinition>(
      context: context,
      builder: (_) => _FieldEditorDialog(initial: field, existing: schema!.fields),
    );
    if (result == null) return;
    try {
      await SchemaService.updateField(result);
      await _refresh();
    } catch (e) {
      if (mounted) _message('خطا: $e');
    }
  }

  Future<void> _disableField(FieldDefinition field) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('غیرفعال‌سازی فیلد'),
            content: Text('فیلد «${field.label}» از فرم و جستجو مخفی شود؟ داده‌های قبلی آن حذف نمی‌شود.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('غیرفعال کردن')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    try {
      await SchemaService.disableField(field.key);
      await _refresh();
    } catch (e) {
      if (mounted) _message('خطا: $e');
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, textDirection: TextDirection.rtl)));
  }

  Future<void> _finish() async {
    if (_pendingCard != null && schema != null) {
      schema = RecordSchema(schemaVersion: schema!.schemaVersion + 1, fields: schema!.fields, sections: schema!.sections, defaultSearchFields: schema!.defaultSearchFields, dateField: schema!.dateField, statsGroupFields: schema!.statsGroupFields, statsEnabled: schema!.statsEnabled, card: _pendingCard!);
    }
    if (schema != null) await SchemaService.save(schema!);
    if (widget.firstRun) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomePage()),
        (route) => false,
      );
    } else {
      Navigator.pop(context, true);
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
          title: Text(widget.firstRun ? 'راه‌اندازی دبیرخانه' : 'ساختار دبیرخانه'),
          bottom: TabBar(
            controller: tabs,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.view_list_outlined), text: 'فیلدها'),
              Tab(icon: Icon(Icons.dashboard_customize_outlined), text: 'چینش فرم'),
              Tab(icon: Icon(Icons.search_outlined), text: 'جستجو'),
              Tab(icon: Icon(Icons.analytics_outlined), text: 'آمار'),
              Tab(icon: Icon(Icons.credit_card_outlined), text: 'کارت نمایش'),
            ],
          ),
        ),
        body: TabBarView(
          controller: tabs,
          children: [
            _FieldsTab(schema: schema!, onAdd: _addField, onEdit: _editField, onDisable: _disableField),
            _LayoutTab(schema: schema!, onChanged: _refresh),
            _SearchTab(schema: schema!, onChanged: _refresh),
            _StatsTab(schema: schema!, onChanged: _refresh),
            _CardTab(schema: schema!, onChanged: (card) { setState(() => _pendingCard = card); }),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _finish,
            icon: const Icon(Icons.check_rounded),
            label: Text(widget.firstRun ? 'ذخیره تنظیمات و ورود به برنامه' : 'ذخیره و بازگشت'),
          ),
        ),
      ),
    );
  }
}

class _FieldsTab extends StatelessWidget {
  final RecordSchema schema;
  final VoidCallback onAdd;
  final Future<void> Function(FieldDefinition) onEdit;
  final Future<void> Function(FieldDefinition) onDisable;

  const _FieldsTab({required this.schema, required this.onAdd, required this.onEdit, required this.onDisable});

  @override
  Widget build(BuildContext context) {
    final fields = [...schema.fields]..sort((a, b) => a.order.compareTo(b.order));
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('فیلدهای دبیرخانه', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 8),
              const Text('هر فیلد اطلاعاتی که اضافه کنید به صورت یک ستون واقعی در جدول daftare_andicator ایجاد می‌شود. غیرفعال‌سازی، داده‌های قبلی را حذف نمی‌کند.'),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('افزودن فیلد جدید')),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        ...fields.map((field) => Card(
              child: ListTile(
                leading: Icon(_iconFor(field.type)),
                title: Text(field.label),
                subtitle: Text('${field.key} • ${_typeLabel(field.type)}${field.required ? ' • الزامی' : ''}${field.searchable ? ' • جستجو' : ''}'),
                trailing: Wrap(spacing: 2, children: [
                  IconButton(tooltip: 'ویرایش', onPressed: () => onEdit(field), icon: const Icon(Icons.edit_outlined)),
                  if (field.deletable && field.visible)
                    IconButton(tooltip: 'غیرفعال', onPressed: () => onDisable(field), icon: const Icon(Icons.visibility_off_outlined)),
                ]),
              ),
            )),
      ],
    );
  }
}

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
    sections = [...widget.schema.sections]..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  void didUpdateWidget(covariant _LayoutTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) {
      sections = [...widget.schema.sections]..sort((a, b) => a.order.compareTo(b.order));
    }
  }

  Future<void> _save() async {
    await SchemaService.setLayout(sections);
    await widget.onChanged();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('چینش ذخیره شد')));
  }

  Future<void> _addSection() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      title: const Text('بخش جدید'),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'عنوان بخش'), textDirection: TextDirection.rtl),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('افزودن'))],
    ));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    setState(() => sections.add(FormSectionDefinition(id: 'section_${DateTime.now().microsecondsSinceEpoch}', title: title, order: sections.length, fields: const [])));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('فیلدها را با کشیدن جابه‌جا کنید. برای انتقال فیلد به بخش دیگر، فیلد را ویرایش کنید.', style: TextStyle(fontSize: 13)),
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
          return Card(
            key: ValueKey('section-${section.id}'),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.drag_indicator_rounded),
                  const SizedBox(width: 4),
                  Expanded(child: Text(section.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(
                    tooltip: 'تغییر نام بخش',
                    onPressed: () async {
                      final controller = TextEditingController(text: section.title);
                      final title = await showDialog<String>(context: context, builder: (_) => AlertDialog(
                        title: const Text('نام بخش'),
                        content: TextField(controller: controller, autofocus: true, textDirection: TextDirection.rtl),
                        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('ذخیره'))],
                      ));
                      controller.dispose();
                      if (title != null && title.isNotEmpty) {
                        setState(() => sections[index] = section.copyWith(title: title));
                        await _save();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  if (sections.length > 1)
                    IconButton(
                      tooltip: 'حذف بخش',
                      onPressed: () async {
                        if (section.fields.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ابتدا فیلدهای این بخش را به بخش دیگری منتقل کنید.')));
                          return;
                        }
                        setState(() => sections.removeAt(index));
                        await _save();
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  DropdownButton<int>(value: section.columns, items: const [1,2,3].map((e) => DropdownMenuItem(value: e, child: Text('$e ستون'))).toList(), onChanged: (v) { if (v != null) setState(() => sections[index] = section.copyWith(columns: v)); }),
                ]),
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: section.fields.length,
                  onReorder: (oldIndex, newIndex) {
                    if (newIndex > oldIndex) newIndex--;
                    final list = [...section.fields];
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    setState(() => sections[index] = section.copyWith(fields: list));
                  },
                  itemBuilder: (context, i) {
                    final key = section.fields[i];
                    final f = widget.schema.field(key);
                    return ListTile(key: ValueKey('$key-$index'), leading: const Icon(Icons.drag_indicator), title: Text(f?.label ?? key), subtitle: Text(key));
                  },
                ),
              ]),
            ),
          );
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: _addSection, icon: const Icon(Icons.add), label: const Text('افزودن بخش فرم')),
        const SizedBox(height: 8),
        
      ],
    );
  }
}

class _SearchTab extends StatefulWidget {
  final RecordSchema schema;
  final Future<void> Function() onChanged;
  const _SearchTab({required this.schema, required this.onChanged});
  @override
  State<_SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<_SearchTab> {
  late Set<String> selected;

  @override
  void initState() { super.initState(); selected = widget.schema.defaultSearchFields.toSet(); }
  @override
  void didUpdateWidget(covariant _SearchTab oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) selected = widget.schema.defaultSearchFields.toSet(); }

  Future<void> _save() async {
    await SchemaService.setSearchFields(selected.toList());
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.schema.fields.where((f) => f.visible && f.searchable).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('جستجوی عمومی برنامه فقط روی فیلدهایی انجام می‌شود که اینجا انتخاب می‌کنید. جستجو نسبت به نیم‌فاصله نیز مقاوم شده است.'),
      const SizedBox(height: 12),
      ...fields.map((f) => CheckboxListTile(value: selected.contains(f.key), onChanged: (v) => setState(() => v == true ? selected.add(f.key) : selected.remove(f.key)), title: Text(f.label), subtitle: Text(f.key))),
      const SizedBox(height: 8),
      
    ]);
  }
}

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
  void initState() { super.initState(); _sync(); }
  @override
  void didUpdateWidget(covariant _StatsTab oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) _sync(); }
  void _sync() { enabled = widget.schema.statsEnabled; dateField = widget.schema.dateField; groups = widget.schema.statsGroupFields.toSet(); }

  Future<void> _save() async {
    await SchemaService.setStatsConfig(enabled: enabled, dateField: dateField, groupFields: groups.toList());
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.schema.fields.where((f) => f.visible && !f.system && f.type != FieldType.file).toList();
    final dates = widget.schema.fields.where((f) => f.visible && f.type == FieldType.date).toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      SwitchListTile(value: enabled, onChanged: (v) => setState(() => enabled = v), title: const Text('فعال بودن داشبورد آمار')),
      const SizedBox(height: 8),
      DropdownButtonFormField<String?>(value: dateField, decoration: const InputDecoration(labelText: 'فیلد تاریخ برای نمودار ماهانه'), items: [const DropdownMenuItem<String?>(value: null, child: Text('بدون نمودار زمانی')), ...dates.map((f) => DropdownMenuItem<String?>(value: f.key, child: Text(f.label)))], onChanged: (v) => setState(() => dateField = v)),
      const SizedBox(height: 16),
      const Text('فیلدهای گروه‌بندی آماری', style: TextStyle(fontWeight: FontWeight.bold)),
      ...fields.map((f) => CheckboxListTile(value: groups.contains(f.key), onChanged: (v) => setState(() => v == true ? groups.add(f.key) : groups.remove(f.key)), title: Text(f.label), subtitle: Text('تعداد رکورد بر اساس این فیلد'))),
      
    ]);
  }
}

class _CardTab extends StatefulWidget {
  final RecordSchema schema;
  final ValueChanged<CardSchema> onChanged;
  const _CardTab({required this.schema, required this.onChanged});
  @override State<_CardTab> createState() => _CardTabState();
}

class _CardTabState extends State<_CardTab> {
  String? title;
  late List<String> body;
  late List<String> footer;

  @override void initState() { super.initState(); _sync(); }
  @override void didUpdateWidget(covariant _CardTab oldWidget) { super.didUpdateWidget(oldWidget); if (oldWidget.schema.schemaVersion != widget.schema.schemaVersion) _sync(); }
  void _sync() { title = widget.schema.card.titleField; body = [...widget.schema.card.bodyFields]; footer = [...widget.schema.card.footerFields]; }
  void _emit() => widget.onChanged(CardSchema(titleField: title, bodyFields: body, footerFields: footer));

  @override Widget build(BuildContext context) {
    final fields = widget.schema.fields.where((f) => f.visible && f.key != 'Shomare_Radif').toList();
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('کارت نمایش نامه را شخصی‌سازی کنید. شماره ردیف و نشان وضعیت یادآور به‌صورت سیستمی در کارت حفظ می‌شوند.'),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        value: title,
        decoration: const InputDecoration(labelText: 'فیلد عنوان کارت'),
        items: fields.map((f) => DropdownMenuItem(value: f.key, child: Text(f.label))).toList(),
        onChanged: (v) { setState(() => title = v); _emit(); },
      ),
      const SizedBox(height: 16),
      const Text('فیلدهای بدنه کارت', style: TextStyle(fontWeight: FontWeight.bold)),
      ...fields.where((f) => f.key != title).map((f) => CheckboxListTile(value: body.contains(f.key), onChanged: (v) { setState(() => v == true ? body.add(f.key) : body.remove(f.key)); _emit(); }, title: Text(f.label))),
      const Divider(),
      const Text('فیلدهای پایین کارت', style: TextStyle(fontWeight: FontWeight.bold)),
      ...fields.where((f) => f.key != title).map((f) => CheckboxListTile(value: footer.contains(f.key), onChanged: (v) { setState(() => v == true ? footer.add(f.key) : footer.remove(f.key)); _emit(); }, title: Text(f.label))),
    ]);
  }
}

class _FieldEditorDialog extends StatefulWidget {
  final FieldDefinition? initial;
  final List<FieldDefinition>? existing;
  const _FieldEditorDialog({this.initial, this.existing});
  @override
  State<_FieldEditorDialog> createState() => _FieldEditorDialogState();
}

class _FieldEditorDialogState extends State<_FieldEditorDialog> {
  final keyController = TextEditingController();
  final labelController = TextEditingController();
  final sectionController = TextEditingController(text: 'اطلاعات اصلی');
  final optionsController = TextEditingController();
  late FieldType type;
  bool required = false, searchable = true, suggestions = false, visible = true, filterable = true;

  @override
  void initState() {
    super.initState();
    final f = widget.initial;
    if (f != null) {
      keyController.text = f.key;
      labelController.text = f.label;
      sectionController.text = f.section;
      optionsController.text = f.options.join('
');
      type = f.type;
      required = f.required;
      searchable = f.searchable;
      suggestions = f.suggestions;
      visible = f.visible;
      filterable = f.filterable;
      filterable = f.filterable;
    } else {
      type = FieldType.text;
    }
  }

  @override
  void dispose() { keyController.dispose(); labelController.dispose(); sectionController.dispose(); optionsController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final editing = widget.initial != null;
    return AlertDialog(
      title: Text(editing ? 'ویرایش فیلد' : 'افزودن فیلد'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(children: [
            TextField(controller: labelController, decoration: const InputDecoration(labelText: 'نام نمایشی'), textDirection: TextDirection.rtl),
            const SizedBox(height: 8),
            TextField(controller: keyController, enabled: !editing, decoration: const InputDecoration(labelText: 'کلید فنی', hintText: 'مثلاً tracking_code'), textDirection: TextDirection.ltr),
            const SizedBox(height: 8),
            DropdownButtonFormField<FieldType>(value: type, decoration: const InputDecoration(labelText: 'نوع فیلد'), items: FieldType.values.where((e) => e != FieldType.category && e != FieldType.file).map((e) => DropdownMenuItem(value: e, child: Text(_typeLabel(e)))).toList(), onChanged: (v) => setState(() => type = v ?? FieldType.text)),
            const SizedBox(height: 8),
            TextField(controller: sectionController, decoration: const InputDecoration(labelText: 'بخش فرم'), textDirection: TextDirection.rtl),
            if (type == FieldType.select || type == FieldType.multiselect) ...[
              const SizedBox(height: 8),
              TextField(controller: optionsController, maxLines: 4, decoration: const InputDecoration(labelText: 'گزینه‌ها (هر گزینه در یک خط)'), textDirection: TextDirection.rtl),
            ],
            CheckboxListTile(value: required, onChanged: (v) => setState(() => required = v ?? false), title: const Text('الزامی')),
            CheckboxListTile(value: visible, onChanged: (v) => setState(() => visible = v ?? true), title: const Text('نمایش در فرم')),
            CheckboxListTile(value: searchable, onChanged: (v) => setState(() => searchable = v ?? false), title: const Text('قابل جستجو')),
            if (widget.initial?.system != true) CheckboxListTile(value: filterable, onChanged: (v) => setState(() => filterable = v ?? false), title: const Text('قابل فیلتر در صفحه اصلی')),
            if (widget.initial?.system != true) CheckboxListTile(value: filterable, onChanged: (v) => setState(() => filterable = v ?? false), title: const Text('قابل فیلتر در صفحه اصلی')),
            CheckboxListTile(value: suggestions, onChanged: (v) => setState(() => suggestions = v ?? false), title: const Text('پیشنهاد تکمیل از داده‌های قبلی')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
        FilledButton(onPressed: _submit, child: const Text('ذخیره')),
      ],
    );
  }

  void _submit() {
    final key = keyController.text.trim();
    final label = labelController.text.trim();
    final section = sectionController.text.trim().isEmpty ? 'اطلاعات اصلی' : sectionController.text.trim();
    if (key.isEmpty || label.isEmpty) return;
    if (widget.initial == null && (widget.existing ?? const []).any((f) => f.key == key)) return;
    final options = optionsController.text.split('
').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    Navigator.pop(context, FieldDefinition(
      key: key,
      label: label,
      type: type,
      required: required,
      visible: widget.initial?.system == true ? true : visible,
      searchable: searchable,
      filterable: widget.initial?.system == true ? false : filterable,
      suggestions: suggestions,
      section: section,
      order: widget.initial?.order ?? (widget.existing?.length ?? 0),
      options: options,
      maxLines: type == FieldType.multiline ? 4 : 3,
      system: widget.initial?.system ?? false,
      deletable: widget.initial?.deletable ?? true,
    ));
  }
}

String _typeLabel(FieldType type) {
  switch (type) {
    case FieldType.text: return 'متن';
    case FieldType.multiline: return 'متن چندخطی';
    case FieldType.number: return 'عدد';
    case FieldType.date: return 'تاریخ';
    case FieldType.datetime: return 'تاریخ و ساعت';
    case FieldType.select: return 'انتخابی';
    case FieldType.multiselect: return 'چند انتخابی';
    case FieldType.boolean: return 'بله / خیر';
    case FieldType.phone: return 'شماره تماس';
    case FieldType.email: return 'ایمیل';
    case FieldType.url: return 'لینک';
    case FieldType.category: return 'دسته‌بندی';
    case FieldType.file: return 'فایل';
  }
}

IconData _iconFor(FieldType type) {
  switch (type) {
    case FieldType.date: return Icons.calendar_today_outlined;
    case FieldType.number: return Icons.numbers_outlined;
    case FieldType.boolean: return Icons.toggle_on_outlined;
    case FieldType.select:
    case FieldType.multiselect: return Icons.list_alt_outlined;
    case FieldType.phone: return Icons.phone_outlined;
    case FieldType.email: return Icons.email_outlined;
    case FieldType.url: return Icons.link_outlined;
    case FieldType.multiline: return Icons.notes_outlined;
    default: return Icons.text_fields_outlined;
  }
}
