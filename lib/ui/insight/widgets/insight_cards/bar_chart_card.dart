import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/ui/core/widgets/emoji_icon.dart';

class BarItem {
  final String label;
  final double value;
  final String? icon;
  final String? color;
  final bool isHighlight;

  BarItem({
    required this.label,
    required this.value,
    this.icon,
    this.color,
    this.isHighlight = false,
  });

  factory BarItem.fromJson(Map<String, dynamic> json) {
    return BarItem(
      label: json['label'] as String? ?? '',
      value: (json['value'] as num? ?? 0).toDouble(),
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      isHighlight: json['is_highlight'] as bool? ?? false,
    );
  }
}

class BarChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String unit;
  final List<BarItem> items;
  final String? insight;
  final VoidCallback? onTap;

  const BarChartCard({
    super.key,
    required this.title,
    this.subtitle,
    this.unit = '',
    this.items = const [],
    this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    double maxY = items.isNotEmpty
        ? items.map((e) => e.value).reduce((a, b) => a > b ? a : b)
        : 10;
    if (maxY == 0) maxY = 1;

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
            // Title
            SizedBox(
              height: 28,
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

            // Subtitle
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
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
            const SizedBox(height: 24),

            // Items
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              final percent = (item.value / maxY).clamp(0.0, 1.0);
              final barColor = item.color != null
                  ? _parseColor(item.color!)
                  : const Color(0xFF5B6CFF);

              return Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Emoji icon container
                    if (item.icon != null) ...[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF2F4FF),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: EmojiIcon(
                            emoji: item.icon!,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],

                    // Label + bar + value
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Label and value row
                          SizedBox(
                            height: 20,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item.label,
                                  style: const TextStyle(
                                    fontFamily: 'PingFang SC',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    height: 20 / 14,
                                    letterSpacing: -0.15,
                                    color: Color(0xFF364153),
                                  ),
                                ),
                                Text(
                                  '${item.value % 1 == 0 ? item.value.toInt() : item.value}$unit',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    height: 20 / 14,
                                    letterSpacing: -0.15,
                                    color: const Color(0xFF101828),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Progress bar
                          SizedBox(
                            height: 6,
                            child: Stack(
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5E7EB),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: percent,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Color _parseColor(String colorStr) {
    if (colorStr.isEmpty) return const Color(0xFF5B6CFF);
    try {
      String hex = colorStr.replaceAll('#', '').trim();
      final match = RegExp(r'^[0-9a-fA-F]{6,8}').firstMatch(hex);
      if (match != null) {
        hex = match.group(0)!;
      } else {
        return const Color(0xFF5B6CFF);
      }
      if (hex.length == 6) {
        return Color(int.parse(hex, radix: 16) + 0xFF000000);
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (e) {
      debugPrint('Error parsing color: $colorStr - $e');
    }
    return const Color(0xFF5B6CFF);
  }
}
