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
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

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
  final bool isEditing;

  const ContactCard({
    super.key,
    required this.contact,
    this.isEditing = false,
  });

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

  Future<void> _executePreferredAction(BuildContext context, WidgetRef ref) async {
    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;
    
    if (contact.preferredAction == 'video') {
      if (hasWhatsapp) {
        await ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
      } else {
        // Fallback or guidance if WhatsApp number is empty
        final settings = ref.read(settingsProvider).value;
        final language = settings?.language ?? 'en';
        final prompt = language == 'te'
            ? 'వాట్సాప్ నెంబర్ లేదు. మామూలు ఫోన్ కాల్ చేస్తున్నాను.'
            : (language == 'hi'
                ? 'व्हाट्सएप नंबर नहीं है। सामान्य फोन कॉल किया जा रहा है।'
                : 'No WhatsApp number saved. Making a standard phone call.');
        await ref.read(ttsServiceProvider).speak(prompt);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, contact);
        }
      }
    } else if (contact.preferredAction == 'message') {
      if (hasWhatsapp) {
        // Voice message flow: start recording, then open recording overlay
        final path = await ref.read(recordingServiceProvider.notifier).startRecording();
        if (path != null) {
          ref.read(voiceMessageOverlayProvider.notifier).open(contact);
        }
      } else {
        final settings = ref.read(settingsProvider).value;
        final language = settings?.language ?? 'en';
        final prompt = language == 'te'
            ? 'వాట్సాప్ నెంబర్ లేదు. మామూలు ఫోన్ కాల్ చేస్తున్నాను.'
            : (language == 'hi'
                ? 'व्हाट्सएप नंबर नहीं है। सामान्य फोन कॉल किया जा रहा है।'
                : 'No WhatsApp number saved. Making a standard phone call.');
        await ref.read(ttsServiceProvider).speak(prompt);
        await Future.delayed(const Duration(milliseconds: 1500));
        if (context.mounted) {
          await ref.read(audioCallServiceProvider).makeCall(context, contact);
        }
      }
    } else {
      // Default to audio call
      await ref.read(audioCallServiceProvider).makeCall(context, contact);
    }
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;

    if (hasPhoto) {
      // Contact has photo -> immediately place the call
      _executePreferredAction(context, ref);
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
      _executePreferredAction(context, ref);
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

  void _showSeniorActionSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.heavyImpact();

    final settings = ref.read(settingsProvider).value;
    final language = settings?.language ?? 'en';
    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;

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
    final isOnline = contact.positionIndex == 0;

    // Speak prompt
    String prompt = '';
    if (language == 'te') {
      prompt = "${contact.name} కి ఫోన్ చేయడానికి ఆకుపచ్చ బటన్, వీడియో కాల్ కి నీలం బటన్, లేదా వాయిస్ మెసేజ్ కి నారింజ బటన్ నొక్కండి.";
    } else if (language == 'hi') {
      prompt = "${contact.name} को फ़ोन करने के लिए हरा बटन, वीडियो कॉल के लिए नीला बटन, या आवाज़ संदेश के लिए नारंगी बटन दबाएं।";
    } else {
      prompt = "To connect with ${contact.name}, tap the green button for a phone call, the blue button for a video call, or the orange button for a voice message.";
    }
    ref.read(ttsServiceProvider).speak(prompt);

    final String callLabel = language == 'te' ? 'కాల్' : (language == 'hi' ? 'कॉल' : 'Call');
    final String videoLabel = language == 'te' ? 'వీడియో' : (language == 'hi' ? 'वीडियो' : 'Video');
    final String voiceLabel = language == 'te' ? 'వాయిస్' : (language == 'hi' ? 'వాయ్స్' : 'Voice');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      elevation: 10,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pull bar (modern, light matching)
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 24),

                // Contact Header with large photo or initials (Navy/Light themed)
                Semantics(
                  label: "Connecting with ${contact.name}",
                  container: true,
                  child: Column(
                    children: [
                      _buildPhoto(ringColor, isOnline, false, language),
                      const SizedBox(height: 16),
                      Text(
                        contact.name,
                        style: const TextStyle(
                          fontSize: 28.0,
                          fontWeight: FontWeight.bold,
                          color: kTextNavy,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Row of Action Circle Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Button 1: Normal Phone Call (Green)
                    _buildCircularActionButton(
                      context: context,
                      color: kCallGreen,
                      icon: Icons.phone,
                      label: callLabel,
                      semanticsLabel: "Phone Call ${contact.name}",
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(audioCallServiceProvider).makeCall(context, contact);
                      },
                    ),

                    // Button 2: WhatsApp Video Call (Blue)
                    _buildCircularActionButton(
                      context: context,
                      color: kVideoBlue,
                      icon: Icons.videocam,
                      label: videoLabel,
                      semanticsLabel: "Video Call ${contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () {
                              Navigator.pop(context);
                              ref.read(whatsAppCallServiceProvider).makeVideoCall(context, contact);
                            }
                          : () {
                              HapticFeedback.vibrate();
                              ref.read(ttsServiceProvider).speak(
                                language == 'te' ? 'వాట్సాప్ నెంబర్ లేదు' : (language == 'hi' ? 'व्हाट्सएप नंबर नहीं है' : 'No WhatsApp number'),
                              );
                            },
                    ),

                    // Button 3: Voice Message (Orange)
                    _buildCircularActionButton(
                      context: context,
                      color: kMessageOrange,
                      icon: Icons.mic,
                      label: voiceLabel,
                      semanticsLabel: "Voice Message ${contact.name}",
                      isEnabled: hasWhatsapp,
                      onTap: hasWhatsapp
                          ? () async {
                              Navigator.pop(context);
                              final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                              if (path != null) {
                                ref.read(voiceMessageOverlayProvider.notifier).open(contact);
                              }
                            }
                          : () {
                              HapticFeedback.vibrate();
                              ref.read(ttsServiceProvider).speak(
                                language == 'te' ? 'వాట్సాప్ నెంబర్ లేదు' : (language == 'hi' ? 'व्हाट्सएप नंबर नहीं है' : 'No WhatsApp number'),
                              );
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Close Button (Gray circle)
                Semantics(
                  label: language == 'te' ? 'మూసివేయి' : (language == 'hi' ? 'बंद करें' : 'Close'),
                  button: true,
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: kTextSlate,
                        shape: const CircleBorder(),
                      ),
                      icon: const Icon(Icons.close, size: 28),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ref.read(ttsServiceProvider).stop();
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCircularActionButton({
    required BuildContext context,
    required Color color,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    const double buttonSize = 80.0;
    return Semantics(
      label: semanticsLabel,
      button: true,
      enabled: isEnabled,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isEnabled ? color : Colors.grey.shade100,
                foregroundColor: isEnabled ? Colors.white : Colors.grey.shade400,
                elevation: isEnabled ? 4 : 0,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                shadowColor: isEnabled ? color.withValues(alpha: 0.3) : Colors.transparent,
                side: isEnabled
                    ? BorderSide.none
                    : BorderSide(color: Colors.grey.shade200, width: 1.5),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              child: Icon(
                icon,
                size: 36,
                color: isEnabled ? Colors.white : Colors.grey.shade400,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isEnabled ? kTextNavy : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }



  Gradient _getInitialsGradient(int index) {
    final gradients = [
      kPrimaryGradient,
      kVoiceOrangeGradient,
      kCallGreenGradient,
      kPinkGradient,
    ];
    return gradients[index % gradients.length];
  }

  String _getInitials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    if (cleaned.length <= 2) return cleaned.toUpperCase();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      final p1 = parts[0];
      final p2 = parts[1];
      if (p1.isNotEmpty && p2.isNotEmpty) {
        return (p1[0] + p2[0]).toUpperCase();
      }
    }
    return cleaned.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final language = settingsAsync.when(
      data: (settings) => settings.language,
      loading: () => 'en',
      error: (err, stack) => 'en',
    );
    final layoutMode = settingsAsync.when(
      data: (settings) => settings.activeLayoutMode,
      loading: () => 'classic',
      error: (err, stack) => 'classic',
    );

    final hasWhatsapp = contact.whatsappNumber != null && contact.whatsappNumber!.trim().isNotEmpty;
    final selection = ref.watch(photolessSelectionProvider);
    final isSelected = selection.contactId == contact.id;

    final ringColors = [
      const Color(0xFF6C6BF8),
      const Color(0xFFFF8C00),
      const Color(0xFF32E08A),
      const Color(0xFFE8265E),
    ];
    final ringColor = ringColors[contact.positionIndex % ringColors.length];
    final isOnline = contact.positionIndex == 0;

    if (layoutMode == 'classic') {
      final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
      return RepaintBoundary(
        child: Semantics(
          label: "Contact card for ${contact.name}",
          container: true,
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: isSelected ? ringColor : (isEditing ? const Color(0xFF5C5BE8).withValues(alpha: 0.5) : const Color(0xFFF2F2F8)),
                width: isSelected ? 3.0 : (isEditing ? 2.0 : 1.5),
              ),
            ),
            child: InkWell(
              onTap: isEditing ? null : () => _handleTap(context, ref),
              onLongPress: isEditing ? null : () => _showSeniorActionSheet(context, ref),
              borderRadius: BorderRadius.circular(22),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 10, left: 8, right: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            gradient: hasPhoto ? null : _getInitialsGradient(contact.positionIndex),
                            image: hasPhoto
                                ? DecorationImage(
                                    image: FileImage(File(contact.photoPath!)),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: hasPhoto
                              ? null
                              : Text(
                                  _getInitials(contact.name),
                                  style: const TextStyle(
                                    fontSize: 18.0,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -1.0,
                                  ),
                                ),
                        ),
                        if (isSelected)
                          Positioned(
                            bottom: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ringColor,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                        color: kTextNavy,
                        height: 1.1,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (isEditing)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.drag_handle_rounded,
                    color: const Color(0xFF9999B0).withValues(alpha: 0.8),
                    size: 15,
                  ),
                ),
            ],
          ),
        ),
          ),
        ),
      );
    }

    return RepaintBoundary(
      child: Semantics(
        label: "Contact card for ${contact.name}",
        container: true,
        child: Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(
              color: isSelected ? ringColor : (isEditing ? const Color(0xFF5C5BE8).withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
              width: isSelected ? 3.0 : (isEditing ? 2.0 : 1.5),
            ),
          ),
          child: InkWell(
            onTap: isEditing ? null : () => _handleTap(context, ref),
            borderRadius: BorderRadius.circular(22),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildPhoto(ringColor, isOnline, isSelected, language),
                  const SizedBox(height: 6.0),
                  Text(
                    contact.name,
                    style: const TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.bold,
                      color: kTextNavy,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8.0),
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionButtonColumn(
                          context: context,
                          color: const Color(0xFF32E08A),
                          icon: Icons.phone,
                          label: "Call",
                          semanticsLabel: "Call ${contact.name}",
                          onTap: () => _handleTap(context, ref),
                        ),
                      ),
                      Expanded(
                        child: _buildActionButtonColumn(
                          context: context,
                          color: const Color(0xFF007AFF),
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
                      Expanded(
                        child: _buildActionButtonColumn(
                          context: context,
                          color: const Color(0xFFFF8C00),
                          icon: Icons.mic,
                          label: "Voice",
                          semanticsLabel: "Send voice message to ${contact.name}",
                          onTap: hasWhatsapp
                              ? () async {
                                  final path = await ref.read(recordingServiceProvider.notifier).startRecording();
                                  if (path != null) {
                                    ref.read(voiceMessageOverlayProvider.notifier).open(contact);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (isEditing)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  Icons.drag_handle_rounded,
                  color: const Color(0xFF9999B0).withValues(alpha: 0.8),
                  size: 16,
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildPhoto(Color ringColor, bool isOnline, bool isSelected, String language) {
    final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
    const photoSize = 66.0;

    return Semantics(
      label: "${contact.name}'s profile photo",
      image: true,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Container(
            width: photoSize + 10,
            height: photoSize + 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? ringColor : ringColor.withValues(alpha: 0.3),
                width: isSelected ? 3.5 : 1.5,
              ),
            ),
            padding: const EdgeInsets.all(4.0),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasPhoto ? null : Colors.transparent,
                gradient: hasPhoto ? null : _getInitialsGradient(contact.positionIndex),
                image: hasPhoto
                    ? DecorationImage(
                        image: ResizeImage(
                          FileImage(File(contact.photoPath!)),
                          width: 150,
                          height: 150,
                        ),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: hasPhoto
                  ? null
                  : Text(
                      _getInitials(contact.name),
                      style: const TextStyle(
                        fontSize: 22.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
          if (isOnline)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: const Color(0xFF32E08A),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.0),
                ),
              ),
            ),
          if (isSelected && !hasPhoto)
            Positioned(
              bottom: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ringColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
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
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36.0,
                    height: 36.0,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isEnabled ? color : const Color(0xFFEEEEF8),
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
                      size: 18.0,
                      color: isEnabled ? Colors.white : const Color(0xFF9999B0),
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                      color: isEnabled ? kTextNavy : const Color(0xFF9999B0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
