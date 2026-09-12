import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:memex/ui/core/widgets/emoji_icon.dart';

class TimelineItem {
  final String time;
  final String? title;
  final String? content;
  final String? icon;
  final String? color;
  final bool isFilledDot;

  TimelineItem({
    required this.time,
    this.title,
    this.content,
    this.icon,
    this.color,
    this.isFilledDot = false,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) {
    return TimelineItem(
      time: json['time'] as String? ?? '--:--',
      title: json['title'] as String?,
      content: json['content'] as String?,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      isFilledDot: json['is_filled_dot'] as bool? ?? false,
    );
  }
}

class TimelineCard extends StatelessWidget {
  final String title;
  final List<TimelineItem> items;
  final String? insight;
  final VoidCallback? onTap;

  const TimelineCard({
    super.key,
    required this.title,
    this.items = const [],
    this.insight,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0A0A0A),
                height: 1.3,
              ),
            ),
            const SizedBox(height: 24),

            // Timeline items
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              final dotColor = _parseColor(item.color ?? '#5B6CFF');

              return _buildTimelineItem(item, dotColor, isLast);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(TimelineItem item, Color dotColor, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: dot + line
          SizedBox(
            width: 32,
            child: Column(
              children: [
                const SizedBox(height: 4),
                // Solid filled dot
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                // Vertical line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFFE2E8F0),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Time + icon row
                  SizedBox(
                    height: 30,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.time,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF99A1AF),
                            height: 19.5 / 13,
                            letterSpacing: -0.08,
                          ),
                        ),
                        if (item.icon != null)
                          EmojiIcon(emoji: item.icon!, size: 16),
                      ],
                    ),
                  ),
                  if (item.title != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.title!,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: item.isFilledDot
                            ? const Color(0xFF99A1AF)
                            : const Color(0xFF0A0A0A),
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (item.content != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.content!,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF99A1AF),
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _parseColor(String colorStr) {
    if (colorStr.startsWith('#')) {
      return Color(int.parse(colorStr.substring(1), radix: 16) + 0xFF000000);
    }
    return const Color(0xFF5B6CFF);
  }
}
