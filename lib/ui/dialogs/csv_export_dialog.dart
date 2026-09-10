import 'package:dabirkhane/services/csv_export_service.dart';
import 'package:flutter/material.dart';


class CsvExportDialog extends StatefulWidget {
  final int recordCount;

  const CsvExportDialog({
    super.key,
    required this.recordCount,
  });

  @override
  State<CsvExportDialog> createState() => _CsvExportDialogState();
}

class _CsvExportDialogState extends State<CsvExportDialog> {
  late Set<String> _selectedKeys;

  @override
  void initState() {
    super.initState();

    // انتخاب‌های پیش‌فرض
    _selectedKeys = {
      'Shomare_Radif',
      'date',
      'saheb_name',
      'guy',
      'onvan',
    };
  }

  void _selectAll() {
    setState(() {
      _selectedKeys = {
        for (final field in CsvExportService.availableFields)
          field.key,
      };
    });
  }

  void _clearAll() {
    setState(() {
      _selectedKeys.clear();
    });
  }

  void _toggle(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  void _submit() {
    if (_selectedKeys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'حداقل یک فیلد را برای خروجی انتخاب کنید.',
          ),
        ),
      );

      return;
    }

    final selectedFields = CsvExportService.availableFields
        .where(
          (field) => _selectedKeys.contains(field.key),
        )
        .toList();

    Navigator.of(context).pop(
      selectedFields,
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    final dialogWidth = width > 700
        ? 620.0
        : width * .92;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(
          24,
          22,
          24,
          10,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          18,
          8,
          18,
          8,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          18,
          8,
          18,
          16,
        ),
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
                Icons.table_chart_outlined,
                color: Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'خروجی CSV',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'فیلدهای مورد نیاز را انتخاب کنید',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.normal,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      size: 20,
                      color: Colors.blueGrey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${widget.recordCount} نامه برای خروجی انتخاب شده است',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectAll,
                    icon: const Icon(
                      Icons.done_all,
                      size: 18,
                    ),
                    label: const Text('انتخاب همه'),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _clearAll,
                    icon: const Icon(
                      Icons.remove_done,
                      size: 18,
                    ),
                    label: const Text('پاک کردن'),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedKeys.length} فیلد',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 420,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount:
                        CsvExportService.availableFields.length,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                    ),
                    itemBuilder: (_, index) {
                      final field =
                          CsvExportService.availableFields[index];

                      final selected =
                          _selectedKeys.contains(field.key);

                      return CheckboxListTile(
                        value: selected,
                        onChanged: (_) {
                          _toggle(field.key);
                        },
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        controlAffinity:
                            ListTileControlAffinity.leading,
                        title: Text(
                          field.title,
                          textDirection: TextDirection.rtl,
                        ),
                        subtitle: Text(
                          field.key,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('انصراف'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _selectedKeys.isEmpty
                ? null
                : _submit,
            icon: const Icon(
              Icons.file_download_outlined,
              size: 19,
            ),
            label: const Text('ایجاد خروجی'),
          ),
        ],
      ),
    );
  }
}