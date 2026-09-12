import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/db/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  group('AppDatabase migrations', () {
    test('upgrades schema 14 to current without durable agent run tables',
        () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'memex_app_database_migration_',
      );
      final dbFile = File('${tempDir.path}/memex.sqlite');
      _createSchema14Database(dbFile);

      final db = AppDatabase.forTesting(NativeDatabase(dbFile));
      try {
        final schemaVersion = await _userVersion(db);
        expect(schemaVersion, 18);

        final taskColumns = await _columnNames(db, 'tasks');
        expect(taskColumns, contains('run_id'));

        final legacyTask = await (db.select(db.tasks)
              ..where((task) => task.id.equals('legacy-task')))
            .getSingle();
        expect(legacyTask.runId, isNull);

        final taskIndices = await _indexNames(db, 'tasks');
        expect(taskIndices, contains('idx_tasks_run_id'));

        final tables = await _tableNames(db);
        expect(tables, isNot(contains('agent_runs')));
        // v17 migration creates the semantic-search embeddings table.
        expect(tables, contains('card_embeddings'));
        // v18 migration creates the standalone goal-tracking table.
        expect(tables, contains('goals'));

        final goalIndices = await _indexNames(db, 'goals');
        expect(goalIndices, contains('idx_goals_user_status'));

        // Table should be queryable with no residual-table exception.
        final goalRows = await db.select(db.goals).get();
        expect(goalRows, isEmpty);
      } finally {
        await db.close();
        await tempDir.delete(recursive: true);
      }
    });

    test('fresh onCreate install includes goals and card_embeddings indexes',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final goalIndices = await _indexNames(db, 'goals');
        expect(goalIndices, contains('idx_goals_user_status'));

        final cardEmbeddingIndices = await _indexNames(db, 'card_embeddings');
        expect(
            cardEmbeddingIndices, contains('idx_card_embeddings_fact_id'));
      } finally {
        await db.close();
      }
    });
  });
}

void _createSchema14Database(File file) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    db.execute('''
CREATE TABLE tasks (
  id TEXT NOT NULL PRIMARY KEY,
  type TEXT NOT NULL,
  payload TEXT NULL,
  status TEXT NOT NULL,
  priority INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NULL,
  scheduled_at INTEGER NULL,
  completed_at INTEGER NULL,
  updated_at INTEGER NULL,
  retry_count INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 3,
  error TEXT NULL,
  result TEXT NULL,
  biz_id TEXT NULL,
  dependencies TEXT NULL
);
''');
    db.execute('CREATE INDEX idx_tasks_status ON tasks(status)');
    db.execute('CREATE INDEX idx_tasks_scheduled_at ON tasks(scheduled_at)');
    db.execute('CREATE INDEX idx_tasks_type_biz_id ON tasks(type, biz_id)');
    db.execute(
      '''
INSERT INTO tasks (
  id,
  type,
  payload,
  status,
  priority,
  created_at,
  retry_count,
  max_retries
) VALUES (
  'legacy-task',
  'super_agent_chat_turn_task',
  '{}',
  'pending',
  0,
  1700000000,
  0,
  3
);
''',
    );
    db.execute('PRAGMA user_version = 14');
  } finally {
    db.dispose();
  }
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<List<String>> _columnNames(AppDatabase db, String tableName) async {
  final rows = await db.customSelect("PRAGMA table_info('$tableName')").get();
  return [
    for (final row in rows) row.read<String>('name'),
  ];
}

Future<List<String>> _indexNames(AppDatabase db, String tableName) async {
  final rows = await db.customSelect("PRAGMA index_list('$tableName')").get();
  return [
    for (final row in rows) row.read<String>('name'),
  ];
}

Future<List<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return [
    for (final row in rows) row.read<String>('name'),
  ];
}
