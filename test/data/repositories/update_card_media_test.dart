import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/card.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'media_update_user';
  const cardId = '2026/09/07.md#ts_1';
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser(userId);
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_card_media_');
    await FileSystemService.init(tempDir.path);
    EventBusService.instance.clearHandlers();
    await EventBusService.instance.connect();

    await FileSystemService.instance.safeWriteCardFile(
      userId,
      cardId,
      const CardData(
        factId: cardId,
        timestamp: 1781790000,
        status: 'completed',
        tags: [],
        fact: '在看《三体》。',
        uiConfigs: [],
        metadata: {'media_type': 'tv', 'media_status': 'doing'},
      ),
    );
  });

  tearDown(() async {
    EventBusService.instance.clearHandlers();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('updateCardMediaStatusEndpoint', () {
    test('updates status and preserves existing metadata', () async {
      CardUpdatedMessage? observed;
      EventBusService.instance.addHandler(
        EventBusMessageType.cardUpdated,
        (message) => observed = message as CardUpdatedMessage,
      );

      final ok = await updateCardMediaStatusEndpoint(cardId, 'done');
      await Future<void>.delayed(Duration.zero);

      expect(ok, isTrue);
      final card = await FileSystemService.instance.readCardFile(userId, cardId);
      expect(card!.metadata?['media_status'], 'done');
      expect(card.metadata?['media_type'], 'tv');
      expect(observed, isNotNull);
      expect(observed!.id, cardId);
    });

    test('rejects an out-of-whitelist status', () async {
      final ok = await updateCardMediaStatusEndpoint(cardId, 'watching');
      expect(ok, isFalse);
      final card = await FileSystemService.instance.readCardFile(userId, cardId);
      expect(card!.metadata?['media_status'], 'doing');
    });

    test('returns false for a missing card', () async {
      final ok = await updateCardMediaStatusEndpoint('nope', 'done');
      expect(ok, isFalse);
    });
  });

  group('updateCardMediaRatingEndpoint', () {
    test('sets user rating and comment, preserving existing metadata',
        () async {
      final ok = await updateCardMediaRatingEndpoint(cardId, 8, '第一部很好看');
      await Future<void>.delayed(Duration.zero);

      expect(ok, isTrue);
      final card = await FileSystemService.instance.readCardFile(userId, cardId);
      expect(card!.metadata?['user_media_rating'], 8);
      expect(card.metadata?['media_comment'], '第一部很好看');
      expect(card.metadata?['media_status'], 'doing');
    });

    test('null comment clears any existing comment', () async {
      await updateCardMediaRatingEndpoint(cardId, 7, '先记一句');
      final ok = await updateCardMediaRatingEndpoint(cardId, 7, null);
      expect(ok, isTrue);
      final card = await FileSystemService.instance.readCardFile(userId, cardId);
      expect(card!.metadata!.containsKey('media_comment'), isFalse);
    });

    test('rejects an out-of-range rating', () async {
      final ok = await updateCardMediaRatingEndpoint(cardId, 11, 'x');
      expect(ok, isFalse);
    });

    test('returns false for a missing card', () async {
      final ok = await updateCardMediaRatingEndpoint('nope', 5, null);
      expect(ok, isFalse);
    });
  });
}
