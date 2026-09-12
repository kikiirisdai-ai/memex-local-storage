import 'package:flutter/material.dart';

import 'package:memex/ui/settings/view_models/export_backup_viewmodel.dart';
import 'package:memex/utils/backup_safety.dart';
import 'package:memex/utils/toast_helper.dart';
import 'package:memex/utils/user_storage.dart';

/// A dismissible home-timeline banner that nudges the user to perform a
/// manual export when it has been more than [shouldNudgeExport]'s threshold
/// (default 14 days) since the last export — or the user has never
/// exported. On this build, only an external export (share sheet / saved
/// file) survives an app uninstall, so this banner is the primary defense
/// against silent data loss.
///
/// Self-hides ([SizedBox.shrink]) whenever a nudge isn't warranted, so it's
/// safe to always mount at the top of the timeline content.
class ExportReminderBanner extends StatefulWidget {
  const ExportReminderBanner({super.key})
      : _lastExportProvider = null,
        _snoozeProvider = null,
        _onSnooze = null,
        _onExport = null,
        _now = null,
        _viewModel = null;

  /// Test-only constructor. All storage/export interactions are injectable
  /// so tests never touch `UserStorage`/`SharedPreferences` or trigger a
  /// real export.
  ///
  /// Pass [viewModel] (instead of [onExport]) to exercise the default
  /// production export path — i.e. `ExportBackupViewModel.export` — with an
  /// injected `ExportBackupViewModel.forTesting` so error surfacing can be
  /// asserted without touching real OS/service dependencies.
  @visibleForTesting
  ExportReminderBanner.forTesting({
    super.key,
    required Future<DateTime?> Function() lastExportProvider,
    required Future<DateTime?> Function() snoozeProvider,
    required Future<void> Function(DateTime) onSnooze,
    Future<void> Function(BuildContext)? onExport,
    ExportBackupViewModel? viewModel,
    DateTime Function()? now,
  })  : _lastExportProvider = lastExportProvider,
        _snoozeProvider = snoozeProvider,
        _onSnooze = onSnooze,
        _onExport = onExport,
        _viewModel = viewModel,
        _now = now ?? DateTime.now;

  final Future<DateTime?> Function()? _lastExportProvider;
  final Future<DateTime?> Function()? _snoozeProvider;
  final Future<void> Function(DateTime)? _onSnooze;
  final Future<void> Function(BuildContext)? _onExport;
  final ExportBackupViewModel? _viewModel;
  final DateTime Function()? _now;

  @override
  State<ExportReminderBanner> createState() => _ExportReminderBannerState();
}

class _ExportReminderBannerState extends State<ExportReminderBanner> {
  bool _visible = false;
  bool _loaded = false;
  bool _exporting = false;
  ExportBackupViewModel? _viewModel;
  bool _ownsViewModel = false;
  String? _shownError;

  DateTime Function() get _now => widget._now ?? DateTime.now;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget._viewModel != null) {
      _viewModel = widget._viewModel;
      _viewModel!.addListener(_onViewModelChanged);
    }
  }

  @override
  void dispose() {
    _viewModel?.removeListener(_onViewModelChanged);
    if (_ownsViewModel) {
      _viewModel?.dispose();
    }
    super.dispose();
  }

  void _onViewModelChanged() {
    final error = _viewModel?.error;
    if (error != null && error != _shownError && mounted) {
      _shownError = error;
      ToastHelper.showError(context, error);
    }
  }

  Future<DateTime?> _loadLastExport() async {
    if (widget._lastExportProvider != null) {
      return widget._lastExportProvider!();
    }
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    return UserStorage.getLastManualExportAt(userId);
  }

  Future<DateTime?> _loadSnooze() async {
    if (widget._snoozeProvider != null) {
      return widget._snoozeProvider!();
    }
    final userId = await UserStorage.getUserId();
    if (userId == null) return null;
    return UserStorage.getExportNudgeSnoozeUntil(userId);
  }

  Future<void> _load() async {
    final lastExport = await _loadLastExport();
    final snoozeUntil = await _loadSnooze();
    final nudge = shouldNudgeExport(
      lastExport: lastExport,
      snoozeUntil: snoozeUntil,
      now: _now(),
    );
    if (!mounted) return;
    setState(() {
      _visible = nudge;
      _loaded = true;
    });
  }

  Future<void> _handleSnooze() async {
    final until = _now().add(const Duration(days: 3));
    if (widget._onSnooze != null) {
      await widget._onSnooze!(until);
    } else {
      final userId = await UserStorage.getUserId();
      if (userId != null) {
        await UserStorage.setExportNudgeSnoozeUntil(userId, until);
      }
    }
    if (!mounted) return;
    setState(() => _visible = false);
  }

  Future<void> _handleExport(BuildContext context) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      if (widget._onExport != null) {
        await widget._onExport!(context);
      } else {
        if (_viewModel == null) {
          _viewModel = ExportBackupViewModel();
          _ownsViewModel = true;
          _viewModel!.addListener(_onViewModelChanged);
        }
        await _viewModel!.export(context);
      }
      await _load();
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !_visible) {
      return const SizedBox.shrink();
    }

    return Padding(
      key: const ValueKey('export_reminder_banner'),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 20,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      UserStorage.l10n.exportReminderTitle,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      UserStorage.l10n.exportReminderBody,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFB45309),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          height: 32,
                          child: ElevatedButton(
                            key: const ValueKey('export_reminder_export_btn'),
                            onPressed:
                                _exporting ? null : () => _handleExport(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB45309),
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              _exporting
                                  ? UserStorage.l10n.exportReminderExporting
                                  : UserStorage.l10n.exportReminderExportButton,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          key: const ValueKey('export_reminder_dismiss_btn'),
                          onPressed: _handleSnooze,
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFB45309),
                          ),
                          child: Text(UserStorage.l10n.exportReminderSnoozeButton),
                        ),
                      ],
                    ),
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
