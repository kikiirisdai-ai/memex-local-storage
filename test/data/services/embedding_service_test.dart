import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memex/data/services/embedding_service.dart';

void main() {
  group('EmbeddingService.embed', () {
    test('returns embedding vector on HTTP 200', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'embedding': [0.1, 0.2, 0.3],
                  },
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, [0.1, 0.2, 0.3]);
    });

    test('returns null on non-200 status', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 500,
                  data: {'error': 'boom'},
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, isNull);
    });

    test('returns null on DioException / thrown error', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.reject(
                DioException(
                  requestOptions: options,
                  error: 'connection failed',
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, isNull);
    });

    test('returns null and makes no request when no Ollama base URL',
        () async {
      var postCalled = false;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              postCalled = true;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'embedding': [0.1, 0.2, 0.3],
                  },
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => null,
      );

      final result = await service.embed('hello world');

      expect(result, isNull);
      expect(postCalled, isFalse);
    });

    test('strips trailing /v1 and appends /api/embeddings', () async {
      String? requestedPath;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedPath = options.path;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'embedding': [1.0],
                  },
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      await service.embed('hi');

      expect(requestedPath, 'http://localhost:11434/api/embeddings');
    });

    test('returns null when body has no embedding key', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'foo': 1},
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, isNull);
    });

    test('returns null when embedding is present but not a List', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {'embedding': 'oops'},
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, isNull);
    });

    test('converts integer JSON embedding values to doubles', () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'embedding': [1, 2, 3],
                  },
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434/v1',
      );

      final result = await service.embed('hello world');

      expect(result, isNotNull);
      expect(result, everyElement(isA<double>()));
      expect(result![0], closeTo(1.0, 1e-9));
      expect(result[1], closeTo(2.0, 1e-9));
      expect(result[2], closeTo(3.0, 1e-9));
    });

    test('base URL without /v1 still resolves to /api/embeddings', () async {
      String? requestedPath;
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              requestedPath = options.path;
              handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'embedding': [1.0],
                  },
                ),
              );
            },
          ),
        );
      final service = EmbeddingService.forTesting(
        dio: dio,
        ollamaBaseUrl: () async => 'http://localhost:11434',
      );

      await service.embed('hi');

      expect(requestedPath, 'http://localhost:11434/api/embeddings');
    });
  });

  group('cosineSimilarity', () {
    test('orthogonal vectors return 0', () {
      expect(cosineSimilarity([1, 0], [0, 1]), closeTo(0.0, 1e-9));
    });

    test('identical vectors return ~1', () {
      expect(
        cosineSimilarity([1, 2, 3], [1, 2, 3]),
        closeTo(1.0, 1e-9),
      );
    });

    test('length mismatch returns 0', () {
      expect(cosineSimilarity([1, 2], [1, 2, 3]), 0.0);
    });

    test('zero-length vectors return 0', () {
      expect(cosineSimilarity([], []), 0.0);
    });

    test('zero vector returns 0', () {
      expect(cosineSimilarity([0, 0, 0], [1, 2, 3]), 0.0);
    });
  });

  group('normalizeVector', () {
    test('result has unit length', () {
      final normalized = normalizeVector([3.0, 4.0]);
      final length = normalized.fold<double>(
        0.0,
        (sum, v) => sum + v * v,
      );
      expect(length, closeTo(1.0, 1e-9));
    });

    test('zero vector remains unchanged', () {
      expect(normalizeVector([0.0, 0.0]), [0.0, 0.0]);
    });
  });
}
