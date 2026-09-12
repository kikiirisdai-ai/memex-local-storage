import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InsightBubble {
  final String label;
  final num value;
  final String color;
  final String? subLabel;
  final bool isHighlight;

  InsightBubble({
    required this.label,
    required this.value,
    this.color = '#6366F1',
    this.subLabel,
    this.isHighlight = false,
  });

  factory InsightBubble.fromJson(Map<String, dynamic> json) {
    return InsightBubble(
      label: json['label'] as String? ?? '',
      value: json['value'] as num? ?? 1,
      color: json['color'] as String? ?? '#6366F1',
      subLabel: json['sub_label'] as String?,
      isHighlight: json['is_highlight'] as bool? ?? false,
    );
  }
}

class BubbleChartCard extends StatelessWidget {
  final String title;
  final List<InsightBubble> bubbles;
  final String? footer;
  final String? insight;
  final VoidCallback? onTap;

  const BubbleChartCard({
    super.key,
    required this.title,
    this.bubbles = const [],
    this.footer,
    this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sort bubbles so highlight is first (or handle in layout)
    // Actually, for Wrap, having the big one in the middle is hard.
    // We will use a custom Flow or just Wrap for now.
    // If there is a highlight bubble, we might want to place it prominently.
    // Simple approach: Just Wrap centered.

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          // Gradient border or shadow if needed, but design looks clean flat/soft
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'PingFang SC',
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0A0A0A),
                height: 20 / 14,
                letterSpacing: -0.08,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Bubbles Area — Figma exact positions
            LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final s = w / 330;

                final sorted = List<InsightBubble>.from(bubbles);
                sorted.sort((a, b) {
                  if (a.isHighlight && !b.isHighlight) return -1;
                  if (!a.isHighlight && b.isHighlight) return 1;
                  return b.value.compareTo(a.value);
                });

                // Figma: center, top-left, top-right, bottom-left, bottom-right
                final specs = <Map<String, double>>[
                  {'left': 95, 'top': 84, 'size': 140},
                  {'left': 10, 'top': 34, 'size': 90},
                  {'left': 206, 'top': 8, 'size': 100},
                  {'left': 32, 'top': 211, 'size': 100},
                  {'left': 216, 'top': 193, 'size': 100},
                ];

                return SizedBox(
                  height: 310 * s,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (int i = 0;
                          i < sorted.length && i < specs.length;
                          i++)
                        Positioned(
                          left: specs[i]['left']! * s,
                          top: specs[i]['top']! * s,
                          child: _buildBubble(
                            sorted[i],
                            specs[i]['size']! * s,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 24),

            // Footer
            if (footer != null)
              Text(
                footer!,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF99A1AF),
                  height: 18 / 12,
                  letterSpacing: 0,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBubble(InsightBubble bubble, double size) {
    final color = _parseColor(bubble.color);
    final bgColor = color.withValues(alpha: 0.15);
    final bool isSolid = bubble.isHighlight;

    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isSolid ? color : bgColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          bubble.label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSolid ? Colors.white : color,
            fontWeight: FontWeight.w600,
            fontSize: isSolid ? 18 : 14,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Color _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      return Color(int.parse(colorStr.substring(1), radix: 16) + 0xFF000000);
    }
    // Fallback simple names
    switch (colorStr.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      case 'black':
        return Colors.black;
      case 'white':
        return Colors.white;
      default:
        return const Color(0xFF5B6CFF);
    }
  }
}
