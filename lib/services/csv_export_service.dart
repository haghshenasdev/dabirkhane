import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class CsvExportField {
  final String key;
  final String title;

  const CsvExportField({required this.key, required this.title});
}

class CsvExportService {
  CsvExportService._();

  static final CsvExportService instance = CsvExportService._();

  /// فیلدهای قابل انتخاب برای خروجی CSV
  static const List<CsvExportField> availableFields = [
    CsvExportField(key: 'Shomare_Radif', title: 'شماره ردیف'),
    CsvExportField(key: 'date', title: 'تاریخ'),
    CsvExportField(key: 'saheb_name', title: 'صاحب نامه'),
    CsvExportField(key: 'guy', title: 'گیرنده'),
    CsvExportField(key: 'onvan', title: 'عنوان نامه'),
    CsvExportField(key: 'comment', title: 'توضیحات'),
    CsvExportField(key: 'shomare_badi', title: 'شماره بعد'),
    CsvExportField(key: 'from_pywa', title: 'فرستنده'),
    CsvExportField(key: 'sh_name_reside', title: 'محل اقامت فرستنده'),
    CsvExportField(key: 't_name_reside', title: 'محل اقامت گیرنده'),
    CsvExportField(key: 'wordmost2', title: 'کلمه مرتبط'),
    CsvExportField(key: 't_name_ersali', title: 'نام گیرنده ارسالی'),
    CsvExportField(key: 'adres_name', title: 'آدرس'),
    CsvExportField(key: 'goshashte', title: 'گذشته'),
  ];

  /// تبدیل مقدار یک سلول به فرمت صحیح CSV
  ///
  /// دقیقاً مطابق منطق خروجی قبلی:
  /// - همه مقادیر داخل " قرار می‌گیرند.
  /// - " داخل متن به "" تبدیل می‌شود.
  String _escapeCsvValue(dynamic value) {
    final text = value?.toString() ?? '';

    final escaped = text.replaceAll('"', '""');

    return '"$escaped"';
  }

  /// ساخت متن CSV
  ///
  /// ساختار:
  ///
  /// "ستون اول","ستون دوم","ستون سوم"
  /// "مقدار","مقدار","مقدار"
  ///
  /// این ساختار همان الگوریتم خروجی قبلی شماست.
  String buildCsv({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
  }) {
    if (records.isEmpty || fields.isEmpty) {
      return '';
    }

    final StringBuffer csv = StringBuffer();

    // ------------------------------------------------------------
    // Header
    // ------------------------------------------------------------
    final headers = fields
        .map((field) => _escapeCsvValue(field.title))
        .join(',');

    csv.writeln(headers);

    // ------------------------------------------------------------
    // Rows
    // ------------------------------------------------------------
    for (final record in records) {
      final row = fields
          .map((field) {
            final value = record[field.key];

            return _escapeCsvValue(value);
          })
          .join(',');

      csv.writeln(row);
    }

    return csv.toString();
  }

  /// تبدیل متن CSV به بایت‌های UTF-8 همراه BOM
  ///
  /// BOM برای این است که Excel متن فارسی را به‌درستی تشخیص دهد.
  List<int> buildUtf8BomBytes(String csv) {
    final bytes = const Utf8Encoder().convert(csv);

    const bom = [0xEF, 0xBB, 0xBF];

    return [...bom, ...bytes];
  }

  /// خروجی گرفتن CSV
  ///
  /// Windows:
  ///   نمایش Save Dialog و ذخیره فایل در مسیر انتخاب‌شده
  ///
  /// Android:
  ///   ساخت فایل موقت و Share کردن آن
  Future<String?> export({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
    required String fileName,
  }) async {
    if (records.isEmpty || fields.isEmpty) {
      return null;
    }

    // ------------------------------------------------------------
    // ساخت CSV
    // ------------------------------------------------------------
    final csv = buildCsv(records: records, fields: fields);

    if (csv.isEmpty) {
      return null;
    }

    final bytes = buildUtf8BomBytes(csv);

    // ============================================================
    // Windows
    // ============================================================
    if (Platform.isWindows) {
      final saveLocation = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv']),
        ],
      );

      if (saveLocation == null) {
        return null;
      }

      final file = File(saveLocation.path);

      await file.writeAsBytes(bytes, flush: true);

      return saveLocation.path;
    }

    // ============================================================
    // Android
    // ============================================================
    if (Platform.isAndroid) {
      final tempDirectory = await getTemporaryDirectory();

      final file = File('${tempDirectory.path}/$fileName');

      await file.writeAsBytes(bytes, flush: true);

      try {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv', name: fileName)],
          subject: 'خروجی دبیرخانه',
          text: 'خروجی CSV دبیرخانه',
        );
      } finally {
        // بعد از Share نیازی به نگه داشتن فایل موقت نداریم.
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // حذف فایل موقت نباید باعث شکست عملیات Share شود.
        }
      }

      return file.path;
    }

    // ============================================================
    // سایر پلتفرم‌ها
    // ============================================================
    throw UnsupportedError('خروجی CSV در این پلتفرم پشتیبانی نمی‌شود.');
  }
}
