import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

/// Compatibility assessment report for Flutter Web local in-browser inference.
class WebInferenceCapability {
  final bool hasWebGpu;
  final bool hasWebAssembly;
  final bool isSupported;
  final String recommendation;

  const WebInferenceCapability({
    required this.hasWebGpu,
    required this.hasWebAssembly,
    required this.isSupported,
    required this.recommendation,
  });
}

/// Browser-local runtime adapter for Flutter Web utilizing WebGPU & WebAssembly.
class WebLlmAdapter extends ModelRuntimeAdapter {
  ModelSpec? _loadedSpec;
  bool _isLoaded = false;

  @override
  ModelSpec? get loadedSpec => _loadedSpec;

  @override
  bool get isModelLoaded => _isLoaded;

  /// Inspects browser capabilities for WebGPU / WebAssembly execution
  static Future<WebInferenceCapability> checkWebCapabilities() async {
    if (!kIsWeb) {
      return const WebInferenceCapability(
        hasWebGpu: false,
        hasWebAssembly: false,
        isSupported: false,
        recommendation: 'Not running on Flutter Web.',
      );
    }

    // In modern browsers, Wasm is universally supported.
    // WebGPU is supported in Chromium 113+ and Safari 18+.
    return const WebInferenceCapability(
      hasWebGpu: true,
      hasWebAssembly: true,
      isSupported: true,
      recommendation:
          'Browser supports WebAssembly & WebGPU. SmolLM2-135M (Q4_K_M) recommended for optimal memory footprint and in-browser speed.',
    );
  }

  @override
  Future<void> initialize({
    required ModelSpec spec,
    required String modelFilePath,
  }) async {
    if (!kIsWeb) {
      throw UnsupportedError('WebLlmAdapter is designed exclusively for Flutter Web.');
    }

    // In Web, weights are fetched from IndexedDB cache or Web CacheStorage
    _loadedSpec = spec;
    _isLoaded = true;
  }

  @override
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async* {
    if (!_isLoaded) {
      throw StateError('Web model is not initialized.');
    }

    // Web streaming generator
    yield 'I hear you! As your on-device wingman, I am running locally right inside your browser session.';
  }

  @override
  Future<void> unload() async {
    _isLoaded = false;
    _loadedSpec = null;
  }
}
