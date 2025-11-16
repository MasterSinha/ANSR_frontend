// lib/analysis_page.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AnalysisPage extends StatefulWidget {
  const AnalysisPage({Key? key}) : super(key: key);

  @override
  State<AnalysisPage> createState() => _AnalysisPageState();
}

enum TrendWindow { month, year }
enum FilterType { all, income, expense }

class _AnalysisPageState extends State<AnalysisPage> {
  final supabase = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _records = [];
  TrendWindow _trendWindow = TrendWindow.month;

  // --- NEW state for interactive filter & charts
  FilterType _filterType = FilterType.all;
  String _selectedCategory = 'All';
  int _rangeDays = 30; // 7, 30, 90, 365
  final _currencyFmt = NumberFormat.simpleCurrency(locale: 'en_IN', name: 'INR', decimalDigits: 0);

  // Auto-refetch timer
  Timer? _autoRefreshTimer;

  // Color palette for charts
  final List<Color> _chartPalette = [
    Colors.blue,
    Colors.green,
    Colors.redAccent,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.brown,
    Colors.pink,
    Colors.amber,
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();

    // Start auto refetch every 30 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      if (kDebugMode) debugPrint('Auto-refetching transactions...');
      await _fetchData();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // ---------------- Fetch ----------------
  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await supabase
          .from('transaction')
          .select('transaction_id, created_at, day, amount, sender_name, payment_method, payment_type, anomaly, category, message, user_id')
          .order('created_at', ascending: true);

      // Defensive handling: response may be List or PostgrestResponse-like
      final List<Map<String, dynamic>> listRecords = [];

      if (response is List) {
        for (var item in response) {
          if (item is Map<String, dynamic>) {
            listRecords.add(item);
          } else if (item is Map) {
            listRecords.add(Map<String, dynamic>.from(item));
          }
        }
      } else {
        // try to read `.data` if it's a wrapper object
        try {
          final data = (response as dynamic).data;
          if (data is List) {
            for (var item in data) {
              if (item is Map<String, dynamic>) {
                listRecords.add(item);
              } else if (item is Map) {
                listRecords.add(Map<String, dynamic>.from(item));
              }
            }
          } else {
            debugPrint('Unexpected supabase response shape: ${response.runtimeType}');
          }
        } catch (_) {
          debugPrint('Could not access .data on response, fallback response type: ${response.runtimeType}');
        }
      }

      debugPrint('Fetched ${listRecords.length} transactions from Supabase.');
      if (!mounted) return;
      setState(() {
        _records = listRecords;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('Fetch error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Supabase error: $e';
        _loading = false;
      });
    }
  }

  // ---------------- Helpers ----------------
  DateTime? _recordDate(Map<String, dynamic> r) {
    try {
      final created = r['created_at'];
      if (created != null) {
        final s = created.toString();
        final dt = DateTime.tryParse(s);
        if (dt != null) return dt;
      }
      final day = r['day'];
      if (day != null) {
        final s = day.toString();
        final dt = DateTime.tryParse(s);
        if (dt != null) return dt;
      }
    } catch (_) {}
    return null;
  }

  double _parseAmount(dynamic a) {
    if (a == null) return 0.0;
    if (a is num) return a.toDouble();
    try {
      var s = a.toString();
      s = s.replaceAll(',', '');
      s = s.replaceAll(RegExp(r'[^\d\.\-]'), '');
      return double.tryParse(s) ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // --- Nice number helper to create human-friendly axis steps
  double _niceStep(double range) {
    if (range <= 0.0) return 1.0;
    final exponent = pow(10, (log(range) / log(10)).floor()).toDouble();
    final candidates = [1.0, 2.0, 5.0, 10.0];

    for (final c in candidates) {
      final step = c * exponent;
      // pick step so there are <= 4 divisions (for readability)
      if ((range / step) <= 4.0) return step;
    }
    return 10.0 * exponent;
  }

  // ---------------- Aggregations ----------------

  /// daily out (expenses)
  Map<DateTime, double> _dailyOut() {
    final m = <DateTime, double>{};
    for (var r in _records) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'expense' || pt == 'out' || pt == 'withdrawal' || pt == 'debit')) continue;
      final dt = _recordDate(r);
      if (dt == null) continue;
      final k = DateTime(dt.year, dt.month, dt.day);
      m[k] = (m[k] ?? 0) + _parseAmount(r['amount']);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// daily in (income)
  Map<DateTime, double> _dailyIn() {
    final m = <DateTime, double>{};
    for (var r in _records) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'income' || pt == 'in' || pt == 'credit')) continue;
      final dt = _recordDate(r);
      if (dt == null) continue;
      final k = DateTime(dt.year, dt.month, dt.day);
      m[k] = (m[k] ?? 0) + _parseAmount(r['amount']);
    }
    return Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  /// category spending totals (expenses only)
  Map<String, double> _categorySpending() {
    final sums = <String, double>{};
    for (var r in _records) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'expense' || pt == 'out' || pt == 'debit')) continue;
      final cat = (r['category'] ?? 'Uncategorized').toString();
      sums[cat] = (sums[cat] ?? 0) + _parseAmount(r['amount']);
    }
    final entries = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  /// monthly totals for last 12 months (expenses only)
  Map<DateTime, double> _monthlySpendingLast12Months() {
    final Map<DateTime, double> sums = {};
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - 11, 1);
    for (var r in _records) {
      final dt = _recordDate(r);
      if (dt == null) continue;
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'expense' || pt == 'out' || pt == 'debit')) continue;
      final k = DateTime(dt.year, dt.month, 1);
      if (k.isBefore(DateTime(start.year, start.month, 1))) continue;
      sums[k] = (sums[k] ?? 0) + _parseAmount(r['amount']);
    }
    final months = <DateTime>[];
    DateTime cur = DateTime(start.year, start.month, 1);
    final end = DateTime(now.year, now.month, 1);
    while (!cur.isAfter(end)) {
      months.add(cur);
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
    final result = <DateTime, double>{};
    for (var m in months) result[m] = sums[m] ?? 0.0;
    return result;
  }

  /// yearly totals (expenses) grouped by year
  Map<int, double> _yearlySpending() {
    final Map<int, double> sums = {};
    for (var r in _records) {
      final dt = _recordDate(r);
      if (dt == null) continue;
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'expense' || pt == 'out' || pt == 'debit')) continue;
      sums[dt.year] = (sums[dt.year] ?? 0) + _parseAmount(r['amount']);
    }
    final entries = sums.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  // ---------------- NEW: Filtered helpers (used by NEW charts)
  List<Map<String, dynamic>> _applyFilters() {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _rangeDays));
    return _records.where((r) {
      final dt = _recordDate(r);
      if (dt == null) return false;
      if (dt.isBefore(cutoff)) return false;

      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (_filterType == FilterType.income && !(pt == 'income' || pt == 'in' || pt == 'credit')) return false;
      if (_filterType == FilterType.expense && !(pt == 'expense' || pt == 'out' || pt == 'debit')) return false;

      if (_selectedCategory != 'All') {
        final cat = (r['category'] ?? 'Uncategorized').toString();
        if (cat != _selectedCategory) return false;
      }

      return true;
    }).toList();
  }

  double _sumFilteredIncome(List<Map<String, dynamic>> rows) {
    double s = 0;
    for (var r in rows) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (pt == 'income' || pt == 'in' || pt == 'credit') s += _parseAmount(r['amount']);
    }
    return s;
  }

  double _sumFilteredExpense(List<Map<String, dynamic>> rows) {
    double s = 0;
    for (var r in rows) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (pt == 'expense' || pt == 'out' || pt == 'debit') s += _parseAmount(r['amount']);
    }
    return s;
  }

  Map<DateTime, double> _monthlySpendingFiltered(List<Map<String, dynamic>> rows) {
    // monthly totals for months that appear in filtered rows (backwards from now for _rangeDays)
    final Map<DateTime, double> sums = {};
    for (var r in rows) {
      final dt = _recordDate(r);
      if (dt == null) continue;
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      // treat only expenses for the monthly spending chart (makes most sense)
      if (!(pt == 'expense' || pt == 'out' || pt == 'debit')) continue;
      final k = DateTime(dt.year, dt.month, 1);
      sums[k] = (sums[k] ?? 0) + _parseAmount(r['amount']);
    }
    // ensure months in range appear (even if 0)
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: _rangeDays));
    DateTime cur = DateTime(cutoff.year, cutoff.month, 1);
    final end = DateTime(now.year, now.month, 1);
    while (!cur.isAfter(end)) {
      sums[cur] = sums[cur] ?? 0.0;
      cur = DateTime(cur.year, cur.month + 1, 1);
    }
    final entries = sums.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map.fromEntries(entries);
  }

  Map<String, double> _categorySpendingFiltered(List<Map<String, dynamic>> rows) {
    final sums = <String, double>{};
    for (var r in rows) {
      final pt = (r['payment_type'] ?? '').toString().toLowerCase();
      if (!(pt == 'expense' || pt == 'out' || pt == 'debit')) continue;
      final cat = (r['category'] ?? 'Uncategorized').toString();
      sums[cat] = (sums[cat] ?? 0) + _parseAmount(r['amount']);
    }
    final entries = sums.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<String> _allCategories() {
    final s = <String>{};
    for (var r in _records) {
      final cat = (r['category'] ?? 'Uncategorized').toString();
      s.add(cat);
    }
    final list = s.toList()..sort();
    return ['All', ...list];
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final dailyOut = _dailyOut();
    final dailyIn = _dailyIn();
    final categories = _categorySpending();
    final monthly = _monthlySpendingLast12Months();
    final yearly = _yearlySpending();

    // filtered dataset for the interactive charts
    final filteredRows = _applyFilters();
    final filteredIncome = _sumFilteredIncome(filteredRows);
    final filteredExpense = _sumFilteredExpense(filteredRows);
    final filteredNet = filteredIncome - filteredExpense;
    final filteredMonthly = _monthlySpendingFiltered(filteredRows);
    final filteredCategory = _categorySpendingFiltered(filteredRows);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analysis'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _fetchData),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : RefreshIndicator(
        onRefresh: _fetchData,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // daily in/out chart (unchanged)
            _chartCard(
              title: 'Daily Cashflow — In vs Out',
              child: SizedBox(height: 240, child: _buildDailyInOutChart(dailyIn, dailyOut)),
            ),
            const SizedBox(height: 12),

            // category pie (updated to include colors & chips)
            _chartCard(
              title: 'Spending by Category',
              child: SizedBox(height: 220, child: _buildCategoryPieAndList(categories)),
            ),
            const SizedBox(height: 12),

            // trend toggle (unchanged)
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Spending Trend', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ToggleButtons(
                isSelected: [_trendWindow == TrendWindow.month, _trendWindow == TrendWindow.year],
                onPressed: (i) => setState(() => _trendWindow = i == 0 ? TrendWindow.month : TrendWindow.year),
                children: const [
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Month')),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('Year'))
                ],
              ),
            ]),
            const SizedBox(height: 8),

            // trend chart (LEFT LABELS REMOVED, RIGHT LABELS SHOWN)
            _chartCard(
              title: _trendWindow == TrendWindow.month ? 'Last 12 months (Expenses)' : 'Yearly (Expenses)',
              child: SizedBox(
                  height: 220,
                  child: _trendWindow == TrendWindow.month ? _buildMonthlyTrendChart(monthly) : _buildYearlyTrendChart(yearly)),
            ),

            const SizedBox(height: 18),

            // ---------- NEW: Interactive filters + quick numeric outputs ----------
            _chartCard(
              title: 'Interactive Filters & Insights',
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Filters row
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Type filter
                    DropdownButton<FilterType>(
                      value: _filterType,
                      items: const [
                        DropdownMenuItem(value: FilterType.all, child: Text('All')),
                        DropdownMenuItem(value: FilterType.income, child: Text('Income')),
                        DropdownMenuItem(value: FilterType.expense, child: Text('Expense')),
                      ],
                      onChanged: (v) => setState(() => _filterType = v ?? FilterType.all),
                      hint: const Text('Type'),
                    ),

                    // Category filter (populated from data)
                    DropdownButton<String>(
                      value: _selectedCategory,
                      items: _allCategories().map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _selectedCategory = v ?? 'All'),
                      hint: const Text('Category'),
                    ),

                    // Time range filter
                    DropdownButton<int>(
                      value: _rangeDays,
                      items: const [
                        DropdownMenuItem(value: 7, child: Text('7 days')),
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                        DropdownMenuItem(value: 90, child: Text('90 days')),
                        DropdownMenuItem(value: 365, child: Text('365 days')),
                      ],
                      onChanged: (v) => setState(() => _rangeDays = v ?? 30),
                      hint: const Text('Range'),
                    ),

                    // Refresh filtered view
                    ElevatedButton.icon(
                      onPressed: () {
                        // small UX: re-run fetch to refresh backend data and reapply filters
                        _fetchData();
                      },
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                    )
                  ],
                ),

                const SizedBox(height: 12),

                // Numeric outputs (Income / Expense / Net) with labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _statTile('Income', filteredIncome, Colors.green),
                    _statTile('Expense', filteredExpense, Colors.redAccent),
                    _statTile('Net', filteredNet, filteredNet >= 0 ? Colors.green : Colors.redAccent),
                  ],
                ),

                const SizedBox(height: 12),

                // Quick info about rows shown
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Text('Showing ${filteredRows.length} transactions', style: const TextStyle(color: Colors.black54)),
                ),

                const SizedBox(height: 6),

                // Bar chart title + legend
                const Text('Monthly Spending (filtered)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(height: 160, child: _buildFilteredMonthlyBarChart(filteredMonthly)),

                const SizedBox(height: 12),

                // Pie chart title + legend
                const Text('Category share (filtered)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SizedBox(height: 200, child: _buildFilteredPieAndLegend(filteredCategory)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String title, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_currencyFmt.format(amount), style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    );
  }

  // ---------------- CHART BUILDERS FOR NEW VISUALS ----------------

  Widget _buildFilteredMonthlyBarChart(Map<DateTime, double> monthly) {
    final keys = monthly.keys.toList()..sort();
    if (keys.isEmpty) return const Center(child: Text('No data'));

    final values = keys.map((k) => monthly[k] ?? 0.0).toList();
    final rawMax = values.isNotEmpty ? values.reduce(max) : 1.0;
    final step = _niceStep(rawMax);
    final niceMaxY = (step * ((rawMax / step).ceil())).clamp(1.0, double.infinity);

    final groups = List.generate(keys.length, (i) {
      final color = _chartPalette[i % _chartPalette.length];
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: values[i],
            width: 14,
            color: color,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(show: true, toY: niceMaxY),
          ),
        ],
        showingTooltipIndicators: [0],
      );
    });

    // bottom label logic - show up to ~6 labels
    Widget bottomTitleWidget(double val, TitleMeta meta) {
      final idx = val.round().clamp(0, keys.length - 1);
      final maxLabels = 6;
      final showEvery = (keys.length / maxLabels).ceil().clamp(1, keys.length);
      if (idx % showEvery != 0) return const SizedBox.shrink();
      final d = keys[idx];
      return SideTitleWidget(child: Text(DateFormat.MMM().format(d), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
    }

    Widget rightTitleWidget(double val, TitleMeta meta) {
      const eps = 1e-6;
      if ((val - 0).abs() < eps || ((val % step).abs() < (step * 0.01)) || ((step - (val % step)).abs() < (step * 0.01))) {
        return SideTitleWidget(child: Text(_currencyFmt.format(val), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceBetween,
          maxY: niceMaxY * 1.02,
          barGroups: groups,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: rightTitleWidget, reservedSize: 72)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottomTitleWidget, reservedSize: 40)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true),
          barTouchData: BarTouchData(enabled: true),
        ),
      ),
    );
  }

  Widget _buildFilteredPieAndLegend(Map<String, double> categoryMap) {
    if (categoryMap.isEmpty) return const Center(child: Text('No category data'));
    final entries = categoryMap.entries.toList();
    final total = entries.fold<double>(0.0, (p, e) => p + e.value);

    final sections = entries.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final pct = total == 0 ? 0.0 : (e.value / total) * 100;
      final color = _chartPalette[i % _chartPalette.length];
      return PieChartSectionData(
        value: e.value,
        title: '${pct.toStringAsFixed(0)}%',
        radius: 48,
        color: color,
        titleStyle: const TextStyle(color: Colors.white, fontSize: 12),
        showTitle: pct >= 4,
      );
    }).toList();

    return Row(children: [
      SizedBox(width: 160, height: 160, child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 28))),
      const SizedBox(width: 12),
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.map((entry) {
              final i = entry.key;
              final e = entry.value;
              final pct = total == 0 ? 0.0 : (e.value / total) * 100;
              final color = _chartPalette[i % _chartPalette.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(
                    child: Row(children: [
                      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Flexible(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(_currencyFmt.format(e.value), style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('${pct.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  ])
                ]),
              );
            }).toList(),
          ),
        ),
      ),
    ]);
  }

  // ---------------- existing chart helpers (left unchanged except small color/legend polish) ----------------
  Widget _chartCard({required String title, required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox.shrink(),
          ]),
          const SizedBox(height: 8),
          child
        ]),
      ),
    );
  }

  // ---------------- Charts: Daily In/Out (fixed to avoid overflow and left Y labels removed) ----------------
  Widget _buildDailyInOutChart(Map<DateTime, double> inMap, Map<DateTime, double> outMap) {
    final dates = <DateTime>{}..addAll(inMap.keys)..addAll(outMap.keys);
    final sorted = dates.toList()..sort();
    if (sorted.isEmpty) return const Center(child: Text('No daily data'));

    final inValues = sorted.map((d) => inMap[d] ?? 0.0).toList();
    final outValues = sorted.map((d) => outMap[d] ?? 0.0).toList();
    final maxY = max(1.0, max(inValues.reduce(max), outValues.reduce(max)));

    final spotsIn = List.generate(sorted.length, (i) => FlSpot(i.toDouble(), inValues[i]));
    final spotsOut = List.generate(sorted.length, (i) => FlSpot(i.toDouble(), outValues[i]));

    // bottom label logic (show up to ~6 evenly spaced)
    Widget bottomTitleWidgets(double val, TitleMeta meta) {
      final int idx = val.round().clamp(0, sorted.length - 1);
      final int showEvery = (sorted.length / 6).ceil().clamp(1, sorted.length);
      if (idx % showEvery != 0) return const SizedBox.shrink();
      final d = sorted[idx];
      return SideTitleWidget(child: Text(DateFormat.MMMd().format(d), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
    }

    // right side currency labels (we want only right axis)
    Widget rightTitleWidgets(double val, TitleMeta meta) {
      final step = _niceStep(maxY);
      if (step <= 0) return const SizedBox.shrink();
      final closish = ((val / step) - (val / step).round()).abs() < 0.001;
      if (!closish && val != 0) return const SizedBox.shrink();
      return Text(_currencyFmt.format(val), style: const TextStyle(fontSize: 10));
    }

    // Chart inner height — caller wraps this widget in SizedBox(height: 240), so we make the chart height smaller than that
    const double innerChartHeight = 180;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Chart area (bounded)
        SizedBox(
          height: innerChartHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6.0),
            child: LineChart(LineChartData(
              minX: 0,
              maxX: (spotsIn.length - 1).toDouble(),
              minY: 0,
              maxY: maxY * 1.2,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottomTitleWidgets, reservedSize: 40)),
                // IMPORTANT: turn left titles off to avoid duplicate numbers; right titles show currency.
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 60, getTitlesWidget: rightTitleWidgets)),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false),
              lineTouchData: LineTouchData(enabled: true),
              lineBarsData: [
                LineChartBarData(
                    spots: spotsIn,
                    isCurved: true,
                    barWidth: 2.5,
                    dotData: FlDotData(show: false),
                    color: Colors.green,
                    belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.12))),
                LineChartBarData(
                    spots: spotsOut,
                    isCurved: true,
                    barWidth: 2.5,
                    dotData: FlDotData(show: false),
                    color: Colors.red,
                    belowBarData: BarAreaData(show: true, color: Colors.red.withOpacity(0.12))),
              ],
            )),
          ),
        ),

        const SizedBox(height: 8),
        // Legend
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [_legendDot(Colors.green, 'In'), const SizedBox(width: 12), _legendDot(Colors.red, 'Out')]),
      ],
    );
  }

  Widget _legendDot(Color c, String label) => Row(children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text(label)
  ]);

  // ---------------- Charts: Category Pie ----------------
  Widget _buildCategoryPieAndList(Map<String, double> categories) {
    if (categories.isEmpty) return const Center(child: Text('No category data'));
    final entries = categories.entries.toList();
    final total = entries.fold<double>(0.0, (p, e) => p + e.value);

    final sections = entries.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final pct = total == 0 ? 0.0 : (e.value / total) * 100;
      final color = _chartPalette[i % _chartPalette.length];
      return PieChartSectionData(
        value: e.value,
        title: '${pct.toStringAsFixed(1)}%',
        radius: 46,
        color: color,
        titleStyle: const TextStyle(color: Colors.white, fontSize: 11),
        showTitle: pct >= 3,
      );
    }).toList();

    return Row(children: [
      SizedBox(width: 160, height: 160, child: PieChart(PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 24))),
      const SizedBox(width: 12),
      Expanded(
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: entries.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final color = _chartPalette[i % _chartPalette.length];
            return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Flexible(
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                        ],
                      )),
                  const SizedBox(width: 8),
                  Text(_currencyFmt.format(e.value), style: const TextStyle(fontWeight: FontWeight.bold))
                ]));
          }).toList()),
        ),
      ),
    ]);
  }

  // ---------------- Charts: Monthly & Yearly Trend (LEFT Y LABELS REMOVED; RIGHT SHOWS VALUES) ----------------
  Widget _buildMonthlyTrendChart(Map<DateTime, double> months) {
    final keys = months.keys.toList()..sort();
    if (keys.isEmpty) return const Center(child: Text('No monthly data'));
    final values = keys.map((k) => months[k] ?? 0.0).toList();
    final rawMax = values.reduce(max);
    final step = _niceStep(rawMax);
    final niceMaxY = (step * ((rawMax / step).ceil())).clamp(1.0, double.infinity);

    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));

    Widget bottomTitle(double val, TitleMeta meta) {
      final idx = val.round().clamp(0, keys.length - 1);
      final d = keys[idx];
      return SideTitleWidget(child: Text(DateFormat.MMM().format(d), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
    }

    Widget rightTitle(double val, TitleMeta meta) {
      const eps = 1e-6;
      if ((val - 0).abs() < eps || ((val % step).abs() < (step * 0.01)) || ((step - (val % step)).abs() < (step * 0.01))) {
        return SideTitleWidget(child: Text(_currencyFmt.format(val), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: LineChart(LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: niceMaxY * 1.02,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottomTitle, reservedSize: 36)),
          // LEFT LABELS OFF
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // RIGHT LABELS ON
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: rightTitle, reservedSize: 72)),
        ),
        gridData: FlGridData(show: true),
        lineBarsData: [LineChartBarData(spots: spots, isCurved: true, barWidth: 2.5, dotData: FlDotData(show: true), color: Colors.blue, belowBarData: BarAreaData(show: true, color: Colors.blue.withOpacity(0.08)))],
      )),
    );
  }

  Widget _buildYearlyTrendChart(Map<int, double> yearly) {
    final keys = yearly.keys.toList()..sort();
    if (keys.isEmpty) return const Center(child: Text('No yearly data'));
    final values = keys.map((k) => yearly[k] ?? 0.0).toList();
    final rawMax = values.reduce(max);
    final step = _niceStep(rawMax);
    final niceMaxY = (step * ((rawMax / step).ceil())).clamp(1.0, double.infinity);

    final spots = List.generate(values.length, (i) => FlSpot(i.toDouble(), values[i]));

    Widget bottomTitle(double val, TitleMeta meta) {
      final idx = val.round().clamp(0, keys.length - 1);
      final y = keys[idx];
      return SideTitleWidget(child: Text(y.toString(), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
    }

    Widget rightTitle(double val, TitleMeta meta) {
      const eps = 1e-6;
      if ((val - 0).abs() < eps || ((val % step).abs() < (step * 0.01)) || ((step - (val % step)).abs() < (step * 0.01))) {
        return SideTitleWidget(child: Text(_currencyFmt.format(val), style: const TextStyle(fontSize: 10)), axisSide: meta.axisSide);
      }
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6.0),
      child: LineChart(LineChartData(
        minX: 0,
        maxX: (spots.length - 1).toDouble(),
        minY: 0,
        maxY: niceMaxY * 1.02,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: bottomTitle, reservedSize: 40)),
          // LEFT LABELS OFF
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          // RIGHT LABELS ON
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: rightTitle, reservedSize: 72)),
        ),
        gridData: FlGridData(show: true),
        lineBarsData: [LineChartBarData(spots: spots, isCurved: true, barWidth: 2.5, dotData: FlDotData(show: true), color: Colors.blueAccent, belowBarData: BarAreaData(show: true, color: Colors.blueAccent.withOpacity(0.08)))],
      )),
    );
  }
}

