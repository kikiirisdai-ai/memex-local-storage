import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class TrendPoint {
  final String label;
  final double value;
  final bool isHighlight;

  TrendPoint({
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  factory TrendPoint.fromJson(Map<String, dynamic> json) {
    return TrendPoint(
      label: json['label'] as String? ?? '',
      value: (json['value'] as num? ?? 0).toDouble(),
      isHighlight: json['is_highlight'] as bool? ?? false,
    );
  }
}

class TrendChartCard extends StatelessWidget {
  final String title;
  final String? topRightText;
  final List<TrendPoint> points;
  final Map<String, dynamic>? highlightInfo;
  final String color;
  final String? insight;
  final VoidCallback? onTap;

  const TrendChartCard({
    super.key,
    required this.title,
    this.topRightText,
    this.points = const [],
    this.highlightInfo,
    this.color = '#6366F1',
    this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const lineColor = Color(0xFF6366F1);

    final spots = points.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.value);
    }).toList();

    double maxY = points.isNotEmpty
        ? points.map((p) => p.value).reduce((a, b) => a > b ? a : b)
        : 10;
    // Round up to nearest even number for clean grid
    maxY = ((maxY / 2).ceil() * 2).toDouble();
    if (maxY < 10) maxY = 10;
    const double minY = 0;
    final interval = maxY / 5;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: title + top right text
            SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'PingFang SC',
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        height: 28 / 18,
                        letterSpacing: -0.44,
                        color: Color(0xFF101828),
                      ),
                    ),
                  ),
                  if (topRightText != null)
                    Text(
                      topRightText!,
                      style: const TextStyle(
                        fontFamily: 'PingFang SC',
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 20 / 14,
                        letterSpacing: -0.15,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Chart
            AspectRatio(
              aspectRatio: 1.4,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: interval,
                    getDrawingHorizontalLine: (value) {
                      return const FlLine(
                        color: Color(0xFFE5E7EB),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < points.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                points[index].label,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF9CA3AF),
                                  height: 1.0,
                                ),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: interval,
                        reservedSize: 32,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF9CA3AF),
                              height: 1.0,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minX: 0,
                  maxX: (points.length - 1).toDouble(),
                  minY: minY,
                  maxY: maxY,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: lineColor,
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: lineColor,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  lineTouchData: const LineTouchData(enabled: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
