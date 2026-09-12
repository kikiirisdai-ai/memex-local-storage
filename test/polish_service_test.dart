import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/dio.dart';
import 'package:memex/data/services/polish_service.dart';
import 'package:test/test.dart';

/// Returns output keyed off which system prompt was sent (plain vs
/// literary), so assertions stay stable even though the two `generate()`
/// calls race in parallel and may land in either order.
class _StyleKeyedClient extends LLMClient {
  _StyleKeyedClient({this.plainOut, this.literaryOut});

  /// Use `'__throw__'` to simulate that style's call failing.
  final String? plainOut;
  final String? literaryOut;

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    final sys = messages.whereType<SystemMessage>().first.content;
    final isLiterary = sys.contains('文采');
    final out = isLiterary ? literaryOut : plainOut;
    if (out == '__throw__') throw StateError('offline');
    return ModelMessage(model: 'stub-model', textOutput: out);
  }

  @override
  Future<Stream<StreamingMessage>> stream(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }
}

PolishService _svc({String? plainOut, String? literaryOut}) =>
    PolishService.forTesting(
      resourcesProvider: () async => (
        client:
            _StyleKeyedClient(plainOut: plainOut, literaryOut: literaryOut)
                as LLMClient,
        modelConfig: ModelConfig(model: 'stub-model'),
      ),
    );

void main() {
  test('returns two variants', () async {
    final r = await _svc(plainOut: '通顺版文本', literaryOut: '文采版文本')
        .polish('原话');
    expect(r.plain, '通顺版文本');
    expect(r.literary, '文采版文本');
    expect(r.anySucceeded, isTrue);
  });

  test('one style fails -> that field null, other kept', () async {
    final r =
        await _svc(plainOut: '通顺版', literaryOut: '__throw__').polish('原话');
    expect(r.plain, '通顺版');
    expect(r.literary, isNull);
    expect(r.anySucceeded, isTrue);
  });

  test('both fail -> anySucceeded false', () async {
    final r = await _svc(plainOut: '__throw__', literaryOut: '__throw__')
        .polish('原话');
    expect(r.plain, isNull);
    expect(r.literary, isNull);
    expect(r.anySucceeded, isFalse);
  });

  test('empty output treated as failure', () async {
    final r = await _svc(plainOut: '', literaryOut: '   ').polish('原话');
    expect(r.plain, isNull);
    expect(r.literary, isNull);
    expect(r.anySucceeded, isFalse);
  });
}
