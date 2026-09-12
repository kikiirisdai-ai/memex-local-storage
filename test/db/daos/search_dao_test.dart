import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('SearchDao.searchCards content_snippet column fix', () {
    late Directory tempRoot;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final userId = 'search_dao_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot = await Directory.systemTemp.createTemp('memex_search_dao_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    test('content_snippet reflects the content column, not tags', () async {
      await db.searchDao.upsertCardFts(
        factId: 'f1',
        title: '爬山',
        tags: '户外',
        content: '今天去爬山看瀑布',
        insight: '',
      );

      final rows = await db.searchDao.searchCards('爬山');

      expect(rows, isNotEmpty);
      final row = rows.first;
      final contentSnippet = row['content_snippet'] as String;
      expect(contentSnippet, isNotEmpty);
      // The content column contains "瀑布" (waterfall) which never appears
      // in the tags column ("户外" / outdoors). Before the column-index fix,
      // snippet() pointed at column 2 (tags) and could never surface this.
      expect(contentSnippet, contains('瀑布'));
      // And it must not merely echo the tags text.
      expect(contentSnippet, isNot(contains('户外')));
    });

    test('tags vs content snippet are distinguishable', () async {
      await db.searchDao.upsertCardFts(
        factId: 'f2',
        title: '游泳',
        tags: '运动 健身',
        content: '今天去游泳池游泳锻炼身体',
        insight: '',
      );

      final rows = await db.searchDao.searchCards('游泳');

      expect(rows, isNotEmpty);
      final row = rows.first;
      final contentSnippet = row['content_snippet'] as String;
      // Content snippet should surface content-only vocabulary ("锻炼"),
      // which never appears in the tags field ("运动 健身").
      expect(contentSnippet, isNotEmpty);
      expect(contentSnippet, isNot(contains('健身')));
    });
  });
}
