import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:logging/logging.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

/// Calls a local Ollama server's native `/api/embeddings` endpoint to embed
/// text with the `bge-m3` model. Used by semantic search indexing/retrieval
/// (Task 3+); this service intentionally has no callers yet.
///
/// Vectors returned by [embed] are NOT normalized — callers should use
/// [cosineSimilarity] (which works for both raw and normalized vectors)
/// rather than assuming unit length / dot product. This keeps storage simple
/// (raw model output) at the cost of a few extra multiplications per
/// comparison, which is negligible at our expected corpus size.
class EmbeddingService {
  static const String model = 'bge-m3';

  /// Max characters of input text sent to the embedding model.
  static const int _maxPromptLength = 2000;

  final Logger _logger = Logger('EmbeddingService');
  final Dio _dio;
  final Future<String?> Function() _ollamaBaseUrl;

  static final EmbeddingService instance = EmbeddingService._();

  EmbeddingService._()
      : _dio = Dio(),
        _ollamaBaseUrl = _resolveOllamaBaseUrlFromUserStorage;

  @visibleForTesting
  EmbeddingService.forTesting({
    required Dio dio,
    required Future<String?> Function() ollamaBaseUrl,
  })  : _dio = dio,
        _ollamaBaseUrl = ollamaBaseUrl;

  static Future<String?> _resolveOllamaBaseUrlFromUserStorage() async {
    try {
      final configs = await UserStorage.getLLMConfigs();
      for (final config in configs) {
        if (config.type == LLMConfig.typeOllama && config.baseUrl.isNotEmpty) {
          return config.baseUrl;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Embeds [text] via Ollama's bge-m3 model. Returns null if no Ollama
  /// config is available, or if the request fails for any reason (network,
  /// non-200 status, malformed body) — this call never throws.
  Future<List<double>?> embed(String text) async {
    try {
      final rawBaseUrl = await _ollamaBaseUrl();
      if (rawBaseUrl == null || rawBaseUrl.isEmpty) return null;

      final base = _stripOllamaSuffix(rawBaseUrl);
      final url = '$base/api/embeddings';

      final response = await _dio.post(
        url,
        data: {
          'model': model,
          'prompt': _truncate(text, _maxPromptLength),
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          validateStatus: (_) => true,
        ),
      );

      if (response.statusCode != 200) {
        _logger.warning(
          'Embedding request failed with status ${response.statusCode}',
        );
        return null;
      }

      final data = response.data;
      if (data is! Map || data['embedding'] is! List) {
        _logger.warning('Embedding response missing embedding field');
        return null;
      }

      final embedding = (data['embedding'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      return embedding;
    } catch (e) {
      _logger.warning('Embedding request errored: $e');
      return null;
    }
  }

  /// Strips a trailing '/v1' (and any trailing slash) from an
  /// OpenAI-compatible Ollama base URL, since Ollama's native embeddings
  /// endpoint lives at '/api/embeddings', not under '/v1'.
  String _stripOllamaSuffix(String baseUrl) {
    var base = baseUrl;
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1')) {
      base = base.substring(0, base.length - 3);
    }
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return text.substring(0, max);
  }
}

/// Cosine similarity between two vectors. Returns 0.0 if the vectors differ
/// in length, either is empty, or either has zero magnitude. Works for both
/// raw and pre-normalized vectors (for unit vectors this is equivalent to a
/// plain dot product).
double cosineSimilarity(List<double> a, List<double> b) {
  if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }

  if (normA == 0.0 || normB == 0.0) return 0.0;

  return dot / (sqrt(normA) * sqrt(normB));
}

/// Returns a unit-length copy of [v]. If [v] has zero magnitude, returns it
/// unchanged (rather than dividing by zero).
List<double> normalizeVector(List<double> v) {
  var normSquared = 0.0;
  for (final x in v) {
    normSquared += x * x;
  }
  if (normSquared == 0.0) return v;

  final norm = sqrt(normSquared);
  return v.map((x) => x / norm).toList();
}
