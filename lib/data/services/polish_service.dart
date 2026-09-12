import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:memex/domain/models/agent_definitions.dart';
import 'package:memex/domain/models/llm_config.dart';
import 'package:memex/utils/user_storage.dart';

/// Result of polishing a fragment of text into two Chinese variants.
/// Either field may be `null` if that variant's generation failed — the
/// caller must degrade gracefully rather than treat this as an error.
class PolishResult {
  const PolishResult({this.plain, this.literary});

  /// Clear, plain-language ("通顺") rewrite.
  final String? plain;

  /// More literary ("文采") rewrite.
  final String? literary;

  bool get anySucceeded => plain != null || literary != null;
}

/// Generates two Chinese rewrites of the user's text in parallel — a plain
/// and a literary variant — for the journaling "polish" action. Mirrors
/// [QuickCaptureService]'s resource loading. Never throws: each variant
/// degrades to `null` on failure so the UI can still show whichever
/// succeeded.
class PolishService {
  PolishService._(this._resourcesProvider);

  factory PolishService() => PolishService._(null);

  factory PolishService.forTesting({
    required Future<({LLMClient client, ModelConfig modelConfig})> Function()
        resourcesProvider,
  }) =>
      PolishService._(resourcesProvider);

  static final PolishService instance = PolishService();

  final Future<({LLMClient client, ModelConfig modelConfig})> Function()?
      _resourcesProvider;

  static const _plainSys = '你是中文润色助手。把用户文字改写得通顺清晰,保持原意、原语言(中文),长度相近。'
      '不要翻译成其他语言,不要添加事实,不要加解释,直接输出改写后的文字。';
  static const _literarySys = '你是中文润色助手。把用户文字改写得更书面、有文采,可轻度扩写,'
      '但保持原意、原语言(中文),不虚构事实,不加解释,直接输出改写后的文字。';

  Future<({LLMClient client, ModelConfig modelConfig})> _loadResources() {
    final provider = _resourcesProvider;
    if (provider != null) return provider();
    // Same resolution as the chat agent, so polish always uses the model
    // the user configured for chat.
    return UserStorage.getAgentLLMResources(
      AgentDefinitions.chatAgent,
      defaultClientKey: LLMConfig.defaultClientKey,
    );
  }

  Future<String?> _one(
    String systemPrompt,
    String text,
    ({LLMClient client, ModelConfig modelConfig}) resources,
  ) async {
    try {
      final response = await resources.client.generate(
        [SystemMessage(systemPrompt), UserMessage([TextPart(text)])],
        modelConfig: resources.modelConfig,
      );
      final out = response.textOutput?.trim();
      return (out == null || out.isEmpty) ? null : out;
    } catch (_) {
      return null;
    }
  }

  /// Produces plain and literary rewrites of [text] in parallel. Never
  /// throws; a variant that fails or comes back empty is `null`.
  Future<PolishResult> polish(String text) async {
    final resources = await _loadResources();
    final results = await Future.wait([
      _one(_plainSys, text, resources),
      _one(_literarySys, text, resources),
    ]);
    return PolishResult(plain: results[0], literary: results[1]);
  }
}
