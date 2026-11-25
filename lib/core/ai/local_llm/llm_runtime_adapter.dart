import 'dart:async';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

/// Abstract adapter for on-device language model inference engines.
/// Encapsulates platform-specific implementations (Android Native Platform Channel, Web WebGPU/Wasm, Local Host).
abstract class ModelRuntimeAdapter {
  ModelSpec? get loadedSpec;
  bool get isModelLoaded;

  /// Loads model weights into memory and prepares KV-cache
  Future<void> initialize({
    required ModelSpec spec,
    required String modelFilePath,
  });

  /// Streams generated tokens one by one as they are sampled
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  });

  /// Generates the complete response string asynchronously
  Future<String> generate(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async {
    final buffer = StringBuffer();
    await for (final token in generateStreaming(
      prompt,
      maxTokens: maxTokens,
      temperature: temperature,
      stopSequences: stopSequences,
    )) {
      buffer.write(token);
    }
    return buffer.toString();
  }

  /// Frees memory allocated by model weights and context
  Future<void> unload();
}
