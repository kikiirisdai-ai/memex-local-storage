import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/data/services/archive_purge_service.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/ui/archive/view_models/archive_list_viewmodel.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Pushes the Archive page with its own page-scoped ViewModel.
void openArchiveList(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => ArchiveListViewModel(router: MemexRouter())..load(),
        child: const ArchiveListScreen(),
      ),
    ),
  );
}

/// Lists every archived card, with multi-select batch restore/delete.
class ArchiveListScreen extends StatelessWidget {
  const ArchiveListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final vm = context.watch<ArchiveListViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.archiveListTitle,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          if (vm.entries.isNotEmpty)
            TextButton(
              onPressed: vm.toggleSelectAll,
              child: Text(
                vm.isAllSelected ? l10n.archiveDeselectAll : l10n.archiveSelectAll,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.iconBgLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.archiveRetentionNotice(archiveRetention.inDays),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: _buildBody(context, vm)),
        ],
      ),
      bottomNavigationBar: vm.hasSelection ? _buildActionBar(context, vm) : null,
    );
  }

  Widget _buildBody(BuildContext context, ArchiveListViewModel vm) {
    final l10n = UserStorage.l10n;
    if (vm.isLoading && vm.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.errorMessage != null && vm.entries.isEmpty) {
      return Center(
        child: Text(vm.errorMessage!,
            style: const TextStyle(color: AppColors.textTertiary)),
      );
    }
    if (vm.entries.isEmpty) {
      return Center(
        child: Text(
          l10n.archiveListEmpty,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      key: const ValueKey('archive_list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: vm.entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _ArchiveTile(entry: vm.entries[index], viewModel: vm),
    );
  }

  Widget _buildActionBar(BuildContext context, ArchiveListViewModel vm) {
    final l10n = UserStorage.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: vm.isBusy ? null : vm.restoreSelected,
                icon: const Icon(Icons.unarchive_outlined),
                label: Text(l10n.archiveRestoreToTimeline),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: vm.isBusy ? null : vm.deleteSelected,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.danger,
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.delete),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({required this.entry, required this.viewModel});

  final TimelineCardModel entry;
  final ArchiveListViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final selected = viewModel.selectedIds.contains(entry.id);
    final archivedAt = entry.archivedAt;
    final archivedLabel = archivedAt == null
        ? ''
        : _formatEpochSeconds(archivedAt);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: viewModel.hasSelection
            ? () => viewModel.toggleSelection(entry.id)
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        TimelineCardDetailScreen(cardId: entry.id),
                  ),
                ),
        onLongPress: () => viewModel.toggleSelection(entry.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Checkbox(
                value: selected,
                onChanged: (_) => viewModel.toggleSelection(entry.id),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (entry.title?.trim().isNotEmpty ?? false)
                          ? entry.title!
                          : UserStorage.l10n.untitledCard,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (archivedLabel.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        UserStorage.l10n.archivedAtLabel(archivedLabel),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
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

String _formatEpochSeconds(int epochSeconds) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
