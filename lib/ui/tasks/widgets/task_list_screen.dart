import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/task_entry.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/tasks/view_models/task_list_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Pushes the Task List page with its own page-scoped ViewModel.
void openTaskList(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => TaskListViewModel(router: MemexRouter())..load(),
        child: const TaskListScreen(),
      ),
    ),
  );
}

/// Aggregates every card carrying a `task` ui_config (待办) into one
/// browsable list, split into active/completed.
class TaskListScreen extends StatelessWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final vm = context.watch<TaskListViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.taskListTitle,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            key: const ValueKey('task_list_add_entry_button'),
            icon: const Icon(Icons.add),
            tooltip: l10n.taskListAddEntry,
            onPressed: () => _showAddEntrySheet(context, vm),
          ),
        ],
      ),
      body: _buildBody(context, vm),
    );
  }

  Widget _buildBody(BuildContext context, TaskListViewModel vm) {
    final l10n = UserStorage.l10n;
    if (vm.isLoading && vm.activeEntries.isEmpty && vm.completedEntries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.errorMessage != null) {
      return Center(
        child: Text(vm.errorMessage!,
            style: const TextStyle(color: AppColors.textTertiary)),
      );
    }

    final active = vm.activeEntries;
    final completed = vm.completedEntries;
    if (active.isEmpty && completed.isEmpty) {
      return Center(
        child: Text(
          l10n.taskListEmpty,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (active.isNotEmpty) ...[
          _buildSectionHeader(l10n.goalsTabActive),
          ...active.map((e) => _TaskTile(entry: e, viewModel: vm)),
        ],
        if (completed.isNotEmpty) ...[
          _buildSectionHeader(l10n.goalsTabCompleted),
          ...completed.map((e) => _TaskTile(entry: e, viewModel: vm)),
        ],
      ],
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
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.entry, required this.viewModel});

  final TaskEntry entry;
  final TaskListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOverdue = !entry.isCompleted &&
        entry.dueDate != null &&
        entry.dueDate!.isBefore(now);

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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TimelineCardDetailScreen(cardId: entry.cardId),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                key: ValueKey('task_toggle_${entry.cardId}'),
                onTap: () => viewModel.toggleCompleted(entry),
                child: Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                    color: entry.isCompleted
                        ? AppColors.primary
                        : Colors.transparent,
                  ),
                  child: entry.isCompleted
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: entry.isCompleted
                                  ? AppColors.textTertiary
                                  : AppColors.textPrimary,
                              decoration: entry.isCompleted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                        ),
                        if (entry.priority == 'high')
                          const Icon(Icons.priority_high,
                              size: 16, color: AppColors.danger),
                      ],
                    ),
                    if (entry.dueDate != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${entry.dueDate!.year}-${entry.dueDate!.month.toString().padLeft(2, '0')}-'
                        '${entry.dueDate!.day.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isOverdue
                              ? Colors.red
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAddEntrySheet(BuildContext context, TaskListViewModel vm) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddTaskEntrySheet(viewModel: vm),
  );
}

class _AddTaskEntrySheet extends StatefulWidget {
  const _AddTaskEntrySheet({required this.viewModel});

  final TaskListViewModel viewModel;

  @override
  State<_AddTaskEntrySheet> createState() => _AddTaskEntrySheetState();
}

class _AddTaskEntrySheetState extends State<_AddTaskEntrySheet> {
  final _titleController = TextEditingController();
  DateTime? _dueDate;
  bool _highPriority = false;
  String? _titleError;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  Future<void> _submit() async {
    final l10n = UserStorage.l10n;
    final title = _titleController.text;
    if (title.trim().isEmpty) {
      setState(() => _titleError = l10n.taskEntryTitleRequired);
      return;
    }

    final ok = await widget.viewModel.addManualEntry(
      title: title,
      dueDate: _dueDate,
      priority: _highPriority ? 'high' : null,
    );

    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final dueDateLabel = _dueDate == null
        ? l10n.taskEntryDueDateLabel
        : '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-'
            '${_dueDate!.day.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.taskListAddEntry,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: l10n.taskEntryTitleLabel,
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _pickDueDate,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(dueDateLabel,
                            style: const TextStyle(fontSize: 15)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Checkbox(
                  value: _highPriority,
                  onChanged: (v) => setState(() => _highPriority = v ?? false),
                ),
                Text(l10n.taskEntryPriorityLabel),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: widget.viewModel.isSaving ? null : _submit,
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
