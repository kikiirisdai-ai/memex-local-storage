import 'package:flutter/material.dart';
import 'package:memex/data/services/polish_service.dart';
import 'package:memex/utils/user_storage.dart';

/// A choice made from [showPolishCompareDialog]: the text the user picked
/// and which style produced it. `style` is `'original'`, `'plain'`, or
/// `'literary'`. When the user keeps the original text, `style` is
/// `'original'` and no polished-style metadata should be persisted.
class PolishChoice {
  const PolishChoice({required this.text, required this.style});

  final String text;
  final String style;
}

/// Shows a three-column comparison dialog: 原文 (original) / 通顺版 (plain) /
/// 文采版 (literary). Each column has a 「用这个」button that resolves the
/// dialog with the corresponding [PolishChoice]. A `null` variant in
/// [result] renders a "generation failed" placeholder with its button
/// disabled. Returns `null` if the dialog is dismissed without a choice.
Future<PolishChoice?> showPolishCompareDialog(
  BuildContext context, {
  required String original,
  required PolishResult result,
}) {
  return showDialog<PolishChoice>(
    context: context,
    builder: (context) => _PolishCompareDialog(
      original: original,
      result: result,
    ),
  );
}

class _PolishCompareDialog extends StatelessWidget {
  const _PolishCompareDialog({required this.original, required this.result});

  final String original;
  final PolishResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PolishColumn(
                  title: l10n.polishOriginal,
                  text: original,
                  buttonKey: const ValueKey('polish_use_original'),
                  onUse: () => Navigator.pop(
                    context,
                    PolishChoice(text: original, style: 'original'),
                  ),
                ),
                const SizedBox(height: 12),
                _PolishColumn(
                  title: l10n.polishPlain,
                  text: result.plain,
                  buttonKey: const ValueKey('polish_use_plain'),
                  onUse: result.plain == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            PolishChoice(text: result.plain!, style: 'plain'),
                          ),
                ),
                const SizedBox(height: 12),
                _PolishColumn(
                  title: l10n.polishLiterary,
                  text: result.literary,
                  buttonKey: const ValueKey('polish_use_literary'),
                  onUse: result.literary == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            PolishChoice(
                              text: result.literary!,
                              style: 'literary',
                            ),
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PolishColumn extends StatelessWidget {
  const _PolishColumn({
    required this.title,
    required this.text,
    required this.buttonKey,
    required this.onUse,
  });

  final String title;
  final String? text;
  final Key buttonKey;
  final VoidCallback? onUse;

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              text ?? l10n.polishFailed,
              style: text == null
                  ? theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.disabledColor)
                  : theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                key: buttonKey,
                onPressed: onUse,
                child: Text(l10n.polishUseThis),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
