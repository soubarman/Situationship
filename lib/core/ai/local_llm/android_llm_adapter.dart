import 'dart:async';
import 'package:flutter/services.dart';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

/// Android Native Platform Channel adapter for LiteRT-LM / llama.cpp on-device execution.
class AndroidLlmAdapter extends ModelRuntimeAdapter {
  static const MethodChannel _methodChannel = MethodChannel('com.situationship/cupid_local_ai');
  static const EventChannel _eventChannel = EventChannel('com.situationship/cupid_local_ai/stream');

  ModelSpec? _loadedSpec;
  bool _isLoaded = false;

  @override
  ModelSpec? get loadedSpec => _loadedSpec;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> initialize({
    required ModelSpec spec,
    required String modelFilePath,
  }) async {
    try {
      final bool success = await _methodChannel.invokeMethod('loadModel', {
        'modelId': spec.id,
        'modelPath': modelFilePath,
        'contextLength': spec.contextLength,
        'threads': 4,
      });

      if (success) {
        _loadedSpec = spec;
        _isLoaded = true;
      } else {
        throw Exception('Native Android runtime failed to load model at $modelFilePath');
      }
    } on PlatformException catch (e) {
      throw Exception('Android on-device runtime error: ${e.message} (code: ${e.code})');
    }
  }

  @override
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async* {
    if (!_isLoaded) {
      throw StateError('Model is not initialized. Call initialize() first.');
    }

    final controller = StreamController<String>();

    // Start generation on native platform
    _methodChannel.invokeMethod('startInference', {
      'prompt': prompt,
      'maxTokens': maxTokens,
      'temperature': temperature,
      'stopSequences': stopSequences,
    }).catchError((err) {
      controller.addError(err);
    });

    // Listen to token stream from native event channel
    final subscription = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map && data.containsKey('token')) {
          final token = data['token'] as String;
          controller.add(token);
        } else if (data is String) {
          controller.add(data);
        }
      },
      onError: (err) => controller.addError(err),
      onDone: () => controller.close(),
    );

    try {
      yield* controller.stream;
    } finally {
      await subscription.cancel();
      await controller.close();
    }
  }

  @override
  Future<void> unload() async {
    if (!_isLoaded) return;
    try {
      await _methodChannel.invokeMethod('unloadModel');
    } finally {
      _isLoaded = false;
      _loadedSpec = null;
    }
  }

  /// Inspects live Android native RAM metrics
  static Future<Map<String, dynamic>> getNativeMemoryInfo() async {
    try {
      final res = await _methodChannel.invokeMapMethod<String, dynamic>('getMemoryMetrics');
      return res ?? const {};
    } catch (_) {
      return const {};
    }
  }

  /// Checks whether native C++ llama library is loaded and ready
  static Future<bool> isNativeRuntimeReady() async {
    try {
      final res = await _methodChannel.invokeMethod<bool>('isNativeRuntimeReady');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels in-progress native token inference
  Future<void> cancel() async {
    try {
      await _methodChannel.invokeMethod('cancelInference');
    } catch (_) {}
  }
}
