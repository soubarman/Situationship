import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:situationship/core/ai/local_llm/llm_runtime_adapter.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

/// Local Host / Desktop Process adapter for executing real on-device GGUF inference.
/// Uses native llama.cpp execution with direct streaming token capture.
class LocalProcessLlmAdapter extends ModelRuntimeAdapter {
  final String executablePath;
  ModelSpec? _loadedSpec;
  String? _modelPath;
  bool _isLoaded = false;

  LocalProcessLlmAdapter({this.executablePath = 'tools/llama/llama-completion.exe'});

  @override
  ModelSpec? get loadedSpec => _loadedSpec;

  @override
  bool get isModelLoaded => _isLoaded;

  @override
  Future<void> initialize({
    required ModelSpec spec,
    required String modelFilePath,
  }) async {
    final file = File(modelFilePath);
    if (!await file.exists()) {
      throw FileNotFoundException('Model file not found at $modelFilePath');
    }
    _loadedSpec = spec;
    _modelPath = modelFilePath;
    _isLoaded = true;
  }

  @override
  Stream<String> generateStreaming(
    String prompt, {
    int maxTokens = 256,
    double temperature = 0.7,
    List<String> stopSequences = const ['<|im_end|>', '<end_of_turn>', '<|eot_id|>'],
  }) async* {
    if (!_isLoaded || _modelPath == null) {
      throw StateError('Model is not initialized.');
    }

    final process = await Process.start(executablePath, [
      '-m',
      _modelPath!,
      '-p',
      prompt,
      '-n',
      maxTokens.toString(),
      '--temp',
      temperature.toString(),
      '-no-cnv',
    ]);

    // Stream lines and words from stdout
    final controller = StreamController<String>();

    process.stdout.transform(utf8.decoder).listen((data) {
      // llama.cpp outputs prompt then generated text
      controller.add(data);
    }, onError: (err) {
      controller.addError(err);
    }, onDone: () {
      controller.close();
    });

    try {
      var promptEchoSkipped = false;
      await for (final chunk in controller.stream) {
        if (!promptEchoSkipped) {
          // If the CLI echoed the prompt, find the assistant marker
          final assistantIdx = chunk.indexOf('assistant\n');
          if (assistantIdx != -1) {
            promptEchoSkipped = true;
            final remaining = chunk.substring(assistantIdx + 'assistant\n'.length);
            if (remaining.isNotEmpty) yield remaining;
          } else {
            yield chunk;
          }
        } else {
          yield chunk;
        }
      }
    } finally {
      process.kill();
    }
  }

  @override
  Future<void> unload() async {
    _isLoaded = false;
    _modelPath = null;
    _loadedSpec = null;
  }
}

class FileNotFoundException implements Exception {
  final String message;
  const FileNotFoundException(this.message);
  @override
  String toString() => 'FileNotFoundException: $message';
}
