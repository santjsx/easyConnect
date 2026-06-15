import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/voice_message/services/recording_service.dart';
import 'package:easyconnect/features/voice_message/services/share_service.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

enum OverlayFlowState { recording, preview, sending, closed }

class VoiceMessageOverlayState {
  final OverlayFlowState flowState;
  final Contact? activeContact;
  final String? localFilePath;

  VoiceMessageOverlayState({
    this.flowState = OverlayFlowState.closed,
    this.activeContact,
    this.localFilePath,
  });
}

class VoiceMessageOverlayNotifier extends StateNotifier<VoiceMessageOverlayState> {
  VoiceMessageOverlayNotifier() : super(VoiceMessageOverlayState());

  void open(Contact contact) {
    state = VoiceMessageOverlayState(
      flowState: OverlayFlowState.recording,
      activeContact: contact,
    );
  }

  void setPreview(String path) {
    state = VoiceMessageOverlayState(
      flowState: OverlayFlowState.preview,
      activeContact: state.activeContact,
      localFilePath: path,
    );
  }

  void setSending({String? path}) {
    state = VoiceMessageOverlayState(
      flowState: OverlayFlowState.sending,
      activeContact: state.activeContact,
      localFilePath: path ?? state.localFilePath,
    );
  }

  void close() {
    state = VoiceMessageOverlayState(flowState: OverlayFlowState.closed);
  }
}

final voiceMessageOverlayProvider = StateNotifierProvider<VoiceMessageOverlayNotifier, VoiceMessageOverlayState>((ref) {
  return VoiceMessageOverlayNotifier();
});

class RecordingOverlay extends ConsumerStatefulWidget {
  final VoiceMessageOverlayState overlayState;

  const RecordingOverlay({super.key, required this.overlayState});

  @override
  ConsumerState<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends ConsumerState<RecordingOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _previewPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingPreview = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    try {
      _previewPlayer.stop();
    } catch (_) {}
    _previewPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.overlayState;
    if (state.flowState == OverlayFlowState.closed) {
      return const SizedBox.shrink();
    }

    final settingsAsync = ref.watch(settingsProvider);
    final language = settingsAsync.when(
      data: (settings) => settings.language,
      loading: () => 'en',
      error: (err, stack) => 'en',
    );

    return Positioned.fill(
      child: Material(
        color: Colors.black87,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildOverlayContent(context, state, language),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent(BuildContext context, VoiceMessageOverlayState state, String language) {
    switch (state.flowState) {
      case OverlayFlowState.recording:
        return _buildRecordingState(context, state, language);
      case OverlayFlowState.preview:
        return _buildPreviewState(context, state, language);
      case OverlayFlowState.sending:
        return _buildSendingState(context, state, language);
      case OverlayFlowState.closed:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRecordingState(BuildContext context, VoiceMessageOverlayState state, String language) {
    String titleText = 'Recording...';
    String stopText = 'STOP';

    if (language == 'te') {
      titleText = 'రికార్డ్ అవుతోంది...';
      stopText = 'ఆపు';
    } else if (language == 'hi') {
      titleText = 'रिकॉर्डिंग चालू है...';
      stopText = 'रोकें';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 48.0),
        
        // Recording text
        Text(
          titleText,
          style: const TextStyle(
            fontSize: 22.0,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        // Pulsing Circle in Center
        ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.1).animate(
            CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 140.0,
            height: 140.0,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red,
            ),
            child: const Icon(
              Icons.mic,
              size: 64.0,
              color: Colors.white,
            ),
          ),
        ),
        
        // Contact Name
        Text(
          state.activeContact?.name ?? '',
          style: const TextStyle(
            fontSize: 18.0,
            color: Colors.white70,
            fontWeight: FontWeight.w500,
          ),
        ),
        
        const SizedBox(height: 24.0),
        
        // STOP Button
        SizedBox(
          width: double.infinity,
          height: 72.0,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kCardBorderRadius),
              ),
            ),
            onPressed: () async {
              final path = await ref.read(recordingServiceProvider.notifier).stopRecording();
              if (path != null && state.activeContact != null) {
                ref.read(voiceMessageOverlayProvider.notifier).setSending(path: path);
                await ref.read(shareServiceProvider).sendVoiceMessage(
                  path,
                  state.activeContact!,
                );
              }
              ref.read(voiceMessageOverlayProvider.notifier).close();
            },
            child: Text(
              stopText,
              style: const TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewState(BuildContext context, VoiceMessageOverlayState state, String language) {
    String titleText = 'Message recorded';
    String deleteText = 'DELETE';
    String sendText = 'SEND';

    if (language == 'te') {
      titleText = 'రికార్డ్ అయ్యింది';
      deleteText = 'తొలగించు';
      sendText = 'పంపించు';
    } else if (language == 'hi') {
      titleText = 'रिकॉर्ड हो गया';
      deleteText = 'मिटाएं';
      sendText = 'भेजें';
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 48.0),
        
        // Spoken check text
        Text(
          titleText,
          style: const TextStyle(
            fontSize: 20.0,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        // Waveform Placeholder & Play Button
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // MVP Flat Waveform bar
            Container(
              width: double.infinity,
              height: 12.0,
              margin: const EdgeInsets.symmetric(horizontal: 24.0),
              decoration: BoxDecoration(
                color: kMessageOrange.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(6.0),
              ),
            ),
            const SizedBox(height: 24.0),
            
            // Large Play/Pause Button
            IconButton(
              iconSize: 80.0,
              icon: Icon(
                _isPlayingPreview ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: Colors.white70,
              ),
              onPressed: () async {
                if (state.localFilePath != null) {
                  if (_isPlayingPreview) {
                    await _previewPlayer.pause();
                    setState(() {
                      _isPlayingPreview = false;
                    });
                  } else {
                    await _previewPlayer.play(DeviceFileSource(state.localFilePath!));
                    setState(() {
                      _isPlayingPreview = true;
                    });
                  }
                }
              },
            ),
          ],
        ),
        
        // Spacer / layout balance
        const SizedBox(height: 48.0),
        
        // Delete & Send buttons row
        Row(
          children: [
            // DELETE Button
            Expanded(
              child: SizedBox(
                height: 72.0,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kStopRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kCardBorderRadius),
                    ),
                  ),
                  onPressed: () async {
                    await _previewPlayer.stop(); // Stop audio if deleting
                    if (state.localFilePath != null) {
                      await ref.read(recordingServiceProvider.notifier).deleteRecording(state.localFilePath!);
                    }
                    ref.read(voiceMessageOverlayProvider.notifier).close();
                  },
                  child: Text(
                    deleteText,
                    style: const TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16.0),
            
            // SEND Button
            Expanded(
              child: SizedBox(
                height: 72.0,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kCallGreen,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kCardBorderRadius),
                    ),
                  ),
                  onPressed: () async {
                    await _previewPlayer.stop(); // Stop audio if sending
                    if (state.localFilePath != null && state.activeContact != null) {
                      ref.read(voiceMessageOverlayProvider.notifier).setSending();
                      await ref.read(shareServiceProvider).sendVoiceMessage(
                        state.localFilePath!,
                        state.activeContact!,
                      );
                    }
                    ref.read(voiceMessageOverlayProvider.notifier).close();
                  },
                  child: Text(
                    sendText,
                    style: const TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSendingState(BuildContext context, VoiceMessageOverlayState state, String language) {
    String sendingText = 'Opening WhatsApp...';
    if (language == 'te') {
      sendingText = 'వాట్సాప్ తెరుస్తున్నా...';
    } else if (language == 'hi') {
      sendingText = 'व्हाट्सएप खुल रहा है...';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: kCallGreen,
          ),
          const SizedBox(height: 24.0),
          Text(
            sendingText,
            style: const TextStyle(
              fontSize: 20.0,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
