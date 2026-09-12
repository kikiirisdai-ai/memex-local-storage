import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/goal_suggestion_resolution_store.dart';
import 'package:memex/db/app_database.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late GoalSuggestionResolutionStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    store = GoalSuggestionResolutionStore.forTesting(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('isResolved is false before markResolved, true after', () async {
    expect(await store.isResolved('artifact-1'), isFalse);

    await store.markResolved('artifact-1');

    expect(await store.isResolved('artifact-1'), isTrue);
  });

  test('markResolved is idempotent (calling twice does not throw)', () async {
    await store.markResolved('artifact-1');
    await store.markResolved('artifact-1');
    expect(await store.isResolved('artifact-1'), isTrue);
  });

  test('different artifact ids are independent', () async {
    await store.markResolved('artifact-1');
    expect(await store.isResolved('artifact-2'), isFalse);
  });
}
