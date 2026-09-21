import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class StatsExportService {
  StatsExportService._();

  static Future<Uint8List> buildPdf({
    required int selectedYear,
    required int totalLetters,
    required int thisMonthLetters,
    required List<String> monthNames,
    required Map<int, int> monthlyCounts,
    required String receiverTitle,
    required Map<String, int> receiverCounts,
    required String subjectTitle,
    required Map<String, int> subjectCounts,
    required String ownerTitle,
    required Map<String, int> ownerCounts,
    required Map<String, int> categoryCounts,
  }) async {
    final regular = await PdfGoogleFonts.notoNaskhArabicRegular();
    final bold = await PdfGoogleFonts.notoNaskhArabicBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regular,
        bold: bold,
      ),
    );

    pw.Widget rtlText(
      String text, {
      double size = 10,
      bool isBold = false,
      pw.TextAlign align = pw.TextAlign.right,
    }) {
      return pw.Directionality(
        textDirection: pw.TextDirection.rtl,
        child: pw.Text(
          text,
          textAlign: align,
          style: pw.TextStyle(
            font: isBold ? bold : regular,
            fontSize: size,
          ),
        ),
      );
    }

    pw.Widget countTable(
      String title,
      Map<String, int> values,
    ) {
      final rows = values.entries.take(10).map(
        (e) => [
          rtlText(e.key, size: 9),
          rtlText(_toPersianDigits(e.value.toString()), size: 9),
        ],
      ).toList();

      return pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            rtlText(title, size: 12, isBold: true),
            pw.SizedBox(height: 5),
            if (rows.isEmpty)
              rtlText('داده‌ای برای نمایش وجود ندارد.', size: 9)
            else
              pw.Table(
                border: pw.TableBorder.all(
                  color: PdfColors.grey400,
                  width: .5,
                ),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      rtlText('عنوان', size: 9, isBold: true),
                      rtlText('تعداد', size: 9, isBold: true),
                    ],
                  ),
                  ...rows.map(
                    (row) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: row[0],
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: row[1],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (_) => rtlText(
          'گزارش آماری دبیرخانه',
          size: 18,
          isBold: true,
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: rtlText(
            'صفحه ${_toPersianDigits(context.pageNumber.toString())}',
            size: 8,
          ),
        ),
        build: (_) => [
          rtlText(
            'گزارش سال ${_toPersianDigits(selectedYear.toString())}',
            size: 12,
            isBold: true,
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            children: [
              pw.Expanded(
                child: _summaryBox(
                  'کل نامه‌ها',
                  totalLetters,
                  regular,
                  bold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryBox(
                  'نامه‌های این ماه',
                  thisMonthLetters,
                  regular,
                  bold,
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _summaryBox(
                  'سال انتخاب‌شده',
                  selectedYear,
                  regular,
                  bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          rtlText('روند ماهانه', size: 13, isBold: true),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(
              color: PdfColors.grey400,
              width: .5,
            ),
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                ),
                children: [
                  for (final name in monthNames)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: rtlText(name, size: 7, isBold: true, align: pw.TextAlign.center),
                    ),
                ],
              ),
              pw.TableRow(
                children: [
                  for (int i = 1; i <= 12; i++)
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: rtlText(
                        _toPersianDigits((monthlyCounts[i] ?? 0).toString()),
                        size: 8,
                        align: pw.TextAlign.center,
                      ),
                    ),
                ],
              ),
            ],
          ),
          countTable(receiverTitle, receiverCounts),
          countTable(subjectTitle, subjectCounts),
          countTable(ownerTitle, ownerCounts),
          countTable('پراکندگی دسته‌بندی‌ها', categoryCounts),
        ],
      ),
    );

    return pdf.save();
  }

  static Future<void> printStats({
    required int selectedYear,
    required int totalLetters,
    required int thisMonthLetters,
    required List<String> monthNames,
    required Map<int, int> monthlyCounts,
    required String receiverTitle,
    required Map<String, int> receiverCounts,
    required String subjectTitle,
    required Map<String, int> subjectCounts,
    required String ownerTitle,
    required Map<String, int> ownerCounts,
    required Map<String, int> categoryCounts,
  }) async {
    final bytes = await buildPdf(
      selectedYear: selectedYear,
      totalLetters: totalLetters,
      thisMonthLetters: thisMonthLetters,
      monthNames: monthNames,
      monthlyCounts: monthlyCounts,
      receiverTitle: receiverTitle,
      receiverCounts: receiverCounts,
      subjectTitle: subjectTitle,
      subjectCounts: subjectCounts,
      ownerTitle: ownerTitle,
      ownerCounts: ownerCounts,
      categoryCounts: categoryCounts,
    );

    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<void> shareStatsPdf({
    required int selectedYear,
    required int totalLetters,
    required int thisMonthLetters,
    required List<String> monthNames,
    required Map<int, int> monthlyCounts,
    required String receiverTitle,
    required Map<String, int> receiverCounts,
    required String subjectTitle,
    required Map<String, int> subjectCounts,
    required String ownerTitle,
    required Map<String, int> ownerCounts,
    required Map<String, int> categoryCounts,
  }) async {
    final bytes = await buildPdf(
      selectedYear: selectedYear,
      totalLetters: totalLetters,
      thisMonthLetters: thisMonthLetters,
      monthNames: monthNames,
      monthlyCounts: monthlyCounts,
      receiverTitle: receiverTitle,
      receiverCounts: receiverCounts,
      subjectTitle: subjectTitle,
      subjectCounts: subjectCounts,
      ownerTitle: ownerTitle,
      ownerCounts: ownerCounts,
      categoryCounts: categoryCounts,
    );

    await Printing.sharePdf(
      bytes: bytes,
      filename: 'گزارش-آماری-$selectedYear.pdf',
    );
  }

  static pw.Widget _summaryBox(
    String title,
    int value,
    pw.Font regular,
    pw.Font bold,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(9),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: .6),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          pw.Text(
            _toPersianDigits(value.toString()),
            style: pw.TextStyle(font: bold, fontSize: 17),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: regular, fontSize: 8),
          ),
        ],
      ),
    );
  }

  static String _toPersianDigits(String value) {
    const en = '0123456789';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    for (var i = 0; i < en.length; i++) {
      value = value.replaceAll(en[i], fa[i]);
    }
    return value;
  }
}
