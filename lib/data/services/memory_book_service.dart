import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../domain/models/card_model.dart';
import '../../domain/models/system_card_constants.dart';
import '../../utils/logger.dart';
import '../../utils/user_storage.dart';
import 'asset_reference_service.dart';
import 'file_system_service.dart';

/// Path of the bundled CJK (Simplified Chinese) TTF font used to render
/// Chinese text in exported memory-book PDFs.
const String _cjkFontAssetPath = 'assets/fonts/NotoSansSC.ttf';

/// One timeline entry rendered into the memory-book PDF: a single non-summary
/// card's content plus any resolved (and already transcoded) image bytes.
class MemoryCard {
  final DateTime date;
  final String? title;
  final String body;
  final List<Uint8List> images;
  final int? mood;
  final List<String> tags;

  const MemoryCard({
    required this.date,
    this.title,
    required this.body,
    List<Uint8List>? images,
    this.mood,
    List<String>? tags,
  })  : images = images ?? const [],
        tags = tags ?? const [];
}

/// Plain, isolate-sendable representation of one [MemoryCard], used as the
/// payload passed to [_buildPdfIsolate] via [compute]. Background isolates
/// can only receive simple/transferable data (no plugin-backed objects), so
/// [MemoryBookService.buildPdf] maps [MemoryCard]s to this record shape
/// before handing them off.
typedef _PdfCardPayload = ({
  DateTime date,
  String? title,
  String body,
  int? mood,
  List<String> tags,
  List<Uint8List> images,
});

/// Payload passed to [_buildPdfIsolate]: everything needed to assemble and
/// serialize the PDF, with the CJK font bytes already loaded on the main
/// isolate (a background isolate has no `rootBundle` access).
typedef _PdfPayload = ({
  String title,
  List<_PdfCardPayload> cards,
  Uint8List? fontBytes,
});

/// Top-level (background-isolate-safe) entry point for [compute]: builds the
/// cover + timeline PDF and serializes it. This is pure-Dart work (no
/// platform channels), so it's safe to run off the main isolate to avoid
/// blocking the UI thread on large exports (hundreds of cards/images).
Future<Uint8List> _buildPdfIsolate(_PdfPayload payload) async {
  pw.Font? cjkFont;
  final fontBytes = payload.fontBytes;
  if (fontBytes != null) {
    try {
      cjkFont = pw.Font.ttf(fontBytes.buffer.asByteData());
    } catch (_) {
      // Fall back to the pdf package's default font; CJK glyphs would
      // render as tofu, but the pipeline (and English text) keeps working.
      cjkFont = null;
    }
  }

  final doc = pw.Document();

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (context) {
        return pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                payload.title,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: cjkFont,
                  fontSize: 32,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text(
                'Memex Memory Book',
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  font: cjkFont,
                  fontSize: 14,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  if (payload.cards.isNotEmpty) {
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        footer: (context) => pw.Container(
          alignment: pw.Alignment.center,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(
              font: cjkFont,
              fontSize: 10,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) => [
          for (final card in payload.cards) _buildCardBlock(card, cjkFont),
        ],
      ),
    );
  }

  return doc.save();
}

/// Renders one [_PdfCardPayload] as a timeline flow block (date, title,
/// body, stacked images, mood/tags footer). Top-level so it can run inside
/// the background isolate spawned by [compute] in [_buildPdfIsolate].
pw.Widget _buildCardBlock(_PdfCardPayload card, pw.Font? font) {
  final date = card.date;
  final dateStr = '${date.year}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  final footerParts = <String>[
    if (card.mood != null) 'mood ${card.mood}',
    if (card.tags.isNotEmpty) card.tags.map((t) => '#$t').join(' '),
  ];

  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 16),
    padding: const pw.EdgeInsets.only(bottom: 12),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          dateStr,
          style: pw.TextStyle(
            font: font,
            fontSize: 9,
            color: PdfColors.grey600,
          ),
        ),
        if (card.title != null && card.title!.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4, bottom: 4),
            child: pw.Text(
              card.title!,
              style: pw.TextStyle(
                font: font,
                fontSize: 15,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        if (card.body.isNotEmpty)
          pw.Text(
            card.body,
            style: pw.TextStyle(font: font, fontSize: 11),
          ),
        for (final img in card.images)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Image(
              pw.MemoryImage(img),
              fit: pw.BoxFit.contain,
              width: double.infinity,
            ),
          ),
        if (footerParts.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: pw.Text(
              footerParts.join(' · '),
              style: pw.TextStyle(
                font: font,
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Builds memory-book PDF exports: collecting timeline cards for a date
/// range, resolving/transcoding their image assets, and laying out a
/// cover + timeline PDF with the bundled CJK font.
///
/// Task 1 proved the `pdf` package + bundled CJK font pipeline with a single
/// cover page. This task adds card collection (with summary/deleted/tag
/// filtering), image resolution (with HEIC→JPEG transcoding so the `pdf`
/// package can embed iOS photos), and the full timeline layout.
class MemoryBookService {
  static final Logger _logger = getLogger('MemoryBookService');

  /// Default cap on images attached to a single card (see [collect]).
  static const int defaultMaxImagesPerCard = 4;

  /// Default cap on total images embedded across the whole exported book
  /// (see [collect]). At ~300KB/transcoded image, 200 images tops out
  /// around ~60MB resident, which keeps a "baby's first year" export
  /// (hundreds of cards) from OOMing on-device.
  static const int defaultMaxTotalImages = 200;

  final Future<List<CardData>> Function(DateTime from, DateTime to)?
      _cardsProvider;
  final Future<Uint8List?> Function(String assetRef)? _imageBytesProvider;
  final Uint8List? _injectedFontBytes;

  /// Production constructor: collects cards via [FileSystemService.instance]
  /// and resolves/transcodes images via [AssetReferenceService] +
  /// `flutter_image_compress`, scoped to the current user from
  /// [UserStorage.getUserId].
  MemoryBookService()
      : _cardsProvider = null,
        _imageBytesProvider = null,
        _injectedFontBytes = null;

  /// Test-only constructor that bypasses the filesystem/asset pipeline so
  /// unit tests can exercise [collect]/[buildPdf]/[export] with fakes.
  @visibleForTesting
  MemoryBookService.forTesting({
    required Future<List<CardData>> Function(DateTime from, DateTime to)
        cardsProvider,
    required Future<Uint8List?> Function(String assetRef) imageBytesProvider,
    Uint8List? fontBytes,
  })  : _cardsProvider = cardsProvider,
        _imageBytesProvider = imageBytesProvider,
        _injectedFontBytes = fontBytes;

  /// Collects non-summary, non-deleted cards in `[from, to]`, optionally
  /// filtered to those carrying any of [tags], sorted ascending by
  /// timestamp, with their image assets resolved to bytes.
  ///
  /// Image memory is capped so a "baby's first year" export (hundreds of
  /// cards, each with photos) doesn't hold every transcoded JPEG in memory
  /// at once: at most [maxImagesPerCard] images are attached per card, and
  /// at most [maxTotalImages] images are embedded across the whole result —
  /// once either cap is hit, later images are skipped but the card's text
  /// (title/body/mood/tags) is still included. Truncation is logged (not
  /// silently dropped).
  ///
  /// [onProgress] is invoked once per surviving card, after that card's
  /// images have been resolved, as `(doneCount, totalSurvivingCount)`.
  Future<List<MemoryCard>> collect({
    required DateTime from,
    required DateTime to,
    List<String>? tags,
    void Function(int done, int total)? onProgress,
    int maxImagesPerCard = defaultMaxImagesPerCard,
    int maxTotalImages = defaultMaxTotalImages,
  }) async {
    final cardsData = await _fetchCards(from, to);

    final filtered = cardsData.where((c) {
      if (c.deleted == true) return false;
      if (c.tags.any(summaryTags.contains)) return false;
      if (tags != null && tags.isNotEmpty && !c.tags.any(tags.contains)) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final total = filtered.length;
    final result = <MemoryCard>[];
    var totalImagesEmbedded = 0;
    var cardsWithPerCardCapHit = 0;
    var globalCapHit = false;
    for (var i = 0; i < filtered.length; i++) {
      final card = filtered[i];
      final images = <Uint8List>[];
      var perCardCapHit = false;
      for (final asset in card.assets) {
        if (images.length >= maxImagesPerCard) {
          perCardCapHit = true;
          break;
        }
        if (totalImagesEmbedded >= maxTotalImages) {
          globalCapHit = true;
          break;
        }
        final bytes = await _resolveImageBytes(asset);
        if (bytes != null) {
          images.add(bytes);
          totalImagesEmbedded++;
        }
      }
      if (perCardCapHit) cardsWithPerCardCapHit++;
      final mood =
          sanitizeMoodScore(card.metadata?[CardMetadataKeys.userMoodScore]) ??
              sanitizeMoodScore(card.metadata?[CardMetadataKeys.moodScore]);

      result.add(
        MemoryCard(
          date: DateTime.fromMillisecondsSinceEpoch(card.timestamp * 1000),
          title: card.title,
          body: card.fact ?? '',
          images: images,
          mood: mood,
          tags: card.tags,
        ),
      );
      onProgress?.call(i + 1, total);
    }

    if (cardsWithPerCardCapHit > 0) {
      _logger.warning(
        'Memory book export: capped images on $cardsWithPerCardCapHit '
        'card(s) at maxImagesPerCard=$maxImagesPerCard; extra images on '
        'those cards were skipped (text still included).',
      );
    }
    if (globalCapHit) {
      _logger.warning(
        'Memory book export: reached global image cap '
        'maxTotalImages=$maxTotalImages ($totalImagesEmbedded embedded); '
        'later cards in this export lost some/all images but kept their '
        'text.',
      );
    }

    return result;
  }

  /// Builds a memory-book PDF: a cover page with [title], followed by a
  /// paginated timeline of [cards] (date, title, body, stacked images, and a
  /// mood/tags footer line per card), with page-number footers.
  ///
  /// [fontBytes] allows injecting CJK font bytes directly (used by tests, or
  /// callers that already have the font loaded). When omitted, this falls
  /// back to any font bytes injected via [MemoryBookService.forTesting], then
  /// to the bundled asset at [_cjkFontAssetPath] via [rootBundle]. If no font
  /// bytes can be obtained or the bytes fail to parse as a font, this falls
  /// back to the pdf package's default font so the document is still
  /// produced (Chinese glyphs would render as tofu in that fallback case, but
  /// English text and the overall pipeline keep working).
  ///
  /// The actual PDF assembly + serialization (`pw.Document.save()`, plus the
  /// TTF font parse) is pure-Dart work that can take multiple seconds for a
  /// large export, so by default it runs off the main isolate via [compute]
  /// (see [_buildPdfIsolate]) to avoid freezing the UI. A background isolate
  /// has no `rootBundle`/platform-channel access, so the font bytes are
  /// resolved here on the main isolate first and passed into the payload.
  /// [useIsolate] can be set to `false` to run the build inline instead.
  Future<Uint8List> buildPdf({
    required String title,
    List<MemoryCard> cards = const [],
    Uint8List? fontBytes,
    bool useIsolate = true,
  }) async {
    final resolvedFontBytes = fontBytes ??
        _injectedFontBytes ??
        await _loadBundledFontBytes();

    final payload = (
      title: title,
      cards: [
        for (final c in cards)
          (
            date: c.date,
            title: c.title,
            body: c.body,
            mood: c.mood,
            tags: c.tags,
            images: c.images,
          ),
      ],
      fontBytes: resolvedFontBytes,
    );

    if (useIsolate) {
      return compute(_buildPdfIsolate, payload);
    }
    return _buildPdfIsolate(payload);
  }

  /// Collects cards for `[from, to]` (optionally filtered by [tags]) and
  /// renders them into a full memory-book PDF titled [title].
  ///
  /// [maxImagesPerCard] and [maxTotalImages] are forwarded to [collect] to
  /// cap the memory held by transcoded images (see its docs).
  Future<Uint8List> export({
    required String title,
    required DateTime from,
    required DateTime to,
    List<String>? tags,
    void Function(int, int)? onProgress,
    int maxImagesPerCard = defaultMaxImagesPerCard,
    int maxTotalImages = defaultMaxTotalImages,
  }) async {
    final cards = await collect(
      from: from,
      to: to,
      tags: tags,
      onProgress: onProgress,
      maxImagesPerCard: maxImagesPerCard,
      maxTotalImages: maxTotalImages,
    );
    return buildPdf(title: title, cards: cards);
  }

  Future<List<CardData>> _fetchCards(DateTime from, DateTime to) async {
    final provider = _cardsProvider;
    if (provider != null) return provider(from, to);

    final userId = await UserStorage.getUserId();
    if (userId == null || userId.isEmpty) return const [];

    final fs = FileSystemService.instance;
    final paths = await fs.getCardFilesInDateRange(userId, from, to);

    final cards = <CardData>[];
    for (final cardPath in paths) {
      final factId = fs.factIdFromCardPath(cardPath);
      if (factId == null) continue;
      final card = await fs.readCardFile(userId, factId);
      if (card != null) cards.add(card);
    }
    return cards;
  }

  Future<Uint8List?> _resolveImageBytes(String assetRef) async {
    final provider = _imageBytesProvider;
    if (provider != null) return provider(assetRef);

    try {
      final userId = await UserStorage.getUserId();
      if (userId == null || userId.isEmpty) return null;

      final resolved = await AssetReferenceService.resolveExisting(
        userId: userId,
        reference: assetRef,
      );
      if (resolved == null || resolved.type != AssetReferenceType.image) {
        // Not an image (e.g. audio asset) or the file no longer exists —
        // the transcript already lives in the card's body text.
        return null;
      }
      if (!await File(resolved.absolutePath).exists()) return null;

      // Always route through flutter_image_compress: it transcodes iOS
      // HEIC (which the pdf package cannot embed) to JPEG, and also caps
      // the size of already-JPEG/PNG photos so the export stays small.
      final compressed = await FlutterImageCompress.compressWithFile(
        resolved.absolutePath,
        minWidth: 1200,
        minHeight: 1200,
        quality: 80,
        format: CompressFormat.jpeg,
      );
      return compressed;
    } catch (e, st) {
      _logger.warning(
        'Failed to resolve image bytes for asset "$assetRef": $e',
        e,
        st,
      );
      return null;
    }
  }

  Future<Uint8List?> _loadBundledFontBytes() async {
    try {
      final data = await rootBundle.load(_cjkFontAssetPath);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } catch (e, st) {
      _logger.warning('Failed to load bundled CJK font asset: $e', e, st);
      return null;
    }
  }
}
