import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/services/audio_call_service.dart';
import 'package:easyconnect/features/calling/services/whatsapp_call_service.dart';
import 'package:easyconnect/features/voice_message/services/recording_service.dart';
import 'package:easyconnect/features/voice_message/widgets/recording_overlay.dart';
import 'package:easyconnect/services/tts_service.dart';

class PhotolessSelectionState {
  final String? contactId;
  final int lastTapTime;

  PhotolessSelectionState({this.contactId, this.lastTapTime = 0});
}

final photolessSelectionProvider = StateProvider<PhotolessSelectionState>((ref) {
  return PhotolessSelectionState();
});

class ContactCard extends ConsumerWidget {
  final Contact contact;

  const ContactCard({super.key, required this.contact});

  void _announceName(WidgetRef ref) async {
    final tts = ref.read(ttsServiceProvider);
    await tts.stop();

    final nameToSpeak = contact.name.trim();
    if (nameToSpeak.isEmpty) {
      // Empty contact name: Speak casual error phrase and reset selection (no call)
      await tts.speak("పేరు లేదు", forceLanguage: 'te');
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      return;
    }

    try {
      // Announce the name using warm natural Telugu pitch configurations
      await tts.speak(nameToSpeak, forceLanguage: 'te');
    } catch (e) {
      // Fallback: TTS engine failed / not initialized -> Buzz long-short-long tactile pattern
      await HapticFeedback.vibrate();
      await Future.delayed(const Duration(milliseconds: 200));
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      await HapticFeedback.vibrate();
    }
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;

    if (hasPhoto) {
      // Contact has photo -> immediately place the call
      ref.read(audioCallServiceProvider).makeCall(context, contact);
      return;
    }

    final selection = ref.read(photolessSelectionProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Check if double-tapped too fast (< 300ms)
    final isDoubleTapTooFast = selection.contactId == contact.id && (now - selection.lastTapTime < 300);

    if (isDoubleTapTooFast) {
      // Treat as single tap: announce name, do not call, update timestamp
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: contact.id,
        lastTapTime: now,
      );
      _announceName(ref);
      return;
    }

    if (selection.contactId == contact.id) {
      // Second tap: Confirm call placement and reset selection
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
      ref.read(audioCallServiceProvider).makeCall(context, contact);
    } else {
      // First tap or selection changed: Reset previous selection, start TTS name readout, and log active selection
      ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState(
        contactId: contact.id,
        lastTapTime: now,
      );
      _announceName(ref);

      // Auto-reset selection after 4 seconds of inactivity
      final currentId = contact.id;
      Future.delayed(const Duration(seconds: 4), () {
        final currentSelection = ref.read(photolessSelectionProvider);
        if (currentSelection.contactId == currentId) {
          ref.read(photolessSelectionProvider.notifier).state = PhotolessSelectionState();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;
    final selection = ref.watch(photolessSelectionProvider);
    final isSelected = selection.contactId == contact.id;

    // Glowing border ring colors mapped based on position index
    final ringColors = [
      const Color(0xFF4CAF50), // Green (Santhosh)
      const Color(0xFF9C27B0), // Purple (Anitha)
      const Color(0xFFE91E63), // Pink (Nandini)
      const Color(0xFFFF5722), // Orange (Latha Akka)
      const Color(0xFFFFC107), // Yellow (Ramesh Mama)
      const Color(0xFF009688), // Teal (Vikram)
    ];
    final ringColor = ringColors[contact.positionIndex % ringColors.length];

    // Santhosh (index 0) gets a green active status dot
    final isOnline = contact.positionIndex == 0;

    return Semantics(
      label: "Contact card for ${contact.name}",
      container: true,
      child: Card(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        color: kCardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          // Subtle visual highlight border indicating "tap again to call"
          side: isSelected ? BorderSide(color: ringColor, width: 3.5) : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => _handleTap(context, ref),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.only(top: 10.0, bottom: 8.0, left: 6.0, right: 6.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Photo with colored ring and optional online status indicator
                _buildPhoto(ringColor, isOnline, isSelected),
                const SizedBox(height: 6.0),
                
                // 2. Name Text
                Text(
                  contact.name,
                  style: const TextStyle(
                    fontSize: 17.0,
                    fontWeight: FontWeight.bold,
                    color: kTextNavy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8.0),
                
                // 3. Action Buttons Row (Call, Video, Voice) with generous gaps
                Row(
                  children: [
                    // Phone (Call) Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kCallGreen,
                        icon: Icons.phone,
                        label: "Call",
                        semanticsLabel: "Call ${contact.name}",
                        onTap: () => _handleTap(context, ref),
                      ),
                    ),
                    
                    // Video Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kVideoBlue,
                        icon: Icons.videocam,
                        label: "Video",
                        semanticsLabel: "Video call ${contact.name}",
                        onTap: hasWhatsapp
                            ? () {
                                ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
                              }
                            : null,
                      ),
                    ),
                    
                    // Mic (Voice Message) Button Column
                    Expanded(
                      child: _buildActionButtonColumn(
                        context: context,
                        color: kMessageOrange,
                        icon: Icons.mic,
                        label: "Voice",
                        semanticsLabel: "Send voice message to ${contact.name}",
                        onTap: () async {
                          final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                          if (path != null) {
                            ref.read(voiceMessageOverlayProvider.notifier).open(contact);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoto(Color ringColor, bool isOnline, bool isSelected) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
    const photoSize = 84.0;

    return Semantics(
      label: "${contact.name}'s profile photo",
      image: true,
      child: Stack(
        alignment: Alignment.center,
        children: [
        Container(
          width: photoSize + 12,
          height: photoSize + 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              // Pulsing / highlighted border ring visual cue
              color: isSelected ? ringColor : ringColor.withValues(alpha: 0.4),
              width: isSelected ? 4.0 : 2.0,
            ),
          ),
          padding: const EdgeInsets.all(5.0),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[200],
              image: hasPhoto
                  ? DecorationImage(
                      image: ResizeImage(
                        FileImage(File(contact.photoPath!)),
                        width: 180,
                        height: 180,
                      ),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: hasPhoto
                ? null
                : Icon(
                    Icons.person,
                    size: 40.0,
                    color: Colors.grey[400],
                  ),
          ),
        ),
        if (isOnline)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtonColumn({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return RepaintBoundary(
      child: Semantics(
        label: semanticsLabel,
        button: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 4.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 44.0,
                      height: 44.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isEnabled ? color : Colors.grey[300],
                        boxShadow: isEnabled
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        size: 22.0,
                        color: isEnabled ? Colors.white : Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: kTextSlate,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
