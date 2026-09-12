import 'package:flutter/material.dart';
import 'package:memex/data/model/chat_artifact.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/data/services/goal_suggestion_resolution_store.dart';
import 'package:memex/utils/logger.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

final _logger = getLogger('GoalSuggestionArtifactCard');

/// Inline "confirm this goal progress?" card attached to a quick-capture
/// reply. Not a navigable artifact — its only interaction is the confirm
/// button. Resolution state is read from [GoalSuggestionResolutionStore],
/// keyed by [ChatArtifact.artifactId], so it survives app restarts and
/// reopening old chat history.
class GoalSuggestionArtifactCard extends StatefulWidget {
  const GoalSuggestionArtifactCard({
    super.key,
    required this.artifact,
    GoalService? goalService,
    GoalSuggestionResolutionStore? resolutionStore,
  })  : _goalService = goalService,
        _resolutionStore = resolutionStore;

  final ChatArtifact artifact;
  final GoalService? _goalService;
  final GoalSuggestionResolutionStore? _resolutionStore;

  GoalService get goalService => _goalService ?? GoalService.instance;
  GoalSuggestionResolutionStore get resolutionStore =>
      _resolutionStore ?? GoalSuggestionResolutionStore.instance;

  @override
  State<GoalSuggestionArtifactCard> createState() =>
      _GoalSuggestionArtifactCardState();
}

class _GoalSuggestionArtifactCardState
    extends State<GoalSuggestionArtifactCard> {
  bool? _resolved; // null while the initial lookup is in flight
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.resolutionStore.isResolved(widget.artifact.artifactId).then((v) {
      if (mounted) setState(() => _resolved = v);
    });
  }

  Future<void> _confirm() async {
    if (_busy || _resolved != false) return;
    setState(() => _busy = true);

    final artifact = widget.artifact;
    final goalId = artifact.goalSuggestionGoalId;
    final goalType = artifact.goalSuggestionGoalType;
    final delta = artifact.goalSuggestionDelta;
    if (goalId == null || goalType == null) {
      setState(() => _busy = false);
      return;
    }

    bool ok;
    try {
      ok = goalType == 'quantitative'
          ? await widget.goalService.incrementProgress(goalId, delta ?? 1)
          : await widget.goalService.markCompleted(goalId);
    } catch (e, stack) {
      _logger.warning('Failed to confirm goal suggestion', e, stack);
      ok = false;
    }

    if (!mounted) return;
    if (ok) {
      // The goal update above already succeeded; a failure here is just a
      // bookkeeping write, so it must not roll that back or leave the
      // button stuck disabled — reset _busy and surface an error either way.
      try {
        await widget.resolutionStore.markResolved(artifact.artifactId);
        if (!mounted) return;
        setState(() {
          _resolved = true;
          _busy = false;
        });
        ToastHelper.showSuccess(context, UserStorage.l10n.saved);
      } catch (e, stack) {
        _logger.warning(
            'Goal updated but failed to persist resolution state', e, stack);
        if (!mounted) return;
        setState(() => _busy = false);
        ToastHelper.showError(context, UserStorage.l10n.updateFailed('goal'));
      }
    } else {
      setState(() => _busy = false);
      ToastHelper.showError(context, UserStorage.l10n.updateFailed('goal'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final artifact = widget.artifact;
    final title = artifact.goalSuggestionTitle ?? '';
    final goalType = artifact.goalSuggestionGoalType;
    final delta = artifact.goalSuggestionDelta;
    // The goal title itself is rendered as its own [Text] below so it stays
    // independently findable regardless of the surrounding sentence.
    final actionText = goalType == 'binary'
        ? UserStorage.l10n.goalSuggestionMarkComplete(title)
        : UserStorage.l10n
            .goalSuggestionIncrement(title, (delta ?? 1).toStringAsFixed(0));

    final resolved = _resolved;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                Text(
                  actionText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (resolved == null)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (resolved)
            Text(
              UserStorage.l10n.goalSuggestionConfirmed,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            )
          else
            FilledButton(
              onPressed: _busy ? null : _confirm,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
              ),
              child: Text(UserStorage.l10n.goalSuggestionConfirm),
            ),
        ],
      ),
    );
  }
}
