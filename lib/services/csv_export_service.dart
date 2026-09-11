import 'dart:async';
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

  // ============================================================
  // CSV ESCAPE
  // ============================================================

  String _escapeCsvValue(dynamic value) {
    final text = value?.toString() ?? '';

    final escaped = text.replaceAll('"', '""');

    return '"$escaped"';
  }

  // ============================================================
  // BUILD HEADER
  // ============================================================

  String buildHeader({required List<CsvExportField> fields}) {
    return fields.map((field) => _escapeCsvValue(field.title)).join(',');
  }

  // ============================================================
  // BUILD ROW
  // ============================================================

  String buildRow({
    required Map<String, dynamic> record,
    required List<CsvExportField> fields,
  }) {
    return fields
        .map((field) {
          final value = record[field.key];

          return _escapeCsvValue(value);
        })
        .join(',');
  }

  // ============================================================
  // BUILD CSV
  // ============================================================

  String buildCsv({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
  }) {
    if (records.isEmpty || fields.isEmpty) {
      return '';
    }

    final StringBuffer csv = StringBuffer();

    csv.writeln(buildHeader(fields: fields));

    for (final record in records) {
      csv.writeln(buildRow(record: record, fields: fields));
    }

    return csv.toString();
  }

  // ============================================================
  // UTF-8 BOM
  // ============================================================

  List<int> buildUtf8BomBytes(String csv) {
    final bytes = const Utf8Encoder().convert(csv);

    const bom = [0xEF, 0xBB, 0xBF];

    return [...bom, ...bytes];
  }

  // ============================================================
  // EXPORT معمولی
  // ============================================================

  Future<String?> export({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
    required String fileName,
  }) async {
    if (records.isEmpty || fields.isEmpty) {
      return null;
    }

    final csv = buildCsv(records: records, fields: fields);

    if (csv.isEmpty) {
      return null;
    }

    final bytes = buildUtf8BomBytes(csv);

    // ============================================================
    // WINDOWS
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
    // ANDROID
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
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }

      return file.path;
    }

    throw UnsupportedError('خروجی CSV در این پلتفرم پشتیبانی نمی‌شود.');
  }

  // ============================================================
  // STREAM EXPORT
  // ============================================================
  //
  // مخصوص زمانی که تعداد رکوردها زیاد است.
  //
  // مثلاً:
  //
  // 100,000 رکورد
  //
  // به جای اینکه:
  //
  // List<Map<String,dynamic>> = 100,000
  //
  // داشته باشیم، رکوردها به صورت دسته‌ای دریافت می‌شوند.
  //
  Future<String?> exportStream({
    required Stream<List<Map<String, dynamic>>> recordsStream,
    required List<CsvExportField> fields,
    required String fileName,
    void Function(int exportedCount)? onProgress,
  }) async {
    if (fields.isEmpty) {
      return null;
    }

    // ============================================================
    // WINDOWS
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

      final sink = file.openWrite();

      try {
        // BOM
        sink.add(const [0xEF, 0xBB, 0xBF]);

        // Header
        sink.write('${buildHeader(fields: fields)}\r\n');

        int exportedCount = 0;

        await for (final records in recordsStream) {
          for (final record in records) {
            sink.write('${buildRow(record: record, fields: fields)}\r\n');

            exportedCount++;

            onProgress?.call(exportedCount);
          }

          // اجازه می‌دهیم جریان نوشتن فایل
          // مرتب Flush شود.
          await sink.flush();
        }
      } finally {
        await sink.close();
      }

      return saveLocation.path;
    }

    // ============================================================
    // ANDROID
    // ============================================================

    if (Platform.isAndroid) {
      final tempDirectory = await getTemporaryDirectory();

      final file = File('${tempDirectory.path}/$fileName');

      final sink = file.openWrite();

      try {
        // BOM
        sink.add(const [0xEF, 0xBB, 0xBF]);

        // Header
        sink.write('${buildHeader(fields: fields)}\r\n');

        int exportedCount = 0;

        await for (final records in recordsStream) {
          for (final record in records) {
            sink.write('${buildRow(record: record, fields: fields)}\r\n');

            exportedCount++;

            onProgress?.call(exportedCount);
          }

          await sink.flush();
        }
      } finally {
        await sink.close();
      }

      try {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv', name: fileName)],
          subject: 'خروجی دبیرخانه',
          text: 'خروجی CSV دبیرخانه',
        );
      } finally {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }

      return file.path;
    }

    throw UnsupportedError('خروجی CSV در این پلتفرم پشتیبانی نمی‌شود.');
  }
}
