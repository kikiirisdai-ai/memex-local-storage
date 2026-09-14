import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/domain/models/timeline_card_model.dart';
import 'package:memex/l10n/app_localizations.dart';
import 'package:memex/ui/archive/view_models/archive_list_viewmodel.dart';
import 'package:memex/ui/archive/widgets/archive_list_screen.dart';
import 'package:memex/utils/result.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

TimelineCardModel _card({required String id, String title = 'Card', int? archivedAt}) {
  return TimelineCardModel(
    id: id,
    timestamp: DateTime(2026, 1, 1),
    tags: const [],
    status: 'completed',
    title: title,
    uiConfigs: const [],
    archivedAt: archivedAt,
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

  testWidgets('lists archived cards with the retention notice',
      (tester) async {
    final vm = ArchiveListViewModel.forTest(
      fetchArchivedCards: () async =>
          Ok([_card(id: 'a', title: 'Old note', archivedAt: 100)]),
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const ArchiveListScreen()),
    ));

    expect(find.text('Old note'), findsOneWidget);
    expect(find.textContaining('30'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no archived cards',
      (tester) async {
    final vm = ArchiveListViewModel.forTest(
      fetchArchivedCards: () async => const Ok([]),
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const ArchiveListScreen()),
    ));

    expect(find.text('No archived records yet'), findsOneWidget);
  });

  testWidgets(
      'selecting a card reveals the action bar, restore calls unarchiveCard',
      (tester) async {
    String? unarchivedId;
    final vm = ArchiveListViewModel.forTest(
      fetchArchivedCards: () async => Ok([_card(id: 'a')]),
      unarchiveCard: (id) async {
        unarchivedId = id;
        return true;
      },
    );
    await vm.load();

    await tester.pumpWidget(_wrap(
      ChangeNotifierProvider.value(value: vm, child: const ArchiveListScreen()),
    ));

    expect(find.text('Restore to timeline'), findsNothing);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('Restore to timeline'), findsOneWidget);

    await tester.tap(find.text('Restore to timeline'));
    await tester.pumpAndSettle();

    expect(unarchivedId, 'a');
  });
}
