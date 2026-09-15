import 'package:flutter/material.dart';
import 'package:memex/ui/core/input_sheet_metrics.dart';
import 'package:memex/utils/user_storage.dart';

/// Shows a bottom sheet letting the user tweak polished text before
/// confirming it. Mirrors the `_editMood` bottom-sheet-returns-value pattern
/// (`showModalBottomSheet<T>` resolved via `Navigator.pop`).
///
/// Returns the edited (trimmed) text when the user taps Confirm, or `null`
/// if they tap Cancel or dismiss the sheet.
Future<String?> showPolishEditConfirmSheet(
  BuildContext context, {
  required String initialText,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _PolishEditConfirmSheet(initialText: initialText),
  );
}

class _PolishEditConfirmSheet extends StatefulWidget {
  const _PolishEditConfirmSheet({required this.initialText});

  final String initialText;

  @override
  State<_PolishEditConfirmSheet> createState() =>
      _PolishEditConfirmSheetState();
}

class _PolishEditConfirmSheetState extends State<_PolishEditConfirmSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return ConstrainedBox(
      constraints: inputSheetConstraints(context),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('polish_edit_field'),
                controller: _controller,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('polish_cancel_button'),
                      onPressed: () => Navigator.pop(context, null),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      key: const ValueKey('polish_confirm_button'),
                      onPressed: () =>
                          Navigator.pop(context, _controller.text.trim()),
                      child: Text(l10n.confirm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
