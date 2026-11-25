import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:situationship/core/ai/local_llm/model_spec.dart';

enum ModelDownloadStatus {
  notDownloaded,
  checking,
  downloading,
  verifying,
  ready,
  error,
}

class ModelDownloadState {
  final ModelSpec spec;
  final ModelDownloadStatus status;
  final double progress; // 0.0 to 1.0
  final int bytesDownloaded;
  final int totalBytes;
  final String? localPath;
  final String? errorMessage;

  const ModelDownloadState({
    required this.spec,
    required this.status,
    this.progress = 0.0,
    this.bytesDownloaded = 0,
    this.totalBytes = 0,
    this.localPath,
    this.errorMessage,
  });

  ModelDownloadState copyWith({
    ModelSpec? spec,
    ModelDownloadStatus? status,
    double? progress,
    int? bytesDownloaded,
    int? totalBytes,
    String? localPath,
    String? errorMessage,
  }) {
    return ModelDownloadState(
      spec: spec ?? this.spec,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      totalBytes: totalBytes ?? this.totalBytes,
      localPath: localPath ?? this.localPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Manages on-device model downloading, streaming SHA-256 verification, and private storage.
class LocalModelManager {
  static final LocalModelManager _instance = LocalModelManager._internal();
  factory LocalModelManager() => _instance;
  LocalModelManager._internal();

  final _stateController = StreamController<ModelDownloadState>.broadcast();
  Stream<ModelDownloadState> get stateStream => _stateController.stream;

  ModelDownloadState _currentState = const ModelDownloadState(
    spec: ModelSpec.smollm2_135m,
    status: ModelDownloadStatus.notDownloaded,
  );

  ModelDownloadState get currentState => _currentState;

  /// Returns the private application directory for storing LLM weight files
  Future<Directory> getModelStorageDirectory() async {
    if (kIsWeb) {
      throw UnsupportedError('Local filesystem paths are not available on Flutter Web. Use Web Storage.');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory(p.join(appDir.path, 'cupid_models'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    return modelDir;
  }

  /// Resolves the absolute local file path for a model spec
  Future<String> getModelPath(ModelSpec spec) async {
    final dir = await getModelStorageDirectory();
    final fileName = '${spec.id}_${spec.quantization}.gguf';
    return p.join(dir.path, fileName);
  }

  /// Checks if a model is downloaded and has verified integrity
  Future<bool> isModelReady(ModelSpec spec) async {
    if (kIsWeb) return false;
    try {
      final path = await getModelPath(spec);
      final file = File(path);
      if (!await file.exists()) {
        return false;
      }
      final size = await file.length();
      // Fast check: verify size matches expected spec size
      return size == spec.sizeBytes;
    } on Exception {
      return false;
    }
  }

  /// Verifies SHA-256 cryptographic checksum of a local model file
  Future<bool> verifyIntegrity(File file, String expectedSha256) async {
    if (!await file.exists()) return false;
    final digest = await sha256.bind(file.openRead()).first;
    final actual = digest.toString().toLowerCase();
    return actual == expectedSha256.toLowerCase();
  }

  /// Downloads model weights with progress reporting and atomic SHA-256 verification
  Future<File> downloadModel(
    ModelSpec spec, {
    void Function(double progress, int received, int total)? onProgress,
  }) async {
    final targetPath = await getModelPath(spec);
    final targetFile = File(targetPath);

    // If already downloaded and valid, return immediately
    if (await isModelReady(spec)) {
      _updateState(ModelDownloadState(
        spec: spec,
        status: ModelDownloadStatus.ready,
        progress: 1.0,
        bytesDownloaded: spec.sizeBytes,
        totalBytes: spec.sizeBytes,
        localPath: targetPath,
      ));
      return targetFile;
    }

    _updateState(ModelDownloadState(
      spec: spec,
      status: ModelDownloadStatus.downloading,
      progress: 0.0,
      totalBytes: spec.sizeBytes,
    ));

    final tempFile = File('$targetPath.tmp');
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    http.Client? client;
    IOSink? sink;

    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(spec.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Download failed with HTTP status ${response.statusCode}: ${response.reasonPhrase}');
      }

      final totalBytes = response.contentLength ?? spec.sizeBytes;
      sink = tempFile.openWrite();
      var receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final progress = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

        _updateState(_currentState.copyWith(
          progress: progress,
          bytesDownloaded: receivedBytes,
          totalBytes: totalBytes,
        ));

        onProgress?.call(progress, receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // ── Integrity Verification ─────────────────────────────────────────────
      _updateState(_currentState.copyWith(
        status: ModelDownloadStatus.verifying,
        progress: 1.0,
      ));

      final isValid = await verifyIntegrity(tempFile, spec.sha256Checksum);
      if (!isValid) {
        await tempFile.delete();
        throw Exception(
          'Integrity verification failed for ${spec.name}. Checksum mismatch detected. The download may be corrupted.',
        );
      }

      // Atomic rename from .tmp to final path
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetPath);

      _updateState(ModelDownloadState(
        spec: spec,
        status: ModelDownloadStatus.ready,
        progress: 1.0,
        bytesDownloaded: spec.sizeBytes,
        totalBytes: spec.sizeBytes,
        localPath: targetPath,
      ));

      return targetFile;
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (_) {}
      }

      _updateState(ModelDownloadState(
        spec: spec,
        status: ModelDownloadStatus.error,
        errorMessage: e.toString(),
      ));
      rethrow;
    } finally {
      await sink?.close();
      client?.close();
    }
  }

  /// Deletes a locally downloaded model to reclaim private device storage
  Future<void> deleteModel(ModelSpec spec) async {
    final path = await getModelPath(spec);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _updateState(ModelDownloadState(
      spec: spec,
      status: ModelDownloadStatus.notDownloaded,
    ));
  }

  void _updateState(ModelDownloadState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
  }
}
