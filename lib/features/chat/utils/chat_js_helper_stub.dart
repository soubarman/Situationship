import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';

AudioRecorder? _nativeRecorder;
String? _currentNativePath;
VideoPlayerController? _nativePlayerController;

Future<bool> startJsRecording() async {
  try {
    _nativeRecorder ??= AudioRecorder();
    final hasPermission = await _nativeRecorder!.hasPermission();
    if (!hasPermission) {
      print('Native microphone permission denied');
      return false;
    }

    final tempDir = await getTemporaryDirectory();
    _currentNativePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _nativeRecorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _currentNativePath!,
    );
    return true;
  } catch (e) {
    print('Native start recording error: $e');
    return false;
  }
}

String? getJsRecordingError() => null;

Future<String?> stopJsRecording() async {
  try {
    if (_nativeRecorder == null) return null;
    final path = await _nativeRecorder!.stop();
    if (path == null) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final base64String = base64Encode(bytes);
    final dataUrl = 'data:audio/mp4;base64,$base64String';

    return jsonEncode({
      'dataUrl': dataUrl,
      'mimeType': 'audio/mp4',
      'filePath': path,
      'size': bytes.length,
    });
  } catch (e) {
    print('Native stop recording error: $e');
    return null;
  }
}

void playJsAudio(String url) async {
  try {
    await _nativePlayerController?.pause();
    await _nativePlayerController?.dispose();
    _nativePlayerController = null;

    if (url.startsWith('http://') || url.startsWith('https://')) {
      _nativePlayerController = VideoPlayerController.networkUrl(Uri.parse(url));
    } else if (url.startsWith('data:')) {
      final comma = url.indexOf(',');
      if (comma != -1) {
        final b64 = url.substring(comma + 1);
        final bytes = base64Decode(b64);
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/temp_chat_audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
        await tempFile.writeAsBytes(bytes);
        _nativePlayerController = VideoPlayerController.file(tempFile);
      }
    } else {
      _nativePlayerController = VideoPlayerController.file(File(url));
    }

    if (_nativePlayerController != null) {
      await _nativePlayerController!.initialize();
      await _nativePlayerController!.play();
    }
  } catch (e) {
    print('Native playJsAudio error: $e');
  }
}

void pauseJsAudio() async {
  try {
    await _nativePlayerController?.pause();
  } catch (e) {
    print('Native pauseJsAudio error: $e');
  }
}

void openJsUrl(String url) {}
