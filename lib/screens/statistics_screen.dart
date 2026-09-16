import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';

import '../services/library_stats.dart';
import '../state/library_state.dart';
import '../theme/app_spacing.dart';

/// Analyseseite: Kennzahlen (Anzahl Medien, Speicherplatz, ...) sowie
/// grafische Auswertungen (Fotos/Videos pro Jahr, Saisonalität pro Monat,
/// häufigste Kameras). Lädt bewusst eine einzelne Momentaufnahme statt
/// Live-Streams (siehe AppDatabase.loadLibraryStats) – "Aktualisieren" in
/// der AppBar bzw. Pull-to-Refresh laden bei Bedarf neu.
class StatisticsScreen extends StatefulWidget {
  final LibraryState library;
  const StatisticsScreen({super.key, required this.library});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late Future<LibraryStats> _statsFuture = widget.library.db.loadLibraryStats();

  Future<void> _reload() {
    final future = widget.library.db.loadLibraryStats();
    setState(() => _statsFuture = future);
    return future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppTexte.of(context).statTitel),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: AppTexte.of(context).allgAktualisieren,
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<LibraryStats>(
        future: _statsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!;
          if (stats.totalCount == 0) {
            return Center(child: Text(AppTexte.of(context).statLeer));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                _SummaryGrid(stats: stats),
                if (stats.countsByYear.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(AppTexte.of(context).statProJahr, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xl, AppSpacing.xl, AppSpacing.sm),
                      child: _YearBarChart(countsByYear: stats.countsByYear),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Text(AppTexte.of(context).statSaisonalitaet, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xl, AppSpacing.xl, AppSpacing.sm),
                    child: _MonthBarChart(countsByMonth: stats.countsByMonth),
                  ),
                ),
                if (stats.topCameras.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text(AppTexte.of(context).statKameras, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _CameraList(cameras: stats.topCameras),
                ],
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final LibraryStats stats;
  const _SummaryGrid({required this.stats});


  static String _formatSize(int bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
    return '${(bytes / kb).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    // Tausendertrennung nach der aktiven Sprache: 1.234 gegen 1,234.
    final zahl = NumberFormat.decimalPattern(
        Localizations.localeOf(context).toString());
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.photo_library_outlined,
          label: AppTexte.of(context).statInsgesamt,
          value: zahl.format(stats.totalCount),
        ),
        _StatCard(
          icon: Icons.image_outlined,
          label: AppTexte.of(context).statFotos,
          value: zahl.format(stats.imageCount),
        ),
        _StatCard(
          icon: Icons.videocam_outlined,
          label: AppTexte.of(context).statVideos,
          value: zahl.format(stats.videoCount),
        ),
        _StatCard(
          icon: Icons.favorite_outline,
          label: AppTexte.of(context).suchoptFavoriten,
          value: zahl.format(stats.favoriteCount),
        ),
        _StatCard(
          icon: Icons.sd_storage_outlined,
          label: AppTexte.of(context).statSpeicherplatz,
          value: _formatSize(stats.totalSizeBytes),
        ),
        _StatCard(
          icon: Icons.delete_outline,
          label: AppTexte.of(context).statImPapierkorb,
          value: zahl.format(stats.trashedCount),
        ),
        _StatCard(
          icon: Icons.lock_outline,
          label: AppTexte.of(context).einstGesperrterOrdner,
          value: zahl.format(stats.lockedCount),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _StatCard({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearBarChart extends StatelessWidget {
  final Map<int, int> countsByYear;
  const _YearBarChart({required this.countsByYear});

  @override
  Widget build(BuildContext context) {
    final years = countsByYear.keys.toList()..sort();
    final maxCount = countsByYear.values.fold(0, (a, b) => a > b ? a : b);
    final color = Theme.of(context).colorScheme.primary;
    // Bei vielen Jahren nicht jedes Label zeichnen, sonst überlappen sie sich.
    final labelStep = (years.length / 12).ceil().clamp(1, years.length);

    return Semantics(
      label: AppTexte.of(context).statDiagrammJahr(
          years.map((y) => '$y: ${countsByYear[y]}').join(', ')),
      child: ExcludeSemantics(
        child: SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxCount == 0 ? 1 : maxCount * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${years[group.x.toInt()]}\n${rod.toY.round()}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= years.length || index % labelStep != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text('${years[index]}', style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < years.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: countsByYear[years[i]]!.toDouble(),
                  color: color,
                  width: years.length > 20 ? 6 : 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _MonthBarChart extends StatelessWidget {
  final Map<int, int> countsByMonth;
  const _MonthBarChart({required this.countsByMonth});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    final maxCount = countsByMonth.values.fold(0, (a, b) => a > b ? a : b);
    final monthFormat =
        DateFormat.MMM(Localizations.localeOf(context).toString());

    return Semantics(
      label: AppTexte.of(context).statDiagrammMonat([
        for (var m = 1; m <= 12; m++)
          '${monthFormat.format(DateTime(2000, m))}: ${countsByMonth[m] ?? 0}'
      ].join(', ')),
      child: ExcludeSemantics(
        child: SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxCount == 0 ? 1 : maxCount * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${monthFormat.format(DateTime(2000, group.x.toInt() + 1))}\n${rod.toY.round()}',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final month = value.toInt() + 1;
                  if (month < 1 || month > 12) return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(monthFormat.format(DateTime(2000, month)), style: const TextStyle(fontSize: 11)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var month = 1; month <= 12; month++)
              BarChartGroupData(x: month - 1, barRods: [
                BarChartRodData(
                  toY: (countsByMonth[month] ?? 0).toDouble(),
                  color: color,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ]),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _CameraList extends StatelessWidget {
  final List<CameraStat> cameras;
  const _CameraList({required this.cameras});

  @override
  Widget build(BuildContext context) {
    final maxCount = cameras.map((c) => c.count).fold(0, (a, b) => a > b ? a : b);
    final color = Theme.of(context).colorScheme.primary;
    final numberFormat =
        NumberFormat.decimalPattern(Localizations.localeOf(context).toString());

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            for (final camera in cameras)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 170,
                      child: Text(
                        camera.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            height: 16,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                          ),
                          FractionallySizedBox(
                            widthFactor: maxCount == 0 ? 0 : camera.count / maxCount,
                            child: Container(
                              height: 16,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 48,
                      child: Text(numberFormat.format(camera.count), textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
