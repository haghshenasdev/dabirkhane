import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../db/database_helper.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  int selectedYear = Jalali.now().year;

  List<int> years = [];

  int totalLetters = 0;
  int thisMonthLetters = 0;

  Map<int, int> monthlyCounts = {};
  Map<String, int> receiverCounts = {};
  Map<String, int> subjectCounts = {};
  Map<String, int> ownerCounts = {};
  Map<String, int> categoryCounts = {};

  bool loading = true;

  final List<String> monthNames = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      await loadYears();
      await loadStats();
    });
  }

  // ============================================================
  // بارگذاری سال‌های موجود
  // ============================================================

  Future<void> loadYears() async {
    try {
      final db = await DatabaseHelper.database;

      final result = await db.rawQuery('''
        SELECT DISTINCT substr(date,1,4) as year
        FROM daftare_andicator
        WHERE date IS NOT NULL
          AND TRIM(date) != ''
          AND substr(date,1,4) GLOB '[0-9][0-9][0-9][0-9]'
      ''');

      final loadedYears =
          result
              .map((e) => int.tryParse(e['year']?.toString() ?? '') ?? 0)
              .where((year) => year > 0)
              .toSet()
              .toList()
            ..sort();

      if (!mounted) return;

      setState(() {
        years = loadedYears;

        // اگر سال انتخاب‌شده دیگر وجود نداشت،
        // آخرین سال موجود انتخاب شود.
        if (!years.contains(selectedYear) && years.isNotEmpty) {
          selectedYear = years.last;
        }
      });
    } catch (e) {
      debugPrint('Stats loadYears error: $e');
    }
  }

  // ============================================================
  // بروزرسانی کامل صفحه
  // ============================================================

  Future<void> refreshStats() async {
    await loadYears();
    await loadStats();
  }

  // ============================================================
  // بارگذاری آمار
  // ============================================================

  Future<void> loadStats() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final db = await DatabaseHelper.database;

      // ============================================================
      // کل نامه‌ها
      // ============================================================

      final total = await db.rawQuery('''
        SELECT COUNT(*) as count
        FROM daftare_andicator
      ''');

      totalLetters = int.tryParse(total.first['count']?.toString() ?? '0') ?? 0;

      // ============================================================
      // ماه جاری
      // ============================================================

      final now = Jalali.now();

      final currentMonth =
          '${now.year}/${now.month.toString().padLeft(2, '0')}';

      final monthRes = await db.rawQuery(
        '''
        SELECT COUNT(*) as count
        FROM daftare_andicator
        WHERE date LIKE ?
        ''',
        ['$currentMonth%'],
      );

      thisMonthLetters =
          int.tryParse(monthRes.first['count']?.toString() ?? '0') ?? 0;

      // ============================================================
      // آمار ماهانه
      // ============================================================

      final monthData = await db.rawQuery(
        '''
        SELECT
          substr(date,6,2) as month,
          COUNT(*) as count
        FROM daftare_andicator
        WHERE substr(date,1,4) = ?
        GROUP BY month
        ORDER BY month
        ''',
        [selectedYear.toString()],
      );

      monthlyCounts = {for (int i = 1; i <= 12; i++) i: 0};

      for (final row in monthData) {
        final month = int.tryParse(row['month']?.toString() ?? '') ?? 0;

        final count = int.tryParse(row['count']?.toString() ?? '0') ?? 0;

        if (month >= 1 && month <= 12) {
          monthlyCounts[month] = count;
        }
      }

      // ============================================================
      // بیشترین گیرنده‌ها
      // ============================================================

      final receiverData = await db.rawQuery(
        '''
        SELECT
          TRIM(onvan) as onvan_clean,
          COUNT(*) as count
        FROM daftare_andicator
        WHERE substr(date,1,4) = ?
        GROUP BY onvan_clean
        HAVING count > 2
        ORDER BY count DESC
        LIMIT 6
        ''',
        [selectedYear.toString()],
      );

      receiverCounts.clear();

      for (final row in receiverData) {
        final value = row['onvan_clean']?.toString().trim() ?? '';

        final count = int.tryParse(row['count']?.toString() ?? '0') ?? 0;

        if (value.isNotEmpty) {
          receiverCounts[value] = count;
        }
      }

      // ============================================================
      // بیشترین موضوع‌ها
      // ============================================================

      final subjectData = await db.rawQuery(
        '''
        SELECT
          TRIM(guy) as guy_clean,
          COUNT(*) as count
        FROM daftare_andicator
        WHERE substr(date,1,4) = ?
        GROUP BY guy_clean
        HAVING count > 1
        ORDER BY count DESC
        LIMIT 6
        ''',
        [selectedYear.toString()],
      );

      subjectCounts.clear();

      for (final row in subjectData) {
        final value = row['guy_clean']?.toString().trim() ?? '';

        final count = int.tryParse(row['count']?.toString() ?? '0') ?? 0;

        if (value.isNotEmpty) {
          subjectCounts[value] = count;
        }
      }

      // ============================================================
      // بیشترین صاحب‌ها
      // ============================================================

      final ownerData = await db.rawQuery(
        '''
        SELECT
          TRIM(saheb_name) as saheb_clean,
          COUNT(*) as count
        FROM daftare_andicator
        WHERE substr(date,1,4) = ?
        GROUP BY saheb_clean
        HAVING count > 1
        ORDER BY count DESC
        LIMIT 6
        ''',
        [selectedYear.toString()],
      );

      ownerCounts.clear();

      for (final row in ownerData) {
        final value = row['saheb_clean']?.toString().trim() ?? '';

        final count = int.tryParse(row['count']?.toString() ?? '0') ?? 0;

        if (value.isNotEmpty) {
          ownerCounts[value] = count;
        }
      }

      // ============================================================
      // دسته‌بندی‌ها
      // ============================================================

      final categoryData = await db.rawQuery(
        '''
        SELECT
          TRIM(c.name) as cat_name,
          COUNT(*) as count
        FROM record_categories rc
        JOIN categories c
          ON c.id = rc.category_id
        JOIN daftare_andicator d
          ON d.Shomare_Radif = rc.record_id
        WHERE substr(d.date,1,4) = ?
        GROUP BY cat_name
        HAVING count > 0
        ORDER BY count DESC
        LIMIT 6
        ''',
        [selectedYear.toString()],
      );

      categoryCounts.clear();

      for (final row in categoryData) {
        final value = row['cat_name']?.toString().trim() ?? '';

        final count = int.tryParse(row['count']?.toString() ?? '0') ?? 0;

        if (value.isNotEmpty) {
          categoryCounts[value] = count;
        }
      }

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    } catch (e) {
      debugPrint('Stats loadStats error: $e');

      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Color get primaryColor {
    return Theme.of(context).colorScheme.primary;
  }

  Color get secondaryColor {
    return Theme.of(context).colorScheme.secondary;
  }

  Color get surfaceColor {
    return Theme.of(context).colorScheme.surface;
  }

  Color get textColor {
    return Theme.of(context).colorScheme.onSurface;
  }

  List<Color> get chartColors {
    final scheme = Theme.of(context).colorScheme;

    return [
      scheme.primary,
      scheme.secondary,
      scheme.tertiary,
      scheme.primary.withOpacity(.70),
      scheme.secondary.withOpacity(.70),
      scheme.tertiary.withOpacity(.70),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text(
          'آمار نامه‌ها',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: loading
          ? Center(child: CircularProgressIndicator(color: scheme.primary))
          : Stack(
              children: [
                Positioned(
                  top: -120,
                  right: -100,
                  child: _BackgroundGlow(color: scheme.primary, size: 300),
                ),
                Positioned(
                  top: 350,
                  left: -140,
                  child: _BackgroundGlow(color: scheme.secondary, size: 320),
                ),
                Positioned(
                  bottom: -120,
                  right: 100,
                  child: _BackgroundGlow(color: scheme.tertiary, size: 280),
                ),

                RefreshIndicator(
                  color: scheme.primary,
                  onRefresh: refreshStats,
                  child: Directionality(
                    textDirection: TextDirection.rtl,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 900;

                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            isWide ? 32 : 16,
                            10,
                            isWide ? 32 : 16,
                            40,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1400),
                              child: Column(
                                children: [
                                  _buildHeader(),
                                  const SizedBox(height: 20),
                                  _buildStatisticsCards(),
                                  const SizedBox(height: 18),
                                  _buildYearSelector(),
                                  const SizedBox(height: 18),
                                  _buildMonthlyChart(),
                                  const SizedBox(height: 18),
                                  _buildChartsGrid(),
                                  const SizedBox(height: 18),
                                  _buildOwnersChart(),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // Header
  // ============================================================

  Widget _buildHeader() {
    return _GlassContainer(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(colors: [primaryColor, secondaryColor]),
            ),
            child: const Icon(
              Icons.analytics_outlined,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'داشبورد آماری دبیرخانه',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'نمایش وضعیت و روند ثبت نامه‌ها',
                  style: TextStyle(
                    color: textColor.withOpacity(.60),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'بروزرسانی',
            onPressed: refreshStats,
            icon: Icon(Icons.refresh_rounded, color: primaryColor),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Statistics Cards
  // ============================================================

  Widget _buildStatisticsCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 650;

        if (isWide) {
          return Row(
            children: [
              Expanded(
                child: _statCard(
                  title: 'کل نامه‌ها',
                  value: totalLetters.toString(),
                  icon: Icons.mail_outline_rounded,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard(
                  title: 'نامه‌های این ماه',
                  value: thisMonthLetters.toString(),
                  icon: Icons.calendar_month_rounded,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _statCard(
                  title: 'سال انتخاب شده',
                  value: selectedYear.toString(),
                  icon: Icons.date_range_rounded,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _statCard(
                    title: 'کل نامه‌ها',
                    value: totalLetters.toString(),
                    icon: Icons.mail_outline_rounded,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statCard(
                    title: 'این ماه',
                    value: thisMonthLetters.toString(),
                    icon: Icons.calendar_month_rounded,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _statCard(
              title: 'سال انتخاب شده',
              value: selectedYear.toString(),
              icon: Icons.date_range_rounded,
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return _GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: color.withOpacity(.14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textColor.withOpacity(.60),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Year Selector
  // ============================================================

  Widget _buildYearSelector() {
    final scheme = Theme.of(context).colorScheme;

    return _GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: scheme.primary.withOpacity(.10),
            ),
            child: Icon(
              Icons.calendar_today_rounded,
              color: scheme.primary,
              size: 21,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              'سال آماری',
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
          ),

          if (years.isEmpty)
            Text(
              'اطلاعاتی وجود ندارد',
              style: TextStyle(color: textColor.withOpacity(.55)),
            )
          else
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: scheme.primary.withOpacity(.08),
                border: Border.all(color: scheme.primary.withOpacity(.14)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: years.contains(selectedYear) ? selectedYear : null,

                  // ارتفاع منوی بازشده
                  menuMaxHeight: MediaQuery.of(context).size.height * .65,

                  // عرض منوی بازشده
                  menuWidth: 150,

                  borderRadius: BorderRadius.circular(16),

                  dropdownColor: scheme.surface,

                  icon: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.primary,
                    ),
                  ),

                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),

                  padding: const EdgeInsets.symmetric(horizontal: 10),

                  // سال جدیدتر در بالای لیست
                  items: [...years].reversed
                      .map(
                        (year) => DropdownMenuItem<int>(
                          value: year,
                          child: SizedBox(
                            width: 110,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_outlined,
                                  size: 17,
                                  color: scheme.primary.withOpacity(.65),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  year.toString(),
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontWeight: year == selectedYear
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),

                  onChanged: (value) {
                    if (value == null || value == selectedYear) {
                      return;
                    }

                    setState(() {
                      selectedYear = value;
                    });

                    loadStats();
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // Monthly Chart
  // ============================================================

  Widget _buildMonthlyChart() {
    final values = List.generate(12, (index) => monthlyCounts[index + 1] ?? 0);

    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).toDouble();

    final chartMax = maxValue == 0 ? 5.0 : (maxValue * 1.25).ceilToDouble();

    return _GlassContainer(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'روند ثبت نامه‌ها',
            subtitle: 'تعداد نامه‌های ثبت‌شده در ماه‌های سال $selectedYear',
            icon: Icons.show_chart_rounded,
          ),
          const SizedBox(height: 25),
          SizedBox(
            height: 300,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: chartMax,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: chartMax / 5,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: textColor.withOpacity(.08),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: chartMax / 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor.withOpacity(.55),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 35,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index < 0 || index >= 12) {
                          return const SizedBox();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            monthNames[index].substring(
                              0,
                              monthNames[index].length > 3
                                  ? 3
                                  : monthNames[index].length,
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              color: textColor.withOpacity(.65),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => surfaceColor,
                    tooltipRoundedRadius: 12,
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final month = monthNames[spot.x.toInt()];

                        return LineTooltipItem(
                          '$month\n',
                          TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: '${spot.y.toInt()} نامه',
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      12,
                      (index) =>
                          FlSpot(index.toDouble(), values[index].toDouble()),
                    ),
                    isCurved: true,
                    curveSmoothness: .25,
                    barWidth: 4,
                    color: primaryColor,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: primaryColor,
                          strokeWidth: 2,
                          strokeColor: surfaceColor,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          primaryColor.withOpacity(.28),
                          primaryColor.withOpacity(.02),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Donut Charts
  // ============================================================

  Widget _buildChartsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;

        final width = wide
            ? (constraints.maxWidth - 18) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            SizedBox(
              width: width,
              child: _buildDonutCard(
                title: 'بیشترین گیرنده‌ها',
                subtitle: 'بر اساس عنوان نامه',
                icon: Icons.groups_outlined,
                data: receiverCounts,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildDonutCard(
                title: 'بیشترین موضوع‌ها',
                subtitle: 'بر اساس موضوع / طرف نامه',
                icon: Icons.topic_outlined,
                data: subjectCounts,
              ),
            ),
            SizedBox(
              width: width,
              child: _buildDonutCard(
                title: 'بیشترین دسته‌بندی‌ها',
                subtitle: 'دسته‌بندی نامه‌ها',
                icon: Icons.category_outlined,
                data: categoryCounts,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDonutCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Map<String, int> data,
  }) {
    final total = data.values.fold<int>(0, (sum, value) => sum + value);

    final colors = chartColors;

    return _GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title: title, subtitle: subtitle, icon: icon),
          const SizedBox(height: 20),
          if (data.isEmpty)
            _emptyChart()
          else
            Column(
              children: [
                SizedBox(
                  height: 245,
                  child: PieChart(
                    PieChartData(
                      centerSpaceRadius: 62,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      borderData: FlBorderData(show: false),
                      sections: List.generate(data.length, (index) {
                        final entry = data.entries.elementAt(index);

                        return PieChartSectionData(
                          value: entry.value.toDouble(),
                          color: colors[index % colors.length],
                          radius: 50,
                          showTitle: false,
                        );
                      }),
                      centerSpaceColor: surfaceColor.withOpacity(.75),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(0, -145),
                  child: SizedBox(
                    height: 90,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            total.toString(),
                            style: TextStyle(
                              color: textColor,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            'مورد',
                            style: TextStyle(
                              color: textColor.withOpacity(.55),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                _buildLegend(data, colors),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLegend(Map<String, int> data, List<Color> colors) {
    return Column(
      children: List.generate(data.length, (index) {
        final entry = data.entries.elementAt(index);

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors[index % colors.length],
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  entry.key,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor.withOpacity(.80),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                entry.value.toString(),
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ============================================================
  // Owners Chart
  // ============================================================

  Widget _buildOwnersChart() {
    if (ownerCounts.isEmpty) {
      return _GlassContainer(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              title: 'بیشترین صاحبان',
              subtitle: 'بیشترین ثبت‌کنندگان نامه در سال $selectedYear',
              icon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 20),
            _emptyChart(),
          ],
        ),
      );
    }

    final maxValue = ownerCounts.values.reduce((a, b) => a > b ? a : b);

    return _GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'بیشترین صاحبان',
            subtitle: 'بیشترین ثبت‌کنندگان نامه در سال $selectedYear',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: ownerCounts.length * 62.0 + 20,
            child: BarChart(
              BarChartData(
                maxY: maxValue == 0 ? 1 : maxValue.toDouble() * 1.25,
                minY: 0,
                alignment: BarChartAlignment.spaceAround,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: textColor.withOpacity(.07),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 100,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();

                        if (index < 0 || index >= ownerCounts.length) {
                          return const SizedBox();
                        }

                        return Padding(
                          padding: const EdgeInsets.only(left: 4, right: 8),
                          child: Text(
                            ownerCounts.keys.elementAt(index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor.withOpacity(.70),
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => surfaceColor,
                    tooltipRoundedRadius: 10,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} نامه',
                        TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                ),
                barGroups: List.generate(ownerCounts.length, (index) {
                  final value = ownerCounts.values.elementAt(index);

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: value.toDouble(),
                        width: 22,
                        color: primaryColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: maxValue.toDouble(),
                          color: textColor.withOpacity(.035),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Section Header
  // ============================================================

  Widget _sectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            color: primaryColor.withOpacity(.11),
          ),
          child: Icon(icon, color: primaryColor, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor.withOpacity(.52),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // Empty Chart
  // ============================================================

  Widget _emptyChart() {
    return SizedBox(
      height: 180,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 46,
              color: textColor.withOpacity(.15),
            ),
            const SizedBox(height: 10),
            Text(
              'اطلاعات کافی برای نمایش نمودار وجود ندارد',
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor.withOpacity(.45), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Glassmorphism Container
// ================================================================

class _GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _GlassContainer({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = theme.colorScheme.primary.withOpacity(
      isDark ? .18 : .12,
    );

    final backgroundColor = theme.colorScheme.surface.withOpacity(
      isDark ? .42 : .62,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: backgroundColor,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? .18 : .06),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ================================================================
// Background Glow
// ================================================================

class _BackgroundGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _BackgroundGlow({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withOpacity(.18),
              color.withOpacity(.06),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      ),
    );
  }
}
