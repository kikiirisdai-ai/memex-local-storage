import 'package:flutter/material.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/goals/view_models/goal_form_viewmodel.dart';
import 'package:memex/utils/user_storage.dart';

class GoalFormPage extends StatefulWidget {
  const GoalFormPage({super.key, required this.goalService});

  final GoalService goalService;

  @override
  State<GoalFormPage> createState() => _GoalFormPageState();
}

class _GoalFormPageState extends State<GoalFormPage> {
  late final GoalFormViewModel _vm =
      GoalFormViewModel(goalService: widget.goalService);
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChange);
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _deadline = picked;
      _vm.deadline = picked;
    });
  }

  Future<void> _save() async {
    final ok = await _vm.save();
    if (ok && mounted) {
      Navigator.pop(context, true);
    }
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.goalFormPageTitle,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: _fieldDecoration(l10n.goalFormTitleLabel),
              onChanged: (v) => _vm.title = v,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _TypeChip(
                  label: l10n.goalFormTypeQuantitative,
                  selected: _vm.goalType == 'quantitative',
                  onTap: () => setState(() => _vm.goalType = 'quantitative'),
                ),
                const SizedBox(width: 8),
                _TypeChip(
                  label: l10n.goalFormTypeBinary,
                  selected: _vm.goalType == 'binary',
                  onTap: () => setState(() => _vm.goalType = 'binary'),
                ),
              ],
            ),
            if (_vm.goalType == 'quantitative') ...[
              const SizedBox(height: 16),
              TextField(
                decoration: _fieldDecoration(l10n.goalFormTargetValueLabel),
                keyboardType: TextInputType.number,
                onChanged: (v) => _vm.targetValueText = v,
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: _fieldDecoration(l10n.goalFormUnitLabel),
                onChanged: (v) => _vm.unit = v,
              ),
            ],
            const SizedBox(height: 16),
            _DeadlineField(
              deadline: _deadline,
              label: l10n.goalFormNoDeadline,
              actionLabel: l10n.goalFormDeadlineLabel,
              onTap: _pickDeadline,
            ),
            if (_vm.error != null) ...[
              const SizedBox(height: 8),
              Text(_vm.error!,
                  style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _vm.isSaving ? null : _save,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.primary,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? AppColors.primary : const Color(0xFFE5E7EB),
        ),
      ),
    );
  }
}

/// Tappable date field: icon + a single-line, ellipsized date label, with
/// a compact trailing action instead of a free-floating button competing
/// with the date text for width — that's what was making the date wrap
/// onto a second line on narrower screens.
class _DeadlineField extends StatelessWidget {
  const _DeadlineField({
    required this.deadline,
    required this.label,
    required this.actionLabel,
    required this.onTap,
  });

  final DateTime? deadline;
  final String label;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = deadline == null
        ? label
        : '${deadline!.year}-${deadline!.month.toString().padLeft(2, '0')}-'
            '${deadline!.day.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.calendar_month_outlined,
                  size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 2,
                child: Text(
                  actionLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
