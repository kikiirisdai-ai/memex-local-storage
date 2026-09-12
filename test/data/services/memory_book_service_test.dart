import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/memory_book_service.dart';
import 'package:memex/domain/models/card_model.dart';

/// A minimal valid 1x1 transparent PNG, used as stand-in image bytes so the
/// `pdf` package's [pw.MemoryImage] can decode them without needing real
/// photo files in unit tests.
final Uint8List _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==',
);

CardData _card({
  required String factId,
  required int timestamp,
  String? title,
  String? fact,
  List<String>? tags,
  List<String>? assets,
  bool? deleted,
  Map<String, dynamic>? metadata,
}) {
  return CardData(
    factId: factId,
    timestamp: timestamp,
    status: 'done',
    tags: tags ?? const [],
    uiConfigs: const [],
    title: title,
    fact: fact,
    assets: assets,
    deleted: deleted,
    metadata: metadata,
  );
}

void main() {
  group('MemoryBookService.collect', () {
    late DateTime from;
    late DateTime to;

    setUp(() {
      from = DateTime(2026, 1, 1);
      to = DateTime(2026, 1, 31);
    });

    Future<List<CardData>> Function(DateTime, DateTime) providerFor(
      List<CardData> cards,
    ) {
      return (_, __) async => cards;
    }

    test(
        'excludes summary + deleted cards, applies tag filter, sorts ascending, '
        'attaches image bytes to the right card, keeps audio transcript body, '
        'and calls onProgress once per surviving card',
        () async {
      final plainText = _card(
        factId: '2026/01/10.md#ts_1',
        timestamp: DateTime(2026, 1, 10).millisecondsSinceEpoch ~/ 1000,
        title: 'Plain note',
        fact: 'Just some text.',
        tags: ['note'],
      );
      final withImage = _card(
        factId: '2026/01/05.md#ts_1',
        timestamp: DateTime(2026, 1, 5).millisecondsSinceEpoch ~/ 1000,
        title: 'Photo day',
        fact: 'A nice photo.',
        tags: ['note'],
        assets: ['![image](fs://photo1.jpg)'],
      );
      final audioCard = _card(
        factId: '2026/01/15.md#ts_1',
        timestamp: DateTime(2026, 1, 15).millisecondsSinceEpoch ~/ 1000,
        title: 'Voice memo',
        fact: 'Transcribed audio content.',
        tags: ['note'],
        assets: ['[audio](fs://memo1.m4a)'],
      );
      final summaryCard = _card(
        factId: '2026/01/07.md#ts_1',
        timestamp: DateTime(2026, 1, 7).millisecondsSinceEpoch ~/ 1000,
        title: 'Weekly rollup',
        fact: 'Should be excluded.',
        tags: ['WeeklySummary'],
      );
      final deletedCard = _card(
        factId: '2026/01/08.md#ts_1',
        timestamp: DateTime(2026, 1, 8).millisecondsSinceEpoch ~/ 1000,
        title: 'Deleted note',
        fact: 'Should be excluded too.',
        tags: ['note'],
        deleted: true,
      );
      final wrongTagCard = _card(
        factId: '2026/01/20.md#ts_1',
        timestamp: DateTime(2026, 1, 20).millisecondsSinceEpoch ~/ 1000,
        title: 'Other tag',
        fact: 'Not matching the filter.',
        tags: ['other'],
      );

      final allCards = [
        plainText,
        withImage,
        audioCard,
        summaryCard,
        deletedCard,
        wrongTagCard,
      ];

      final imageBytesCalls = <String>[];
      final progressCalls = <List<int>>[];

      final service = MemoryBookService.forTesting(
        cardsProvider: providerFor(allCards),
        imageBytesProvider: (assetRef) async {
          imageBytesCalls.add(assetRef);
          if (assetRef.contains('photo1.jpg')) {
            return _tinyPngBytes;
          }
          // Audio assets (or anything else) resolve to no image bytes.
          return null;
        },
      );

      final result = await service.collect(
        from: from,
        to: to,
        tags: ['note'],
        onProgress: (done, total) => progressCalls.add([done, total]),
      );

      // summaryCard, deletedCard, wrongTagCard excluded → 3 survive.
      expect(result, hasLength(3));
      expect(
        result.map((c) => c.title),
        ['Photo day', 'Plain note', 'Voice memo'],
      );

      // Ascending order by timestamp.
      for (var i = 1; i < result.length; i++) {
        expect(
          result[i].date.isAfter(result[i - 1].date) ||
              result[i].date.isAtSameMomentAs(result[i - 1].date),
          isTrue,
        );
      }

      final photoCard = result.firstWhere((c) => c.title == 'Photo day');
      expect(photoCard.images, hasLength(1));
      expect(photoCard.images.first, _tinyPngBytes);

      final plainCard = result.firstWhere((c) => c.title == 'Plain note');
      expect(plainCard.images, isEmpty);

      final audioResult = result.firstWhere((c) => c.title == 'Voice memo');
      expect(audioResult.images, isEmpty);
      expect(audioResult.body, 'Transcribed audio content.');

      // onProgress called once per surviving card, with the final total.
      expect(progressCalls, hasLength(3));
      expect(progressCalls.map((p) => p[1]).toSet(), {3});
      expect(progressCalls.map((p) => p[0]).toList(), [1, 2, 3]);
    });

    test('maxImagesPerCard caps images attached to a single card', () async {
      final manyImagesCard = _card(
        factId: '2026/01/05.md#ts_1',
        timestamp: DateTime(2026, 1, 5).millisecondsSinceEpoch ~/ 1000,
        title: 'Photo dump',
        fact: 'Lots of photos.',
        tags: const ['note'],
        assets: [
          '![image](fs://photo1.jpg)',
          '![image](fs://photo2.jpg)',
          '![image](fs://photo3.jpg)',
        ],
      );

      final imageBytesCalls = <String>[];
      final service = MemoryBookService.forTesting(
        cardsProvider: providerFor([manyImagesCard]),
        imageBytesProvider: (assetRef) async {
          imageBytesCalls.add(assetRef);
          return _tinyPngBytes;
        },
      );

      final result = await service.collect(
        from: from,
        to: to,
        maxImagesPerCard: 1,
      );

      expect(result, hasLength(1));
      expect(result.first.images, hasLength(1));
      // The cap stops resolution once reached — later assets on the card
      // are never even resolved.
      expect(imageBytesCalls, hasLength(1));
    });

    test('maxTotalImages caps the total images embedded across the book',
        () async {
      final threeImageCards = List.generate(3, (i) {
        return _card(
          factId: '2026/01/0${i + 1}.md#ts_1',
          timestamp: DateTime(2026, 1, i + 1).millisecondsSinceEpoch ~/ 1000,
          title: 'Card $i',
          fact: 'Body $i',
          tags: const ['note'],
          assets: ['![image](fs://photo$i.jpg)'],
        );
      });

      final service = MemoryBookService.forTesting(
        cardsProvider: providerFor(threeImageCards),
        imageBytesProvider: (_) async => _tinyPngBytes,
      );

      final result = await service.collect(
        from: from,
        to: to,
        maxTotalImages: 2,
      );

      expect(result, hasLength(3));
      final totalImages =
          result.fold<int>(0, (sum, c) => sum + c.images.length);
      expect(totalImages, 2);
      // The first two cards (ascending date order) keep their image; the
      // third loses it but keeps its text.
      expect(result[0].images, hasLength(1));
      expect(result[1].images, hasLength(1));
      expect(result[2].images, isEmpty);
      expect(result[2].body, 'Body 2');
    });

    test('mood is read from userMoodScore, falling back to moodScore',
        () async {
      final userScored = _card(
        factId: '2026/01/02.md#ts_1',
        timestamp: DateTime(2026, 1, 2).millisecondsSinceEpoch ~/ 1000,
        fact: 'a',
        metadata: {'user_mood_score': 9, 'mood_score': 3},
      );
      final modelScored = _card(
        factId: '2026/01/03.md#ts_1',
        timestamp: DateTime(2026, 1, 3).millisecondsSinceEpoch ~/ 1000,
        fact: 'b',
        metadata: {'mood_score': 5},
      );

      final service = MemoryBookService.forTesting(
        cardsProvider: providerFor([userScored, modelScored]),
        imageBytesProvider: (_) async => null,
      );

      final result = await service.collect(from: from, to: to);

      expect(result[0].mood, 9);
      expect(result[1].mood, 5);
    });
  });

  group('MemoryBookService.buildPdf', () {
    late Uint8List cjkFontBytes;

    setUpAll(() async {
      final file = File('assets/fonts/NotoSansSC.ttf');
      cjkFontBytes = await file.readAsBytes();
    });

    test('renders cover + timeline for cards (with and without images) '
        'into a valid PDF without throwing', () async {
      final service = MemoryBookService.forTesting(
        cardsProvider: (_, __) async => [],
        imageBytesProvider: (_) async => null,
        fontBytes: cjkFontBytes,
      );

      final cards = [
        MemoryCard(
          date: DateTime(2026, 1, 5),
          title: '第一张照片',
          body: 'A day with a photo.',
          images: [_tinyPngBytes],
          mood: 8,
          tags: const ['note', 'photo'],
        ),
        MemoryCard(
          date: DateTime(2026, 1, 10),
          title: 'Plain entry',
          body: 'Just text, no images.',
          mood: null,
          tags: const [],
        ),
      ];

      final bytes = await service.buildPdf(
        title: '2026年一月记忆册',
        cards: cards,
      );

      expect(bytes, isA<Uint8List>());
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
    });

    test('renders cover only when cards is empty', () async {
      final service = MemoryBookService.forTesting(
        cardsProvider: (_, __) async => [],
        imageBytesProvider: (_) async => null,
        fontBytes: cjkFontBytes,
      );

      final bytes = await service.buildPdf(title: 'Empty book');

      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });

  group('MemoryBookService.export', () {
    test('collects and builds an end-to-end PDF from fakes', () async {
      final cjkFontBytes =
          await File('assets/fonts/NotoSansSC.ttf').readAsBytes();

      final card = _card(
        factId: '2026/01/05.md#ts_1',
        timestamp: DateTime(2026, 1, 5).millisecondsSinceEpoch ~/ 1000,
        title: 'Exported card',
        fact: 'Body text.',
        tags: ['note'],
        assets: ['![image](fs://a.jpg)'],
      );

      final service = MemoryBookService.forTesting(
        cardsProvider: (_, __) async => [card],
        imageBytesProvider: (_) async => _tinyPngBytes,
        fontBytes: cjkFontBytes,
      );

      final bytes = await service.export(
        title: 'Export test',
        from: DateTime(2026, 1, 1),
        to: DateTime(2026, 1, 31),
      );

      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });
}
