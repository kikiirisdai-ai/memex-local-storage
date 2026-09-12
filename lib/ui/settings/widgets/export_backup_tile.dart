import 'package:flutter/material.dart';

import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/ui/settings/view_models/export_backup_viewmodel.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// Prominent top-level "Export Backup" settings tile: mirrors the existing
/// tile styling but one-tap generates a `.memex` backup and opens the OS
/// share sheet via [ExportBackupViewModel.export]. Extracted as a standalone
/// widget (rather than inlined in `SettingsPage`) so it can be widget-tested
/// with an injected [ExportBackupViewModel.forTesting].
class ExportBackupTile extends StatefulWidget {
  const ExportBackupTile({super.key, required this.viewModel});

  final ExportBackupViewModel viewModel;

  @override
  State<ExportBackupTile> createState() => _ExportBackupTileState();
}

class _ExportBackupTileState extends State<ExportBackupTile> {
  String? _shownError;

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    final error = widget.viewModel.error;
    if (error != null && error != _shownError && mounted) {
      _shownError = error;
      ToastHelper.showError(context, error);
    }
    setState(() {});
  }

  String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    final vm = widget.viewModel;
    final lastExportAt = vm.lastExportAt;
    final hasExported = lastExportAt != null;
    final subtitleText = hasExported
        ? l10n.exportBackupLastExported(_formatDate(lastExportAt))
        : l10n.exportBackupNeverExported;

    return Material(
      key: const ValueKey('export_backup_tile'),
      color: Colors.transparent,
      child: InkWell(
        onTap: vm.generating ? null : () => vm.export(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.textSecondary.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.ios_share,
                color: AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.exportBackupTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      key: const ValueKey('export_backup_subtitle'),
                      style: TextStyle(
                        fontSize: 13,
                        color: hasExported ? Colors.grey[500] : Colors.red,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (vm.generating)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
            ],
          ),
        ),
      ),
    );
  }
}
