import 'package:flutter/material.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

/// The three persistent actions shown under the super-agent input: create a
/// timeline card directly, hand the text to the AI chat, or polish it first.
/// All three are disabled together via [enabled] (e.g. while the input is
/// empty) by passing `null` callbacks to the underlying buttons.
class InputActionButtons extends StatelessWidget {
  const InputActionButtons({
    super.key,
    required bool enabled,
    required VoidCallback? onCreateCard,
    required VoidCallback? onAiInteract,
    required VoidCallback? onPolish,
    bool isPolishing = false,
  })  : _enabled = enabled,
        _onCreateCard = onCreateCard,
        _onAiInteract = onAiInteract,
        _onPolish = onPolish,
        _isPolishing = isPolishing;

  final bool _enabled;
  final VoidCallback? _onCreateCard;
  final VoidCallback? _onAiInteract;
  final VoidCallback? _onPolish;

  /// While true, the 润色 (polish) button shows a spinner and is disabled so
  /// a second tap can't start a concurrent polish() call.
  final bool _isPolishing;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: l10n.actionCreateCardTriggerHint,
            triggerMode: TooltipTriggerMode.longPress,
            child: _buildActionButton(
              key: const ValueKey('action_create_card'),
              icon: Icons.style_outlined,
              label: l10n.actionCreateCard,
              onPressed: _enabled ? _onCreateCard : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            key: const ValueKey('action_ai_interact'),
            icon: Icons.chat_bubble_outline,
            label: l10n.actionAiInteract,
            onPressed: _enabled ? _onAiInteract : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionButton(
            key: const ValueKey('action_polish'),
            icon: Icons.auto_fix_high_outlined,
            label: l10n.actionPolish,
            onPressed: (_enabled && !_isPolishing) ? _onPolish : null,
            showSpinner: _isPolishing,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool showSpinner = false,
  }) {
    return TextButton.icon(
      key: key,
      onPressed: onPressed,
      icon: showSpinner
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textTertiary,
              ),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: TextButton.styleFrom(
        foregroundColor:
            onPressed == null ? AppColors.textTertiary : AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }
}
