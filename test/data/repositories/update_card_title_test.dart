import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/repositories/update_card_title.dart';
import 'package:memex/data/services/event_bus_service.dart';
import 'package:memex/data/services/file_system_service.dart';
import 'package:memex/domain/models/card_model.dart';
import 'package:memex/utils/user_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const userId = 'test_user';
  const cardId = '2026/04/28.md#ts_1';
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await UserStorage.saveUser(userId);
    await UserStorage.setLocale(const Locale('en'));
    tempDir = await Directory.systemTemp.createTemp('memex_update_title_');
    await FileSystemService.init(tempDir.path);
    EventBusService.instance.clearHandlers();
    await EventBusService.instance.connect();
  });

  tearDown(() async {
    EventBusService.instance.clearHandlers();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedCard({String? title}) async {
    await FileSystemService.instance.safeWriteCardFile(
      userId,
      cardId,
      CardData(
        factId: cardId,
        timestamp: 1777332000,
        status: 'completed',
        tags: const [],
        title: title,
        uiConfigs: const [
          UiConfig(templateId: 'snippet', data: {'text': 'original body'}),
        ],
      ),
    );
  }

  test('writes a corrected title and notifies the timeline', () async {
    await seedCard(title: 'AI guessed wrong');

    CardUpdatedMessage? observedUpdate;
    EventBusService.instance.addHandler(
      EventBusMessageType.cardUpdated,
      (message) => observedUpdate = message as CardUpdatedMessage,
    );

    final success = await updateCardTitleEndpoint(cardId, 'What I meant');
    await Future<void>.delayed(Duration.zero);

    expect(success, isTrue);
    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    expect(card!.title, 'What I meant');
    expect(observedUpdate, isNotNull);
    expect(observedUpdate!.id, cardId);
  });

  test('trims surrounding whitespace', () async {
    await seedCard(title: 'old');

    await updateCardTitleEndpoint(cardId, '  padded title  ');

    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    expect(card!.title, 'padded title');
  });

  test('clears the title when given an empty string', () async {
    await seedCard(title: 'remove me');

    final success = await updateCardTitleEndpoint(cardId, '   ');

    expect(success, isTrue);
    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    expect(card!.title, isNull);
  });

  test('adds a title to a card that never had one', () async {
    await seedCard();

    await updateCardTitleEndpoint(cardId, 'Now titled');

    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    expect(card!.title, 'Now titled');
  });

  test('leaves the card body untouched', () async {
    await seedCard(title: 'old');

    await updateCardTitleEndpoint(cardId, 'new');

    final card = await FileSystemService.instance.readCardFile(userId, cardId);
    expect(card!.uiConfigs.single.data['text'], 'original body');
  });

  test('returns false for a card that does not exist', () async {
    expect(await updateCardTitleEndpoint('2026/01/01.md#nope', 'x'), isFalse);
  });
}
