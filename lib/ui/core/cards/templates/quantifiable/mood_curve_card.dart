import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/ui/core/cards/ui/glass_card.dart';

/// Line chart for a rollup card's per-period mood scores (e.g. one point per
/// weekday for a weekly summary). Points with no score (`null`) render as a
/// bare axis label with no dot, and the line breaks across the gap instead
/// of interpolating through a day that has no data.
class MoodCurveCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  const MoodCurveCard({super.key, required this.data, this.onTap});

  @override
  Widget build(BuildContext context) {
    final labels = (data['labels'] as List?)?.cast<String>() ?? const [];
    final rawScores = (data['scores'] as List?) ?? const [];
    final scores = rawScores.map((s) => (s as num?)?.toDouble()).toList();
    final average = (data['average'] as num?)?.toInt();
    const lineColor = Color(0xFF6366F1);

    // Split into contiguous runs of present points so the line never draws
    // across a missing day — each run is its own LineChartBarData.
    final barsData = <LineChartBarData>[];
    var run = <FlSpot>[];
    for (var i = 0; i < scores.length; i++) {
      final score = scores[i];
      if (score == null) {
        if (run.length > 1) barsData.add(_barFor(run, lineColor));
        if (run.isNotEmpty) barsData.add(_dotOnlyBarFor(run, lineColor));
        run = [];
        continue;
      }
      run.add(FlSpot(i.toDouble(), score));
    }
    if (run.length > 1) barsData.add(_barFor(run, lineColor));
    if (run.isNotEmpty) barsData.add(_dotOnlyBarFor(run, lineColor));

    return SizedBox(
      width: double.infinity,
      child: GlassCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '情绪曲线',
                  style: TextStyle(
                    fontFamily: 'PingFang SC',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0A0A0A),
                  ),
                ),
                if (average != null)
                  Text(
                    '均值 $average/10',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9CA3AF),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            AspectRatio(
              aspectRatio: 1.8,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 2,
                    getDrawingHorizontalLine: (value) => const FlLine(
                      color: Color(0xFFE5E7EB),
                      strokeWidth: 1,
                    ),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= labels.length) {
                            return const SizedBox();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              labels[index],
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF9CA3AF),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (labels.isEmpty ? scores.length : labels.length) - 1.0,
                  minY: 0,
                  maxY: 10,
                  lineBarsData: barsData,
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static LineChartBarData _barFor(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.3,
      color: color,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  /// A run of exactly one present point has nothing to connect a line
  /// through — still show its dot on its own zero-length "bar".
  static LineChartBarData _dotOnlyBarFor(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Colors.transparent,
      barWidth: 0,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 4,
          color: color,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(show: false),
    );
  }
}
