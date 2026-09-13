import 'package:flutter/material.dart';
import 'package:memex/domain/models/card_detail_model.dart';
import 'package:memex/utils/user_storage.dart';

String _statusLabel(String status) {
  final l10n = UserStorage.l10n;
  switch (status) {
    case 'want':
      return l10n.mediaStatusWant;
    case 'doing':
      return l10n.mediaStatusDoing;
    case 'done':
      return l10n.mediaStatusDone;
    default:
      return status;
  }
}

/// Pill showing the media status ("想看/在看/看完"), independent from
/// rating. Renders nothing for non-media cards.
class MediaStatusBadge extends StatelessWidget {
  const MediaStatusBadge({super.key, required this.detail, this.onTap});

  final CardDetailModel detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (detail.mediaType == null) return const SizedBox.shrink();
    final status = detail.mediaStatusValue;
    if (status == null && onTap == null) return const SizedBox.shrink();
    final text = status != null
        ? _statusLabel(status)
        : UserStorage.l10n.mediaStatusUnset;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    if (onTap == null) return pill;
    return GestureDetector(onTap: onTap, child: pill);
  }
}

/// Bottom-sheet body with three tap-to-pick statuses. Pops with the chosen
/// status string or null when dismissed.
class MediaStatusPicker extends StatelessWidget {
  const MediaStatusPicker({super.key, this.currentStatus});

  final String? currentStatus;

  static const _order = ['want', 'doing', 'done'];

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
            for (final status in _order)
              GestureDetector(
                onTap: () => Navigator.pop(context, status),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: status == currentStatus
                        ? const Color(0xFFEEF2FF)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: status == currentStatus
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Text(_statusLabel(status)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pill showing the media rating + short comment. Renders nothing for
/// non-media cards; shows a muted placeholder when unrated.
class MediaRatingBadge extends StatelessWidget {
  const MediaRatingBadge({super.key, required this.detail, this.onTap});

  final CardDetailModel detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (detail.mediaType == null) return const SizedBox.shrink();
    final rating = detail.mediaRatingValue;
    final comment = detail.mediaComment;
    if (rating == null && comment == null && onTap == null) {
      return const SizedBox.shrink();
    }

    final String text;
    if (rating == null && comment == null) {
      text = '☆ ${UserStorage.l10n.mediaUnrated}';
    } else {
      text = [
        if (rating != null) '$rating/10',
        if (comment != null) comment,
      ].join(' · ');
    }

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            rating == null ? const Color(0xFFF1F5F9) : const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: rating == null
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

/// Bottom-sheet body: 1-10 rating picker + a short comment field. Pops with
/// a `(rating: int, comment: String?)` record, or null when dismissed.
class MediaRatingEditor extends StatefulWidget {
  const MediaRatingEditor({
    super.key,
    this.currentRating,
  });

  final int? currentRating;

  @override
  State<MediaRatingEditor> createState() => _MediaRatingEditorState();
}

class _MediaRatingEditorState extends State<MediaRatingEditor> {
  late int _rating;

  @override
  void initState() {
    super.initState();
    _rating = widget.currentRating ?? 5;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                for (var score = 1; score <= 10; score++)
                  GestureDetector(
                    onTap: () => setState(() => _rating = score),
                    child: Container(
                      width: 44,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: score == _rating
                            ? const Color(0xFFEEF2FF)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: score == _rating
                              ? const Color(0xFF6366F1)
                              : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Text('$score'),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(UserStorage.l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(context, _rating);
                  },
                  child: Text(UserStorage.l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
