import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/memory_book_service.dart';

void main() {
  group('MemoryBookService.buildPdf', () {
    late Uint8List cjkFontBytes;

    setUpAll(() async {
      // Read the bundled CJK TTF directly from disk to avoid needing an
      // asset-bundle-backed rootBundle in a plain `flutter test` run.
      final file = File('assets/fonts/NotoSansSC.ttf');
      cjkFontBytes = await file.readAsBytes();
    });

    test('renders a Chinese title into a valid PDF with injected font bytes', () async {
      final service = MemoryBookService();

      final bytes = await service.buildPdf(
        title: '测试记忆册 · 宝宝的第一年',
        fontBytes: cjkFontBytes,
      );

      expect(bytes, isA<Uint8List>());
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
      expect(bytes.length, greaterThan(1000));
    });

    test('falls back to default font and does not throw when no font bytes are provided', () async {
      final service = MemoryBookService();

      final bytes = await service.buildPdf(title: 'Hello', fontBytes: null);

      expect(bytes, isA<Uint8List>());
      expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
    });
  });
}
