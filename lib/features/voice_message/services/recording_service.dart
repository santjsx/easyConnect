import 'dart:io';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/services/tts_service.dart';

class RecordingState {
  final bool isRecording;
  final String? recordingPath;

  RecordingState({
    this.isRecording = false,
    this.recordingPath,
  });

  RecordingState copyWith({
    bool? isRecording,
    String? recordingPath,
  }) {
    return RecordingState(
      isRecording: isRecording ?? this.isRecording,
      recordingPath: recordingPath ?? this.recordingPath,
    );
  }
}

class RecordingService extends StateNotifier<RecordingState> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final TTSService _ttsService;

  RecordingService(this._ttsService) : super(RecordingState());

  Future<String?> startRecording() async {
    try {
      // 1. Check and request Permission.microphone
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        status = await Permission.microphone.request();
      }
      if (!status.isGranted) {
        return null;
      }

      // Cleanup old easyconnect recording files from previous sessions asynchronously
      try {
        final tempDir = await getTemporaryDirectory();
        await tempDir.list().forEach((entity) async {
          if (entity is File && entity.path.contains('easyconnect_msg_')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        });
      } catch (e) {
        debugPrint('Error cleaning up temp recording files: $e');
      }

      // 2. Generate a temp file path in the app's temp directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '${tempDir.path}/easyconnect_msg_$timestamp.m4a';

      // 3. Start recording using the record package with AudioEncoder.aacLc, 44100 Hz
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
      );
      await _audioRecorder.start(config, path: path);

      // 4. Set isRecording = true
      state = RecordingState(isRecording: true, recordingPath: path);

      return path;
    } catch (e) {
      debugPrint('Error in RecordingService.startRecording: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (!state.isRecording) return null;

    try {
      // 1. Stop the recording
      final path = await _audioRecorder.stop();

      // 2. Set isRecording = false
      state = RecordingState(isRecording: false, recordingPath: path);

      if (path == null) return null;

      // 3. Validate the file exists and is > 0 bytes; if not, return null
      final file = File(path);
      if (await file.exists() && await file.length() > 0) {
        return path;
      }
      return null;
    } catch (e) {
      debugPrint('Error in RecordingService.stopRecording: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
      state = RecordingState(isRecording: false, recordingPath: null);
      return null;
    }
  }

  Future<void> deleteRecording(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
      if (state.recordingPath == path) {
        state = RecordingState(isRecording: false, recordingPath: null);
      }
    } catch (e) {
      debugPrint('Error in RecordingService.deleteRecording: $e');
      await _ttsService.speak("Something went wrong. Please try again.");
    }
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }
}

final recordingServiceProvider = StateNotifierProvider<RecordingService, RecordingState>((ref) {
  final ttsService = ref.watch(ttsServiceProvider);
  return RecordingService(ttsService);
});
