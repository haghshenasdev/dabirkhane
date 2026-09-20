import 'package:dabirkhane/model/field_definition.dart';
import 'package:dabirkhane/services/schema_service.dart';
import 'package:flutter/material.dart';

class ShareRecordResult {
  final List<FieldDefinition> fields;
  final bool includeFiles;

  const ShareRecordResult({
    required this.fields,
    required this.includeFiles,
  });
}

class ShareRecordDialog extends StatefulWidget {
  final Map<String, dynamic> record;
  final List<String> categories;

  const ShareRecordDialog({
    super.key,
    required this.record,
    required this.categories,
  });

  @override
  State<ShareRecordDialog> createState() => _ShareRecordDialogState();
}

class _ShareRecordDialogState extends State<ShareRecordDialog> {
  bool loading = true;
  bool includeFiles = true;
  List<FieldDefinition> fields = [];
  final Set<String> selected = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final schema = await SchemaService.load();
      if (!mounted) return;

      if (schema != null) {
        fields = schema.fields
            .where((f) => f.visible && !f.system)
            .toList()
          ..sort((a, b) => a.order.compareTo(b.order));

        fields.add(
          const FieldDefinition(
            key: '__category__',
            label: 'دسته‌بندی',
            type: FieldType.category,
            visible: true,
            system: true,
            deletable: false,
          ),
        );

        const defaults = {
          'Shomare_Radif',
          'date',
          'saheb_name',
          'guy',
          'onvan',
          'comment',
          '__category__',
        };

        selected.addAll(
          fields.where((f) => defaults.contains(f.key)).map((f) => f.key),
        );
      }

      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطا در خواندن ساختار فرم: $e')),
      );
    }
  }

  void _selectAll() {
    setState(() => selected.addAll(fields.map((f) => f.key)));
  }

  void _clearAll() {
    setState(selected.clear);
  }

  void _submit() {
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حداقل یک فیلد را انتخاب کنید.')),
      );
      return;
    }

    Navigator.pop(
      context,
      ShareRecordResult(
        fields: fields.where((f) => selected.contains(f.key)).toList(),
        includeFiles: includeFiles,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content: SizedBox(
            height: 90,
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      );
    }

    final width = MediaQuery.of(context).size.width;
    final dialogWidth = width > 700 ? 620.0 : width * .92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
        contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
        actionsPadding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(.10),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.share_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'اشتراک‌گذاری نامه',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'اطلاعات و فایل‌های مورد نظر را برای ارسال انتخاب کنید',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: dialogWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(Icons.select_all_rounded),
                    label: const Text('همه'),
                  ),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(Icons.deselect_rounded),
                    label: const Text('هیچ‌کدام'),
                  ),
                  const Spacer(),
                  Text('${selected.length} مورد انتخاب شده'),
                ],
              ),
              const Divider(height: 1),
              SizedBox(
                height: 340,
                child: ListView.builder(
                  itemCount: fields.length,
                  itemBuilder: (context, index) {
                    final field = fields[index];

                    return CheckboxListTile(
                      value: selected.contains(field.key),
                      dense: true,
                      title: Text(field.label),
                      subtitle: Text(field.key),
                      secondary: Icon(_iconFor(field)),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            selected.add(field.key);
                          } else {
                            selected.remove(field.key);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: includeFiles,
                title: const Text('ضمیمه کردن فایل‌های نامه'),
                subtitle: const Text(
                  'تصاویر و سایر فایل‌های ثبت‌شده همراه متن ارسال می‌شوند.',
                  textDirection: TextDirection.rtl,
                ),
                secondary: const Icon(Icons.attach_file_rounded),
                onChanged: (value) {
                  setState(() => includeFiles = value ?? false);
                },
              ),
              if (widget.categories.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'دسته‌بندی: ${widget.categories.join('، ')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.share_rounded),
            label: const Text('اشتراک‌گذاری'),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(FieldDefinition field) {
    switch (field.type) {
      case FieldType.date:
      case FieldType.datetime:
        return Icons.event_outlined;
      case FieldType.number:
        return Icons.numbers_outlined;
      case FieldType.phone:
        return Icons.phone_outlined;
      case FieldType.email:
        return Icons.email_outlined;
      case FieldType.url:
        return Icons.link_outlined;
      case FieldType.multiline:
        return Icons.notes_outlined;
      case FieldType.file:
        return Icons.attach_file_outlined;
      case FieldType.boolean:
        return Icons.toggle_on_outlined;
      case FieldType.select:
      case FieldType.multiselect:
        return Icons.list_alt_outlined;
      case FieldType.text:
      case FieldType.category:
        return Icons.text_fields_outlined;
    }
  }
}
