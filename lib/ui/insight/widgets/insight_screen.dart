import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:memex/routing/routes.dart';
import 'package:memex/ui/insight/view_models/insight_viewmodel.dart';
import 'package:memex/ui/insight/widgets/user_stats_page.dart';
import 'package:memex/ui/media_library/widgets/media_library_screen.dart';
import 'package:memex/ui/tasks/widgets/task_list_screen.dart';
import 'package:memex/utils/user_storage.dart';

/// Insight screen - global knowledge analytics. Receives [viewModel] from
/// parent (Compass-style).
///
/// The AI "Knowledge Insight" section has been removed: on-device insight
/// generation never reliably completes (times out / returns empty /
/// hallucinates success with zero real tool calls). This page now always
/// shows the Activity Stats section (which includes the deterministic mood
/// curve). See [InsightViewModel.loadData], which no longer fetches AI
/// insights.
class InsightScreen extends StatefulWidget {
  final InsightViewModel viewModel;
  final bool isEmbedded;

  const InsightScreen({
    super.key,
    required this.viewModel,
    this.isEmbedded = false,
  });

  @override
  State<InsightScreen> createState() => _InsightScreenState();
}

class _InsightScreenState extends State<InsightScreen> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final content = RefreshIndicator(
          onRefresh: () => vm.loadStats(),
          child: UserStatsPage(
            snapshot: vm.statsSnapshot,
            isLoading: vm.isStatsLoading,
            errorMessage: vm.statsErrorMessage,
            selectedDays: vm.statsRange.dayCount,
            selectedMetric: vm.selectedStatsMetric,
            onMetricChanged: vm.setStatsMetric,
            onPresetSelected: (days) => vm.setStatsPresetDays(days),
            onReload: () => vm.loadStats(),
            header: const Column(
              children: [
                _InsightEntryTile(
                  key: ValueKey('insight_entry_goals'),
                  icon: Icons.flag_outlined,
                  titleBuilder: _goalsTitle,
                  route: AppRoutes.goals,
                ),
                SizedBox(height: 10),
                _InsightEntryTile(
                  key: ValueKey('insight_entry_tasks'),
                  icon: Icons.check_circle_outline,
                  titleBuilder: _taskListTitle,
                  onTap: openTaskList,
                ),
                SizedBox(height: 10),
                _InsightEntryTile(
                  key: ValueKey('insight_entry_media_library'),
                  icon: Icons.menu_book_outlined,
                  titleBuilder: _mediaLibraryTitle,
                  onTap: openMediaLibrary,
                ),
                SizedBox(height: 10),
                _InsightEntryTile(
                  key: ValueKey('insight_entry_memory'),
                  icon: Icons.memory,
                  titleBuilder: _memoryTitle,
                  route: AppRoutes.memory,
                ),
              ],
            ),
          ),
        );

        // Wrap in Scaffold when not embedded
        return widget.isEmbedded
            ? content
            : Scaffold(
                backgroundColor: const Color(0xFFF7F8FA),
                body: SafeArea(
                  child: content,
                ),
              );
      },
    );
  }
}

String _goalsTitle() => UserStorage.l10n.goalsPageTitle;
String _taskListTitle() => UserStorage.l10n.taskListTitle;
String _mediaLibraryTitle() => UserStorage.l10n.mediaLibraryTitle;
String _memoryTitle() => UserStorage.l10n.memoryTitle;

/// A single tappable row entry shown above the Activity Stats sections,
/// linking out to a related full-screen feature (goals, media library).
class _InsightEntryTile extends StatelessWidget {
  const _InsightEntryTile({
    super.key,
    required this.icon,
    required this.titleBuilder,
    this.route,
    this.onTap,
  }) : assert(route != null || onTap != null);

  final IconData icon;
  final String Function() titleBuilder;

  /// A GoRouter route to push via [GoRouter.push]. Mutually exclusive
  /// with [onTap].
  final String? route;

  /// A direct navigation callback (e.g. pushing a [MaterialPageRoute]).
  /// Mutually exclusive with [route].
  final void Function(BuildContext context)? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (onTap != null) {
            onTap!(context);
          } else {
            context.push(route!);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF6366F1), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titleBuilder(),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF94A3B8),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
