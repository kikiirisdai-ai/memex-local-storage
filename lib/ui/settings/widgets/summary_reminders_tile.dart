import 'package:flutter/material.dart';
import 'package:memex/data/services/summary_notification_service.dart';
import 'package:memex/ui/core/themes/app_colors.dart';
import 'package:memex/utils/user_storage.dart';

/// Settings toggle for the daily 21:00 "write/view a summary" reminder.
///
/// Reads/writes via [readEnabled]/[writeEnabled], which default to
/// [SummaryNotificationService.instance] in production. Tests inject fakes
/// so the widget can be verified in isolation without touching the real
/// notifications plugin.
class SummaryRemindersTile extends StatefulWidget {
  SummaryRemindersTile({
    super.key,
    Future<bool> Function()? readEnabled,
    Future<void> Function(bool)? writeEnabled,
  })  : readEnabled = readEnabled ?? SummaryNotificationService.instance.isEnabled,
        writeEnabled = writeEnabled ?? SummaryNotificationService.instance.setEnabled;

  final Future<bool> Function() readEnabled;
  final Future<void> Function(bool) writeEnabled;

  @override
  State<SummaryRemindersTile> createState() => _SummaryRemindersTileState();
}

class _SummaryRemindersTileState extends State<SummaryRemindersTile> {
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await widget.readEnabled();
    if (mounted) {
      setState(() => _enabled = enabled);
    }
  }

  Future<void> _updateEnabled(bool value) async {
    await widget.writeEnabled(value);
    if (mounted) {
      setState(() => _enabled = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: const ValueKey('summary_reminders_toggle'),
      contentPadding: EdgeInsets.zero,
      secondary: const Icon(
        Icons.notifications_outlined,
        color: AppColors.primary,
        size: 22,
      ),
      title: Text(
        UserStorage.l10n.summaryRemindersTitle,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          UserStorage.l10n.summaryRemindersSubtitle,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
            height: 1.4,
          ),
        ),
      ),
      value: _enabled,
      onChanged: _updateEnabled,
    );
  }
}
