import 'package:flutter/material.dart';
import 'package:memex/ui/core/cards/ui/glass_card.dart';

/// Static timeline snapshot for a media (book/movie/tv/music/podcast)
/// record. Frozen at creation time — status/rating edits made later in the
/// detail page do not update this widget's data, matching the existing
/// mood-badge precedent (live editing is detail-page-only).
class MediaCardWidget extends StatelessWidget {
  const MediaCardWidget({super.key, required this.data, this.onTap});

  final Map<String, dynamic> data;
  final VoidCallback? onTap;

  static const Map<String, String> _icons = {
    'book': '📖',
    'movie': '🎬',
    'tv': '📺',
    'music': '🎵',
    'podcast': '🎙️',
    'other': '🔖',
  };

  @override
  Widget build(BuildContext context) {
    final String mediaType = data['media_type'] as String? ?? 'other';
    final String title = data['title'] as String? ?? '';
    final String? comment = data['comment'] as String?;
    final int? rating = data['rating'] as int?;
    final icon = _icons[mediaType] ?? _icons['other']!;

    return SizedBox(
      width: double.infinity,
      child: GlassCard(
        onTap: onTap,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF334155),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (comment != null || rating != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (rating != null) '$rating/10',
                  if (comment != null) comment,
                ].join(' · '),
                style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
