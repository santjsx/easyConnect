import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/voice_message/services/recording_service.dart';
import 'package:easyconnect/features/voice_message/services/share_service.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/core/constants/app_dimensions.dart';

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

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.overlayState;
    if (state.flowState == OverlayFlowState.closed) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Material(
        color: Colors.black87,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildOverlayContent(context, state),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlayContent(BuildContext context, VoiceMessageOverlayState state) {
    switch (state.flowState) {
      case OverlayFlowState.recording:
        return _buildRecordingState(context, state);
      case OverlayFlowState.preview:
        return _buildPreviewState(context, state);
      case OverlayFlowState.sending:
        return _buildSendingState(context, state);
      case OverlayFlowState.closed:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRecordingState(BuildContext context, VoiceMessageOverlayState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 48.0),
        
        // Recording text
        const Text(
          'Recording...',
          style: TextStyle(
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
            child: const Text(
              'STOP',
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewState(BuildContext context, VoiceMessageOverlayState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(height: 48.0),
        
        // Spoken check text
        const Text(
          'Message recorded',
          style: TextStyle(
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
            
            // Large Play Button
            IconButton(
              iconSize: 80.0,
              icon: const Icon(
                Icons.play_circle_fill,
                color: Colors.grey,
              ),
              onPressed: () async {
                if (state.localFilePath != null) {
                  final Uri fileUri = Uri.file(state.localFilePath!);
                  if (await canLaunchUrl(fileUri)) {
                    await launchUrl(fileUri);
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
                    if (state.localFilePath != null) {
                      await ref.read(recordingServiceProvider.notifier).deleteRecording(state.localFilePath!);
                    }
                    ref.read(voiceMessageOverlayProvider.notifier).close();
                  },
                  child: const Text(
                    'DELETE',
                    style: TextStyle(
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
                    if (state.localFilePath != null && state.activeContact != null) {
                      ref.read(voiceMessageOverlayProvider.notifier).setSending();
                      await ref.read(shareServiceProvider).sendVoiceMessage(
                        state.localFilePath!,
                        state.activeContact!,
                      );
                    }
                    ref.read(voiceMessageOverlayProvider.notifier).close();
                  },
                  child: const Text(
                    'SEND',
                    style: TextStyle(
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

  Widget _buildSendingState(BuildContext context, VoiceMessageOverlayState state) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: kCallGreen,
          ),
          SizedBox(height: 24.0),
          Text(
            'Opening WhatsApp...',
            style: TextStyle(
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
