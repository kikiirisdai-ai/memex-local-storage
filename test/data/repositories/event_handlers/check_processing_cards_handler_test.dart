import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/event_handlers/check_processing_cards_handler.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/db/app_database.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/domain/models/event_bus_message.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('isStaleProcessingCard', () {
    CardData cardCreatedAt(DateTime createdAt) => CardData(
          factId: '2026/09/13.md#ts_1',
          createdAt: createdAt.millisecondsSinceEpoch ~/ 1000,
          timestamp: createdAt.millisecondsSinceEpoch ~/ 1000,
          status: 'processing',
          tags: const [],
          uiConfigs: const [],
        );

    test('not stale just after creation', () {
      final now = DateTime(2026, 9, 13, 12, 0, 0);
      final card = cardCreatedAt(now.subtract(const Duration(minutes: 1)));
      expect(isStaleProcessingCard(card, now: now), isFalse);
    });

    test('stale once it has been processing for 5+ minutes', () {
      final now = DateTime(2026, 9, 13, 12, 0, 0);
      final card = cardCreatedAt(now.subtract(const Duration(minutes: 5)));
      expect(isStaleProcessingCard(card, now: now), isTrue);
    });
  });

  group('handleCheckProcessingCards', () {
    late Directory tempRoot;
    late String userId;
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      userId = 'check_processing_${DateTime.now().millisecondsSinceEpoch}';
      await UserStorage.saveUser(userId);
      tempRoot =
          await Directory.systemTemp.createTemp('memex_check_processing_');
      await FileSystemService.init(tempRoot.path);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      AppDatabase.setTestInstance(db);
    });

    tearDown(() async {
      await db.close();
      await tempRoot.delete(recursive: true);
    });

    test(
        'deletes a card that has been stuck in "processing" past the '
        'staleness window and emits CardDeletedMessage', () async {
      final fs = FileSystemService.instance;
      final factId = await fs.allocateCardFactId(userId);
      await fs.updateCardFile(
        userId,
        factId,
        (card) => card.copyWith(
          createdAt: DateTime.now()
                  .subtract(const Duration(minutes: 10))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      );

      final emitted = <EventBusMessage>[];
      await handleCheckProcessingCards(
        {'data': {'card_ids': [factId]}},
        emitEvent: emitted.add,
      );

      expect(await fs.readCardFile(userId, factId), isNull);
      expect(emitted, hasLength(1));
      expect(emitted.single, isA<CardDeletedMessage>());
      expect((emitted.single as CardDeletedMessage).id, factId);
    });

    test('leaves a freshly-created "processing" card alone', () async {
      final fs = FileSystemService.instance;
      final factId = await fs.allocateCardFactId(userId);

      final emitted = <EventBusMessage>[];
      await handleCheckProcessingCards(
        {'data': {'card_ids': [factId]}},
        emitEvent: emitted.add,
      );

      expect(await fs.readCardFile(userId, factId), isNotNull);
      expect(emitted, isEmpty);
    });
  });
}
