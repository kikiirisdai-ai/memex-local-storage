import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:memex/data/repositories/memex_router.dart';
import 'package:memex/domain/models/media_library_entry.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/media_library/view_models/media_library_viewmodel.dart';
import 'package:memex/ui/timeline/widgets/timeline_card_detail_screen.dart';
import 'package:memex/utils/user_storage.dart';

const Map<String, String> _typeIcons = {
  'book': '📖',
  'movie': '🎬',
  'tv': '📺',
  'music': '🎵',
  'podcast': '🎙️',
  'other': '🔖',
};

const Map<String, Color> _statusColors = {
  'want': AppColors.textTertiary,
  'doing': AppColors.primary,
  'done': AppColors.success,
};

String _typeLabel(String type) {
  final l10n = UserStorage.l10n;
  switch (type) {
    case 'book':
      return l10n.mediaTypeBook;
    case 'movie':
      return l10n.mediaTypeMovie;
    case 'tv':
      return l10n.mediaTypeTv;
    case 'music':
      return l10n.mediaTypeMusic;
    case 'podcast':
      return l10n.mediaTypePodcast;
    default:
      return l10n.mediaTypeOther;
  }
}

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

/// Pushes the Media Library page with its own page-scoped ViewModel.
void openMediaLibrary(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChangeNotifierProvider(
        create: (_) => MediaLibraryViewModel(router: MemexRouter())..load(),
        child: const MediaLibraryScreen(),
      ),
    ),
  );
}

/// Aggregates every card carrying a `media_card` ui_config (书影音) into one
/// browsable, filterable list.
class MediaLibraryScreen extends StatelessWidget {
  const MediaLibraryScreen({super.key});

  static const _typeOrder = ['book', 'movie', 'tv', 'music', 'podcast', 'other'];
  static const _statusOrder = ['want', 'doing', 'done'];

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final vm = context.watch<MediaLibraryViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.mediaLibraryTitle,
            style: const TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            key: const ValueKey('media_library_add_entry_button'),
            icon: const Icon(Icons.add),
            tooltip: l10n.mediaLibraryAddEntry,
            onPressed: () => _showAddEntrySheet(context, vm),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _FilterRow(
              key: const ValueKey('media_library_type_filters'),
              selected: vm.typeFilter,
              options: const ['all', ..._typeOrder],
              labelFor: (v) => v == 'all' ? l10n.all : _typeLabel(v),
              onSelected: vm.setTypeFilter,
              accentColor: AppColors.primary,
            ),
            const SizedBox(height: 8),
            _FilterRow(
              key: const ValueKey('media_library_status_filters'),
              selected: vm.statusFilter,
              options: const ['all', ..._statusOrder],
              labelFor: (v) => v == 'all' ? l10n.all : _statusLabel(v),
              onSelected: vm.setStatusFilter,
              accentColor: AppColors.success,
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildBody(context, vm)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, MediaLibraryViewModel vm) {
    if (vm.isLoading && vm.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (vm.errorMessage != null && vm.entries.isEmpty) {
      return Center(
        child: Text(
          vm.errorMessage!,
          style: const TextStyle(color: AppColors.textTertiary),
        ),
      );
    }

    final entries = vm.filteredEntries;
    if (entries.isEmpty) {
      return Center(
        child: Text(
          UserStorage.l10n.mediaLibraryEmpty,
          style: const TextStyle(color: AppColors.textTertiary, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      key: const ValueKey('media_library_list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _MediaLibraryTile(entry: entries[index]),
    );
  }
}

void _showAddEntrySheet(BuildContext context, MediaLibraryViewModel vm) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AddMediaEntrySheet(viewModel: vm),
  );
}

class _AddMediaEntrySheet extends StatefulWidget {
  const _AddMediaEntrySheet({required this.viewModel});

  final MediaLibraryViewModel viewModel;

  @override
  State<_AddMediaEntrySheet> createState() => _AddMediaEntrySheetState();
}

class _AddMediaEntrySheetState extends State<_AddMediaEntrySheet> {
  final _titleController = TextEditingController();
  final _ratingController = TextEditingController();
  final _commentController = TextEditingController();
  String _mediaType = 'book';
  String? _mediaStatus;
  String? _titleError;

  @override
  void dispose() {
    _titleController.dispose();
    _ratingController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = UserStorage.l10n;
    final title = _titleController.text;
    if (title.trim().isEmpty) {
      setState(() => _titleError = l10n.mediaLibraryEntryTitleRequired);
      return;
    }

    final ratingText = _ratingController.text.trim();
    final rating = ratingText.isEmpty ? null : int.tryParse(ratingText);
    final clampedRating = rating?.clamp(1, 10).toInt();

    final ok = await widget.viewModel.addManualEntry(
      title: title,
      mediaType: _mediaType,
      mediaStatus: _mediaStatus,
      rating: clampedRating,
      comment: _commentController.text,
    );

    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
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
              l10n.mediaLibraryAddEntry,
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
                labelText: l10n.mediaLibraryEntryTitleLabel,
                errorText: _titleError,
              ),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MediaLibraryScreen._typeOrder.map((type) {
                final selected = type == _mediaType;
                return ChoiceChip(
                  label: Text(_typeLabel(type)),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _mediaType = type),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MediaLibraryScreen._statusOrder.map((status) {
                final selected = status == _mediaStatus;
                return ChoiceChip(
                  label: Text(_statusLabel(status)),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => setState(
                      () => _mediaStatus = selected ? null : status),
                  selectedColor: AppColors.success,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : AppColors.textSecondary,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ratingController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.mediaLibraryEntryRatingLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _commentController,
              decoration: InputDecoration(
                hintText: l10n.mediaCommentHint,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    super.key,
    required this.selected,
    required this.options,
    required this.labelFor,
    required this.onSelected,
    required this.accentColor,
  });

  final String selected;
  final List<String> options;
  final String Function(String) labelFor;
  final ValueChanged<String> onSelected;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;
          return Material(
            color: isSelected ? accentColor : Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelected(option),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? accentColor : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Text(
                  labelFor(option),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MediaLibraryTile extends StatelessWidget {
  const _MediaLibraryTile({required this.entry});

  final MediaLibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final icon = _typeIcons[entry.mediaType] ?? _typeIcons['other']!;
    final statusColor =
        _statusColors[entry.mediaStatus] ?? AppColors.textTertiary;

    return Container(
      padding: const EdgeInsets.all(14),
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
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.iconBgLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (entry.mediaStatus != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _statusLabel(entry.mediaStatus!),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ),
                        if (entry.rating != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  size: 14, color: AppColors.warning),
                              const SizedBox(width: 2),
                              Text(
                                '${entry.rating}/10',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    if (entry.comment != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        entry.comment!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
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
