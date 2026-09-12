import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dart_agent_core/dart_agent_core.dart';
import 'package:dio/io.dart';
import 'package:logging/logging.dart';

const _codexAllowedKeys = {
  'model',
  'input',
  'instructions',
  'tools',
  'tool_choice',
  'stream',
  'store',
  'temperature',
  'top_p',
  'reasoning',
  'truncation',
};

class CodexResponsesClient extends LLMClient {
  final Logger _logger = Logger('CodexResponsesClient');
  final String accessToken;
  final String? accountId;
  final String baseUrl;
  final Dio _client;
  final Duration timeout;
  final Duration connectTimeout;
  final String? proxyUrl;
  final int maxRetries;
  final int initialRetryDelayMs;
  final int maxRetryDelayMs;

  CodexResponsesClient({
    required this.accessToken,
    this.accountId,
    this.baseUrl = 'https://chatgpt.com/backend-api/codex',
    this.timeout = const Duration(seconds: 300),
    this.connectTimeout = const Duration(seconds: 60),
    this.proxyUrl,
    this.maxRetries = 3,
    this.initialRetryDelayMs = 1000,
    this.maxRetryDelayMs = 10000,
    Dio? client,
  }) : _client = client ?? Dio() {
    configureProxy(_client, proxyUrl);
    _client.options.connectTimeout = connectTimeout;
  }

  Map<String, String> _buildHeaders() {
    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
      'originator': 'memex',
      'User-Agent': 'memex/0.0.1 (darwin 24.3.0; arm64)',
    };
    if (accountId != null) {
      headers['ChatGPT-Account-Id'] = accountId!;
    }
    return headers;
  }

  @override
  Future<ModelMessage> generate(
    List<LLMMessage> messages, {
    List<Tool>? tools,
    ToolChoice? toolChoice,
    required ModelConfig modelConfig,
    bool? jsonOutput,
    CancelToken? cancelToken,
  }) async {
    // Codex only supports streaming. Aggregate stream chunks into one ModelMessage.
    var aggregatedText = StringBuffer();
    var aggregatedThought = StringBuffer();
    final functionCalls = <FunctionCall>[];
    final audioOutputs = <ModelAudioPart>[];
    ModelUsage? finalUsage;
    String? finalStopReason;
    String? finalResponseId;
    Map<String, dynamic>? finalMetadata;

    var streamResp = await stream(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      jsonOutput: jsonOutput,
      cancelToken: cancelToken,
    );

    await for (final msg in streamResp) {
      final chunk = msg.modelMessage;
      if (chunk == null) continue;

      if (chunk.textOutput != null && chunk.textOutput!.isNotEmpty) {
        aggregatedText.write(chunk.textOutput!);
      }
      if (chunk.thought != null && chunk.thought!.isNotEmpty) {
        aggregatedThought.write(chunk.thought!);
      }
      if (chunk.functionCalls.isNotEmpty) {
        functionCalls.addAll(chunk.functionCalls);
      }
      if (chunk.audioOutputs.isNotEmpty) {
        audioOutputs.addAll(chunk.audioOutputs);
      }
      if (chunk.usage != null) {
        finalUsage = chunk.usage;
      }
      if (chunk.stopReason != null) {
        finalStopReason = chunk.stopReason;
      }
      if (chunk.responseId != null) {
        finalResponseId = chunk.responseId;
      }
      if (chunk.metadata != null) {
        finalMetadata = chunk.metadata;
      }
    }

    return ModelMessage(
      textOutput: aggregatedText.isEmpty ? null : aggregatedText.toString(),
      thought: aggregatedThought.isEmpty ? null : aggregatedThought.toString(),
      functionCalls: functionCalls.isEmpty ? [] : functionCalls,
      audioOutputs: audioOutputs,
      usage: finalUsage,
      model: modelConfig.model,
      responseId: finalResponseId,
      stopReason: finalStopReason,
      metadata: finalMetadata,
    );
  }

  /// Check if a responseId is valid by making a GET request
  Future<bool> checkResponseId(String responseId) async {
    // Codex doesn't support previous_response_id, always return False
    return false;
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
    final url = '$baseUrl/responses';
    final body = _createRequestBody(
      messages,
      tools: tools,
      toolChoice: toolChoice,
      modelConfig: modelConfig,
      stream: true,
      jsonOutput: jsonOutput,
    );

    StreamController<StreamingMessage> controller =
        StreamController<StreamingMessage>();
    int retryCount = 0;
    int currentDelayMs = initialRetryDelayMs;

    Future<void> waitForRetry(String reason) async {
      _logger.warning(
        'Codex stream: $reason. Retrying in ${currentDelayMs}ms... (Attempt ${retryCount + 1}/$maxRetries)',
      );
      await Future.delayed(Duration(milliseconds: currentDelayMs));
      retryCount++;
      currentDelayMs = (currentDelayMs * 2);
      if (currentDelayMs > maxRetryDelayMs) {
        currentDelayMs = maxRetryDelayMs;
      }
    }

    void pumpStream() async {
      while (true) {
        try {
          if (cancelToken != null && cancelToken.isCancelled) {
            throw Exception('Cancelled');
          }

          _logger.info(
            'Codex stream request, model: ${modelConfig.model}, messages: ${messages.length}, tools: ${tools?.length ?? 0}',
          );
          final startTime = DateTime.now();

          final response = await _client.post(
            url,
            data: body,
            options: Options(
              responseType: ResponseType.stream,
              sendTimeout: timeout,
              receiveTimeout: timeout,
              headers: _buildHeaders(),
              validateStatus: (code) => true,
            ),
            cancelToken: cancelToken,
          );
          final endTime = DateTime.now();

          _logger.info(
            'Codex stream response: ${response.statusCode}, ${endTime.difference(startTime).inMilliseconds}ms',
          );

          if (response.statusCode != 200) {
            if (response.statusCode != null &&
                (response.statusCode == 429 || response.statusCode! >= 500)) {
              if (retryCount < maxRetries) {
                await waitForRetry(
                  'status ${response.statusCode}',
                );
                controller.add(
                  StreamingMessage(
                    controlMessage: StreamingControlMessage(
                      controlFlag: StreamingControlFlag.retry,
                      data: {
                        'retryReason': 'status ${response.statusCode}',
                      },
                    ),
                  ),
                );
                continue;
              }
            }

            final responseBodyBytes = <int>[];
            await for (var chunk
                in (response.data.stream as Stream).cast<List<int>>()) {
              responseBodyBytes.addAll(chunk);
            }
            final responseBody =
                utf8.decode(responseBodyBytes, allowMalformed: true);

            throw Exception(
              'Codex API error: ${response.statusCode} ${response.statusMessage} $responseBody',
            );
          }

          final stream = (response.data.stream as Stream).cast<List<int>>();

          final transformedStream = stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .transform(ResponsesChunkDecoder())
              .transform(ResponsesAPIResponseTransformer(modelConfig))
              .map((chunk) => StreamingMessage(modelMessage: chunk));

          await for (final message in transformedStream) {
            controller.add(message);
          }

          controller.close();
          break; // success — exit retry loop
        } on DioException catch (e) {
          if (retryCount < maxRetries) {
            await waitForRetry('Exception: ${e.message}');
            controller.add(
              StreamingMessage(
                controlMessage: StreamingControlMessage(
                  controlFlag: StreamingControlFlag.retry,
                  data: {'retryReason': 'Exception: ${e.message}'},
                ),
              ),
            );
            continue;
          }
          controller.addError(e);
          controller.close();
          break;
        } catch (e) {
          if (retryCount < maxRetries) {
            await waitForRetry('Exception: $e');
            controller.add(
              StreamingMessage(
                controlMessage: StreamingControlMessage(
                  controlFlag: StreamingControlFlag.retry,
                  data: {'retryReason': 'Exception: $e'},
                ),
              ),
            );
            continue;
          }
          controller.addError(e);
          controller.close();
          break;
        }
      }
    }

    pumpStream();
    return controller.stream;
  }
}

// ----------------------------------------------------------------------
// Request Body & Parsing Logic
// ----------------------------------------------------------------------

Map<String, dynamic> _createRequestBody(
  List<LLMMessage> messages, {
  List<Tool>? tools,
  ToolChoice? toolChoice,
  required ModelConfig modelConfig,
  bool stream = false,
  bool? jsonOutput,
}) {
  final inputList = <Map<String, dynamic>>[];
  final instructionsParts = <String>[];

  for (final m in messages) {
    if (m is SystemMessage) {
      // Codex requires system content as top-level "instructions",
      // not inside the input array.
      instructionsParts.add(m.content);
    } else if (m is UserMessage) {
      final contentList = <Map<String, dynamic>>[];
      for (final part in m.contents) {
        if (part is TextPart) {
          contentList.add({'type': 'input_text', 'text': part.text});
        } else if (part is ImagePart) {
          contentList.add({
            'type': 'input_image',
            'image_url': _convertBase64ToUrl(part.base64Data, part.mimeType),
            if (part.detail != null) 'detail': part.detail,
          });
        } else if (part is AudioPart) {
          String format = 'wav';
          if (part.mimeType.toLowerCase().contains('mp3') ||
              part.mimeType.toLowerCase().contains('mpeg')) {
            format = 'mp3';
          }
          contentList.add({
            'type': 'input_audio',
            'input_audio': {'data': part.base64Data, 'format': format},
          });
        }
      }
      if (contentList.isNotEmpty) {
        inputList.add({
          'type': 'message',
          'role': 'user',
          'content': contentList,
        });
      }
    } else if (m is ModelMessage) {
      final contentList = <Map<String, dynamic>>[];
      if (m.textOutput != null && m.textOutput!.isNotEmpty) {
        contentList.add({'type': 'output_text', 'text': m.textOutput});
      }

      if (contentList.isNotEmpty) {
        inputList.add({
          'type': 'message',
          'role': 'assistant',
          'content': contentList,
          'status': 'completed',
        });
      }

      // Handle Tool Calls from ModelMessage
      for (final fc in m.functionCalls) {
        inputList.add({
          'type': 'function_call',
          'call_id': fc.id,
          'name': fc.name,
          'arguments':
              fc.arguments is Map ? jsonEncode(fc.arguments) : fc.arguments,
        });
      }
    } else if (m is FunctionExecutionResultMessage) {
      for (final res in m.results) {
        final textParts = <String>[];

        for (final part in res.content) {
          if (part is TextPart) {
            textParts.add(part.text);
          }
        }

        final textContent = textParts.join('\n');
        inputList.add({
          'type': 'function_call_output',
          'call_id': res.id,
          'output': textContent,
        });
      }
    }
  }

  final Map<String, dynamic> body = {
    'model': modelConfig.model,
    'stream': stream,
    'store': false,
    'instructions': instructionsParts.isNotEmpty
        ? instructionsParts.join('\n\n')
        : 'You are a helpful assistant.',
  };

  if (inputList.isNotEmpty) {
    body['input'] = inputList;
  }

  // Tools (always sent — Codex has no server-side memory)
  if (tools != null && tools.isNotEmpty) {
    body['tools'] = tools
        .map(
          (t) => {
            'type': 'function',
            'name': t.name,
            'description': t.description,
            'parameters': t.parameters,
          },
        )
        .toList();

    if (toolChoice != null) {
      if (toolChoice.allowedFunctionNames != null &&
          toolChoice.allowedFunctionNames!.isNotEmpty) {
        if (toolChoice.mode == ToolChoiceMode.required &&
            toolChoice.allowedFunctionNames!.length == 1) {
          body['tool_choice'] = {
            'type': 'function',
            'name': toolChoice.allowedFunctionNames!.first,
          };
        } else {
          body['tool_choice'] = 'auto'; // Codex uses simple auto here
        }
      } else {
        switch (toolChoice.mode) {
          case ToolChoiceMode.none:
            body['tool_choice'] = 'none';
            break;
          case ToolChoiceMode.auto:
            body['tool_choice'] = 'auto';
            break;
          case ToolChoiceMode.required:
            body['tool_choice'] = 'required';
            break;
        }
      }
    }
  }

  if (modelConfig.temperature != null) {
    body['temperature'] = modelConfig.temperature;
  }
  if (modelConfig.topP != null) {
    body['top_p'] = modelConfig.topP;
  }

  // Extra params (only Codex-supported ones)
  if (modelConfig.extra != null) {
    for (final key in const ['reasoning', 'truncation']) {
      if (modelConfig.extra!.containsKey(key)) {
        body[key] = modelConfig.extra![key];
      }
    }
  }

  // Final whitelist pass
  body.removeWhere((key, value) => !_codexAllowedKeys.contains(key));

  return body;
}

// ----------------------------------------------------------------------
// Stream Transformer (SSE)
// ----------------------------------------------------------------------

class ResponsesChunkDecoder
    extends StreamTransformerBase<String, Map<String, dynamic>> {
  @override
  Stream<Map<String, dynamic>> bind(Stream<String> stream) async* {
    await for (final line in stream) {
      if (line.startsWith('data: ')) {
        final data = line.substring(6).trim();
        if (data == '[DONE]') return;
        try {
          yield jsonDecode(data);
        } catch (e) {
          // ignore
        }
      }
    }
  }
}

class ResponsesAPIResponseTransformer
    extends StreamTransformerBase<Map<String, dynamic>, ModelMessage> {
  final ModelConfig modelConfig;

  ResponsesAPIResponseTransformer(this.modelConfig);

  @override
  Stream<ModelMessage> bind(Stream<Map<String, dynamic>> stream) async* {
    final Map<String, ButtonToolCallBuffer> toolBuffers = {};

    await for (final event in stream) {
      final type = event['type'] as String?;
      final model = modelConfig.model;

      if (type == 'response.completed') {
        final response = event['response'];
        if (response != null && response['usage'] != null) {
          final u = response['usage'];
          final usage = ModelUsage(
            promptTokens: u['input_tokens'] ?? 0,
            completionTokens: u['output_tokens'] ?? 0,
            totalTokens: u['total_tokens'] ?? 0,
            cachedToken: u['input_tokens_details']?['cached_tokens'] ?? 0,
            thoughtToken: u['output_tokens_details']?['reasoning_tokens'] ?? 0,
            model: model,
            originalUsage: u,
          );
          yield ModelMessage(
            usage: usage,
            model: model,
            responseId: response['id'],
            stopReason: response['incomplete_details'] != null
                ? 'incomplete'
                : 'end_turn',
            metadata: {'status': 'completed'},
          );
        }
      }

      if (type == 'response.failed') {
        final error = event['error'];
        throw Exception(
          'Codex response failed: [${error?['code']}] ${error?['message']}',
        );
      }

      if (type == 'response.incomplete') {
        yield ModelMessage(
          stopReason: 'incomplete',
          model: model,
          metadata: {'status': 'incomplete'},
        );
      }

      // Output Items
      if (type == 'response.output_item.added') {
        final item = event['item'];
        if (item != null) {
          final itemId = item['id'];
          final itemType = item['type'];

          if (itemType == 'function_call') {
            toolBuffers[itemId ?? ''] = ButtonToolCallBuffer(
              id: item['call_id'] ?? item['id'] ?? '',
              name: item['name'] ?? item['function']?['name'] ?? '',
              arguments: '',
            );
          }
        }
      }

      if (type == 'response.function_call_arguments.delta') {
        final itemId = event['item_id'] as String?;
        final delta = event['delta'] as String?;

        if (itemId != null && toolBuffers.containsKey(itemId)) {
          toolBuffers[itemId]!.arguments += (delta ?? '');
        }
      }

      if (type == 'response.output_item.done') {
        final item = event['item'];
        if (item != null) {
          final itemId = item['id'] ?? '';
          final itemType = item['type'];

          if (itemType == 'function_call') {
            final buffer = toolBuffers.remove(itemId);

            final callId = buffer?.id ?? item['call_id'] ?? itemId;
            final name = buffer?.name ?? item['name'] ?? '';
            final args = (buffer != null && buffer.arguments.isNotEmpty)
                ? buffer.arguments
                : (item['arguments'] ?? '');

            yield ModelMessage(
              functionCalls: [
                FunctionCall(
                  id: callId,
                  name: name,
                  arguments: args,
                ),
              ],
              model: model,
            );
          }
        }
      }

      // Text Generation
      if (type == 'response.output_text.delta') {
        final delta = event['delta'] as String?;
        if (delta != null) {
          yield ModelMessage(textOutput: delta, model: model);
        }
      }

      // Reasoning
      if (type == 'response.reasoning_summary_text.delta') {
        final delta = event['delta'] as String?;
        if (delta != null) {
          yield ModelMessage(thought: delta, model: model);
        }
      }

      if (type == 'response.reasoning_summary_text.done') {
        final text = event['text'] as String?;
        if (text != null) {
          yield ModelMessage(thought: text, model: model);
        }
      }

      // Safety & Errors
      if (type == 'response.refusal.delta') {
        final delta = event['delta'] as String?;
        if (delta != null) {
          yield ModelMessage(
            textOutput: delta,
            model: model,
            metadata: {'isRefusal': true},
          );
        }
      }

      if (type == 'error') {
        final code = event['code'];
        final message = event['message'];
        throw Exception('Codex stream error: [$code] $message');
      }

      // Audio
      if (type == 'response.audio.delta') {
        final delta = event['delta'] as String?;
        if (delta != null) {
          yield ModelMessage(
            audioOutputs: [
              ModelAudioPart(base64Data: delta, mimeType: 'audio/pcm'),
            ],
            model: model,
          );
        }
      }
    }
  }
}

class ButtonToolCallBuffer {
  String id;
  String name;
  String arguments;
  ButtonToolCallBuffer({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

String _convertBase64ToUrl(String base64Data, String mimeType) {
  if (base64Data.startsWith("data")) {
    return base64Data;
  }
  return 'data:$mimeType;base64,$base64Data';
}

void configureProxy(Dio client, String? proxyUrl) {
  if (proxyUrl != null) {
    (client.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final httpClient = HttpClient();
      final uri = Uri.parse(proxyUrl);

      httpClient.findProxy = (url) {
        return "PROXY ${uri.host}:${uri.port}";
      };

      if (uri.userInfo.isNotEmpty) {
        final parts = uri.userInfo.split(':');
        if (parts.length == 2) {
          final user = parts[0];
          final pass = parts[1];
          httpClient.addProxyCredentials(
            uri.host,
            uri.port,
            '',
            HttpClientBasicCredentials(user, pass),
          );
          httpClient.authenticateProxy =
              (host, port, scheme, realm) async => true;
        }
      }
      return httpClient;
    };
  }
}
