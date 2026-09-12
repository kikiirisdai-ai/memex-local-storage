import 'package:flutter/material.dart';
import 'package:memex/domain/models/card_detail_model.dart';

/// Small pill showing the card's recorded mood, e.g. "🙂 满足 · 7/10".
///
/// When the card has no mood and [onTap] is provided, renders a muted "😶"
/// pill instead so the user can still rate it. Without [onTap] (static
/// contexts like share images) a mood-less card renders nothing.
class CardMoodBadge extends StatelessWidget {
  const CardMoodBadge({super.key, required this.detail, this.onTap});

  final CardDetailModel detail;

  /// Invoked when the user taps the badge to (re)rate the card.
  final VoidCallback? onTap;

  /// Fallback face when the mood label itself contains no emoji.
  static String emojiForScore(int score) {
    if (score >= 8) return '😄';
    if (score >= 6) return '🙂';
    if (score >= 4) return '😐';
    if (score >= 2) return '😕';
    return '😞';
  }

  static final _emojiPattern = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
    unicode: true,
  );

  @override
  Widget build(BuildContext context) {
    final score = detail.moodScore;
    if (score == null && onTap == null) return const SizedBox.shrink();

    final String text;
    if (score == null) {
      text = '😶';
    } else {
      final label = detail.moodLabel;
      final hasEmojiInLabel = label != null && _emojiPattern.hasMatch(label);
      final face = hasEmojiInLabel ? '' : '${emojiForScore(score)} ';
      text = label != null ? '$face$label · $score/10' : '$face$score/10';
    }

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: score == null ? const Color(0xFFF1F5F9) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: score == null
              ? const Color(0xFF94A3B8)
              : const Color(0xFF6366F1),
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}

/// Bottom-sheet body with ten tap-to-pick mood scores. Pops with the chosen
/// int (1-10) or null when dismissed.
class MoodScorePicker extends StatelessWidget {
  const MoodScorePicker({super.key, this.currentScore});

  final int? currentScore;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 12,
          children: [
            for (var score = 1; score <= 10; score++)
              _ScoreOption(
                score: score,
                selected: score == currentScore,
                onTap: () => Navigator.pop(context, score),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScoreOption extends StatelessWidget {
  const _ScoreOption({
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                selected ? const Color(0xFF6366F1) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Column(
          children: [
            Text(
              CardMoodBadge.emojiForScore(score),
              style: const TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 2),
            Text(
              '$score',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
