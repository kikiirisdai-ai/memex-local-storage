import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/tasks/view_models/task_list_viewmodel.dart';
import 'package:memex/ui/tasks/widgets/task_list_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimelineCardModel _taskCard({
  required String id,
  required String title,
  bool isCompleted = false,
}) {
  return TimelineCardModel(
    id: id,
    timestamp: DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    uiConfigs: [
      UiConfig(templateId: 'task', data: {
        'title': title,
        'is_completed': isCompleted,
      }),
    ],
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.setLocale(const Locale('en'));
  });

  testWidgets('lists active and completed to-dos in separate sections',
      (tester) async {
    final vm = TaskListViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async => Ok([
        _taskCard(id: 'a', title: 'Buy milk'),
        _taskCard(id: 'b', title: 'Done thing', isCompleted: true),
      ]),
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const TaskListScreen()),
    ));

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('Done thing'), findsOneWidget);
  });

  testWidgets('tapping the toggle marks a task complete', (tester) async {
    var toggledId = '';
    final vm = TaskListViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async =>
          Ok([_taskCard(id: 'a', title: 'Buy milk')]),
      updateUiConfig: (cardId, configIndex, data) async {
        toggledId = cardId;
        return true;
      },
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const TaskListScreen()),
    ));

    await tester.tap(find.byKey(const ValueKey('task_toggle_a')));
    await tester.pumpAndSettle();

    expect(toggledId, 'a');
  });

  testWidgets('shows the empty state when there are no to-dos',
      (tester) async {
    final vm = TaskListViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async => const Ok([]),
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const TaskListScreen()),
    ));

    expect(find.text('No to-dos yet'), findsOneWidget);
  });

  testWidgets(
      'manually adding a to-do calls addManualEntry and closes the sheet',
      (tester) async {
    String? capturedTitle;
    final vm = TaskListViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async => const Ok([]),
      createEntry: ({required title, dueDate, priority}) async {
        capturedTitle = title;
        return const Ok('new-id');
      },
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const TaskListScreen()),
    ));

    await tester.tap(find.byKey(const ValueKey('task_list_add_entry_button')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Pay rent');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(capturedTitle, 'Pay rent');
    expect(find.text('Add to-do manually'), findsNothing);
  });

  testWidgets('submitting an empty title shows a validation error',
      (tester) async {
    var created = false;
    final vm = TaskListViewModel.forTest(
      fetchTimelineCards: ({page = 1, limit = 20}) async => const Ok([]),
      createEntry: ({required title, dueDate, priority}) async {
        created = true;
        return const Ok('new-id');
      },
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const TaskListScreen()),
    ));

    await tester.tap(find.byKey(const ValueKey('task_list_add_entry_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(created, isFalse);
    expect(find.text('Please enter a title'), findsOneWidget);
  });
}
