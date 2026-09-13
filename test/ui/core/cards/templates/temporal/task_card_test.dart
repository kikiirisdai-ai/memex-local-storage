import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:memex/ui/core/cards/templates/temporal/task_card.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Builds a fresh Map literal each call — mirrors NativeCardFactory.build's
/// `mergedData`, which is a new object every rebuild even when its content
/// hasn't changed. A widget-identity check on `data` (rather than content)
/// would treat every such rebuild as "new data" and re-derive local state
/// from it, discarding a not-yet-persisted optimistic tap.
Map<String, dynamic> _freshData({required bool isCompleted}) => {
      'title': 'Buy bananas',
      'is_completed': isCompleted,
    };

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({'language': 'en'});
    await initializeDateFormatting('en');
    await UserStorage.initL10n();
  });

  testWidgets(
      'a same-content rebuild before the write round-trips back does not '
      'revert an optimistic tap (regression: used to flicker back to '
      'unchecked until the real update arrived)', (tester) async {
    Widget host(bool persistedCompleted) => MaterialApp(
          home: Scaffold(
            body: TaskCard(
              cardId: 'task-1',
              configIndex: 0,
              data: _freshData(isCompleted: persistedCompleted),
              onUpdate: (_, __, ___) {},
            ),
          ),
        );

    await tester.pumpWidget(host(false));
    await tester.tap(find.byKey(const ValueKey('task_card_toggle_task-1')));
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);

    // Rebuild with a brand-new (but still un-persisted, still-false) data
    // map — simulates an unrelated parent rebuild racing the async write.
    await tester.pumpWidget(host(false));
    expect(find.byIcon(Icons.check), findsOneWidget);

    // The real update finally arrives, confirming the edit.
    await tester.pumpWidget(host(true));
    expect(find.byIcon(Icons.check), findsOneWidget);
  });


  testWidgets('parent completion updates every grouped subtask', (
    tester,
  ) async {
    final updates = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            cardId: 'task-1',
            configIndex: 0,
            data: const {
              'title': 'Visa checklist',
              'is_completed': false,
              'subtasks': [
                {'title': 'Collect documents', 'completed': false},
                {'title': 'Submit form', 'completed': false},
              ],
            },
            onUpdate: (_, __, data) => updates.add(data),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_card_toggle_task-1')));
    await tester.pump();

    expect(updates.last['is_completed'], isTrue);
    expect(
      (updates.last['subtasks'] as List).map(
        (subtask) => (subtask as Map)['completed'],
      ),
      [true, true],
    );
  });

  testWidgets('last completed subtask completes the parent task', (
    tester,
  ) async {
    final updates = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            cardId: 'task-1',
            configIndex: 0,
            data: const {
              'title': 'Visa checklist',
              'is_completed': false,
              'subtasks': [
                {'title': 'Collect documents', 'completed': true},
                {'title': 'Submit form', 'completed': false},
              ],
            },
            onUpdate: (_, __, data) => updates.add(data),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_card_subtask_task-1_1')));
    await tester.pump();

    expect(updates.last['is_completed'], isTrue);
    expect(
      (updates.last['subtasks'] as List).map(
        (subtask) => (subtask as Map)['completed'],
      ),
      [true, true],
    );
  });

  testWidgets('tapping complete sets completed_at, tapping again clears it',
      (tester) async {
    final updates = <Map<String, dynamic>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskCard(
            cardId: 'task-1',
            configIndex: 0,
            data: const {'title': 'Buy bananas', 'is_completed': false},
            onUpdate: (_, __, data) => updates.add(data),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('task_card_toggle_task-1')));
    await tester.pump();
    expect(updates.last['is_completed'], isTrue);
    expect(updates.last['completed_at'], isNotNull);
    expect(DateTime.tryParse(updates.last['completed_at'] as String),
        isNotNull);

    await tester.tap(find.byKey(const ValueKey('task_card_toggle_task-1')));
    await tester.pump();
    expect(updates.last['is_completed'], isFalse);
    expect(updates.last['completed_at'], isNull);
  });
}
