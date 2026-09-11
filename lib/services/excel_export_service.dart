import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'csv_export_service.dart';

class ExcelExportService {
  ExcelExportService._();

  static final ExcelExportService instance = ExcelExportService._();

  // ============================================================
  // BUILD EXCEL
  // ============================================================

  Future<List<int>> buildExcelBytes({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
  }) async {
    if (records.isEmpty || fields.isEmpty) {
      return [];
    }

    final excel = Excel.createExcel();

    // ============================================================
    // SHEET
    // ============================================================

    final defaultSheet = excel.getDefaultSheet();

    if (defaultSheet != null && defaultSheet != 'دبیرخانه') {
      excel.rename(defaultSheet, 'دبیرخانه');
    }

    final sheet = excel['دبیرخانه'];

    // راست به چپ برای فارسی
    sheet.isRTL = true;

    // ============================================================
    // HEADER STYLE
    // ============================================================

    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    // ============================================================
    // HEADER
    // ============================================================

    final List<CellValue> headerRow = [];

    for (final field in fields) {
      headerRow.add(TextCellValue(field.title));
    }

    sheet.appendRow(headerRow);

    // اعمال Style به Header
    for (int columnIndex = 0; columnIndex < fields.length; columnIndex++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: columnIndex, rowIndex: 0),
      );

      cell.cellStyle = headerStyle;
    }

    // ============================================================
    // DATA ROWS
    // ============================================================

    for (final record in records) {
      final List<CellValue> row = [];

      for (final field in fields) {
        row.add(_toCellValue(record[field.key]));
      }

      sheet.appendRow(row);
    }

    // ============================================================
    // COLUMN WIDTH
    // ============================================================

    _setColumnWidths(sheet: sheet, fields: fields);

    // ============================================================
    // SAVE
    // ============================================================

    final List<int>? bytes = excel.save();

    if (bytes == null) {
      throw Exception('ساخت فایل Excel با خطا مواجه شد.');
    }

    return bytes;
  }

  // ============================================================
  // CONVERT VALUE TO CELL VALUE
  // ============================================================

  CellValue _toCellValue(dynamic value) {
    if (value == null) {
      return TextCellValue('');
    }

    if (value is int) {
      return IntCellValue(value);
    }

    if (value is double) {
      return DoubleCellValue(value);
    }

    if (value is num) {
      return DoubleCellValue(value.toDouble());
    }

    if (value is bool) {
      return BoolCellValue(value);
    }

    return TextCellValue(value.toString());
  }

  // ============================================================
  // COLUMN WIDTH
  // ============================================================

  void _setColumnWidths({
    required Sheet sheet,
    required List<CsvExportField> fields,
  }) {
    for (int columnIndex = 0; columnIndex < fields.length; columnIndex++) {
      final field = fields[columnIndex];

      double width;

      switch (field.key) {
        case 'Shomare_Radif':
          width = 14;
          break;

        case 'date':
          width = 15;
          break;

        case 'saheb_name':
        case 'guy':
          width = 25;
          break;

        case 'onvan':
          width = 30;
          break;

        case 'comment':
          width = 40;
          break;

        case 'shomare_badi':
          width = 20;
          break;

        case 'from_pywa':
          width = 25;
          break;

        case 'sh_name_reside':
        case 't_name_reside':
          width = 25;
          break;

        case 'wordmost2':
          width = 25;
          break;

        case 't_name_ersali':
          width = 25;
          break;

        case 'adres_name':
          width = 40;
          break;

        case 'goshashte':
          width = 20;
          break;

        default:
          width = 22;
      }

      sheet.setColumnWidth(columnIndex, width);
    }
  }
  // ============================================================
  // EXPORT
  // ============================================================

  Future<String?> export({
    required List<Map<String, dynamic>> records,
    required List<CsvExportField> fields,
    required String fileName,
  }) async {
    if (records.isEmpty || fields.isEmpty) {
      return null;
    }

    final bytes = await buildExcelBytes(records: records, fields: fields);

    if (bytes.isEmpty) {
      return null;
    }

    // ============================================================
    // WINDOWS
    // ============================================================

    if (Platform.isWindows) {
      final saveLocation = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: ['xlsx']),
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
          [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName,
            ),
          ],
          subject: 'خروجی دبیرخانه',
          text: 'خروجی Excel دبیرخانه',
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

    throw UnsupportedError('خروجی Excel در این پلتفرم پشتیبانی نمی‌شود.');
  }

  // ============================================================
  // STREAM EXPORT
  // ============================================================

  Future<String?> exportStream({
    required Stream<List<Map<String, dynamic>>> recordsStream,
    required List<CsvExportField> fields,
    required String fileName,
    void Function(int exportedCount)? onProgress,
  }) async {
    if (fields.isEmpty) {
      return null;
    }

    final excel = Excel.createExcel();

    // ============================================================
    // SHEET
    // ============================================================

    final defaultSheet = excel.getDefaultSheet();

    if (defaultSheet != null && defaultSheet != 'دبیرخانه') {
      excel.rename(defaultSheet, 'دبیرخانه');
    }

    final sheet = excel['دبیرخانه'];

    // فارسی
    sheet.isRTL = true;

    // ============================================================
    // HEADER STYLE
    // ============================================================

    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
    );

    // ============================================================
    // HEADER
    // ============================================================

    final List<CellValue> headerRow = [];

    for (final field in fields) {
      headerRow.add(TextCellValue(field.title));
    }

    sheet.appendRow(headerRow);

    for (int columnIndex = 0; columnIndex < fields.length; columnIndex++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: columnIndex, rowIndex: 0),
      );

      cell.cellStyle = headerStyle;
    }

    // ============================================================
    // DATA
    // ============================================================

    int exportedCount = 0;

    await for (final records in recordsStream) {
      for (final record in records) {
        final List<CellValue> row = [];

        for (final field in fields) {
          row.add(_toCellValue(record[field.key]));
        }

        sheet.appendRow(row);

        exportedCount++;

        onProgress?.call(exportedCount);
      }
    }

    // ============================================================
    // EMPTY
    // ============================================================

    if (exportedCount == 0) {
      return null;
    }

    // ============================================================
    // COLUMN WIDTH
    // ============================================================

    _setColumnWidths(sheet: sheet, fields: fields);

    // ============================================================
    // SAVE
    // ============================================================

    final List<int>? bytes = excel.save();

    if (bytes == null) {
      throw Exception('ساخت فایل Excel با خطا مواجه شد.');
    }

    // ============================================================
    // WINDOWS
    // ============================================================

    if (Platform.isWindows) {
      final saveLocation = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Excel', extensions: ['xlsx']),
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
          [
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              name: fileName,
            ),
          ],
          subject: 'خروجی دبیرخانه',
          text: 'خروجی Excel دبیرخانه',
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

    throw UnsupportedError('خروجی Excel در این پلتفرم پشتیبانی نمی‌شود.');
  }
}
