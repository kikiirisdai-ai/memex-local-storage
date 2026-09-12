import 'package:flutter/material.dart';
import 'package:memex/data/services/goal_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/goals/view_models/goals_list_viewmodel.dart';
import 'package:memex/ui/goals/widgets/goal_form_page.dart';
import 'package:memex/utils/user_storage.dart';

class GoalsListPage extends StatefulWidget {
  const GoalsListPage({super.key, required this.goalService});

  final GoalService goalService;

  @override
  State<GoalsListPage> createState() => _GoalsListPageState();
}

class _GoalsListPageState extends State<GoalsListPage> {
  late final GoalsListViewModel _vm =
      GoalsListViewModel(goalService: widget.goalService);

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onChange);
    _vm.loadGoals();
  }

  @override
  void dispose() {
    _vm.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmDelete(Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(UserStorage.l10n.goalDeleteConfirmTitle),
        content: Text(UserStorage.l10n.deleteConfirmMessage(goal.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(UserStorage.l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _vm.deleteGoal(goal.id);
    }
  }

  String _formatEpochSeconds(int epochSeconds) {
    final d = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _editDeadline(Goal goal) async {
    final initial = goal.deadline == null
        ? DateTime.now()
        : DateTime.fromMillisecondsSinceEpoch(goal.deadline! * 1000);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    await _vm.updateDeadline(goal.id, picked.millisecondsSinceEpoch ~/ 1000);
  }

  Future<void> _editCurrentValue(Goal goal) async {
    final controller =
        TextEditingController(text: goal.currentValue.toStringAsFixed(0));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UserStorage.l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(UserStorage.l10n.save),
          ),
        ],
      ),
    );
    if (result == null) return;
    final parsed = double.tryParse(result.trim());
    if (parsed == null || !parsed.isFinite || parsed < 0) return;
    await _vm.updateProgress(goal.id, parsed);
  }

  Widget _buildGoalCard(Goal goal) {
    final isCompleted = goal.status == 'completed';
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final isOverdue =
        !isCompleted && goal.deadline != null && goal.deadline! < nowSeconds;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadowCard,
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.iconBgLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  goal.goalType == 'quantitative'
                      ? Icons.trending_up_rounded
                      : (isCompleted
                          ? Icons.check_circle_rounded
                          : Icons.flag_outlined),
                  size: 18,
                  color: isCompleted
                      ? AppColors.success
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  goal.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isCompleted
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    decoration: isCompleted
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('delete_${goal.id}'),
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.textTertiary),
                onPressed: () => _confirmDelete(goal),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (goal.goalType == 'quantitative') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: goal.targetValue == null ||
                              goal.targetValue == 0
                          ? 0
                          : (goal.currentValue / goal.targetValue!)
                              .clamp(0, 1)
                              .toDouble(),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFF1F5F9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isCompleted ? AppColors.success : AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _editCurrentValue(goal),
                  child: Text(
                    '${goal.currentValue.toStringAsFixed(0)}/${goal.targetValue?.toStringAsFixed(0)}${goal.unit ?? ''}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (!isCompleted || goal.completedAt != null) ...[
            const SizedBox(height: 10),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (!isCompleted && goal.goalType == 'quantitative') ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StepperButton(
                      icon: Icons.remove,
                      onTap: () => _vm.incrementProgress(goal.id, -1),
                    ),
                    const SizedBox(width: 6),
                    _StepperButton(
                      icon: Icons.add,
                      onTap: () => _vm.incrementProgress(goal.id, 1),
                    ),
                  ],
                ),
              ],
              if (!isCompleted && goal.deadline != null)
                GestureDetector(
                  onTap: () => _editDeadline(goal),
                  child: _DateBadge(
                    text: _formatEpochSeconds(goal.deadline!),
                    isOverdue: isOverdue,
                  ),
                ),
              if (!isCompleted && goal.deadline == null)
                GestureDetector(
                  onTap: () => _editDeadline(goal),
                  child: _DateBadge(
                    text: UserStorage.l10n.goalFormNoDeadline,
                    isOverdue: false,
                  ),
                ),
              if (isCompleted && goal.completedAt != null)
                _DateBadge(
                  text: _formatEpochSeconds(goal.completedAt!),
                  isOverdue: false,
                ),
              if (!isCompleted)
                TextButton(
                  onPressed: () => _vm.markCompleted(goal.id),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(UserStorage.l10n.goalMarkCompleted),
                ),
              if (isCompleted)
                TextButton(
                  onPressed: () => _vm.reopen(goal.id),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(UserStorage.l10n.goalReopen),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(UserStorage.l10n.goalsPageTitle,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => GoalFormPage(goalService: widget.goalService),
                ),
              );
              if (created == true) _vm.loadGoals();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_vm.activeGoals.isNotEmpty) ...[
            _buildSectionHeader(UserStorage.l10n.goalsTabActive),
            ..._vm.activeGoals.map(_buildGoalCard),
          ],
          if (_vm.completedGoals.isNotEmpty) ...[
            _buildSectionHeader(UserStorage.l10n.goalsTabCompleted),
            ..._vm.completedGoals.map(_buildGoalCard),
          ],
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.iconBgLight,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 16, color: AppColors.primary),
        ),
      ),
    );
  }
}

/// A single-line, non-wrapping date pill. Previously this was a bare
/// [Text] sharing a [Row] with action buttons — on narrower cards the date
/// string had no width limit and would wrap onto a second line instead of
/// truncating, misaligning the row. Wrapping the caller's widget in
/// [Flexible] plus fixing `maxLines`/`overflow` here keeps it on one line.
class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.text, required this.isOverdue});

  final String text;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOverdue
            ? AppColors.danger.withValues(alpha: 0.1)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: isOverdue ? Colors.red : AppColors.textSecondary,
        ),
      ),
    );
  }
}
