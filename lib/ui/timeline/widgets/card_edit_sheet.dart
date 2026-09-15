import 'package:flutter/material.dart';
import 'package:memex/domain/models/card_body_text_fields.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/ui/core/input_sheet_metrics.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

/// One editable prose field inside a card's `ui_configs` entry.
class CardBodyField {
  const CardBodyField({
    required this.configIndex,
    required this.dataKey,
    required this.text,
  });

  final int configIndex;
  final String dataKey;
  final String text;
}

/// What the user changed. Only fields that actually differ are included, so
/// the caller writes the minimum number of card updates.
class CardTextEdits {
  const CardTextEdits({required this.title, required this.bodies});

  /// New title, or null when the title was left alone.
  final String? title;

  /// New body text keyed by `ui_configs` index, for changed bodies only.
  final Map<int, String> bodies;

  bool get isEmpty => title == null && bodies.isEmpty;
}

/// Lists the editable prose fields of [uiConfigs], in display order.
List<CardBodyField> editableBodyFields(List<UiConfig> uiConfigs) {
  final fields = <CardBodyField>[];
  for (var i = 0; i < uiConfigs.length; i++) {
    final key = cardBodyTextFieldFor(uiConfigs[i].templateId);
    if (key == null) continue;
    fields.add(CardBodyField(
      configIndex: i,
      dataKey: key,
      text: uiConfigs[i].data[key]?.toString() ?? '',
    ));
  }
  return fields;
}

/// Bottom sheet for correcting the title and body wording of an AI-generated
/// card. Pops a [CardTextEdits] on save, or null when dismissed.
class CardEditSheet extends StatefulWidget {
  const CardEditSheet({
    super.key,
    required this.initialTitle,
    required this.bodyFields,
  });

  final String initialTitle;
  final List<CardBodyField> bodyFields;

  @override
  State<CardEditSheet> createState() => _CardEditSheetState();
}

class _CardEditSheetState extends State<CardEditSheet> {
  late final TextEditingController _titleController;
  late final List<TextEditingController> _bodyControllers;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _bodyControllers = widget.bodyFields
        .map((field) => TextEditingController(text: field.text))
        .toList();
  }

  @override
  void dispose() {
    _titleController.dispose();
    for (final controller in _bodyControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    final bodies = <int, String>{};
    for (var i = 0; i < widget.bodyFields.length; i++) {
      final field = widget.bodyFields[i];
      final text = _bodyControllers[i].text;
      if (text != field.text) bodies[field.configIndex] = text;
    }

    Navigator.of(context).pop(
      CardTextEdits(
        title: title == widget.initialTitle.trim() ? null : title,
        bodies: bodies,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: inputSheetConstraints(
        context,
        fraction: kTallInputSheetMaxHeightFraction,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        UserStorage.l10n.editCard,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(UserStorage.l10n.cancel),
                    ),
                    TextButton(
                      key: const ValueKey('card_edit_save'),
                      onPressed: _save,
                      child: Text(UserStorage.l10n.save),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _label(UserStorage.l10n.editCardTitleLabel),
                        TextField(
                          key: const ValueKey('card_edit_title'),
                          controller: _titleController,
                          decoration: InputDecoration(
                            hintText: UserStorage.l10n.editCardTitleHint,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        for (var i = 0; i < widget.bodyFields.length; i++) ...[
                          const SizedBox(height: 16),
                          _label(
                            widget.bodyFields.length == 1
                                ? UserStorage.l10n.editCardBodyLabel
                                : '${UserStorage.l10n.editCardBodyLabel} '
                                    '${i + 1}',
                          ),
                          TextField(
                            key: ValueKey('card_edit_body_$i'),
                            controller: _bodyControllers[i],
                            maxLines: null,
                            minLines: 3,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                      ],
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

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
      ),
    );
  }
}
