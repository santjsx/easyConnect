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

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Pull bar
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 24),

                // Contact Header with large photo or initials
                Semantics(
                  label: "Connecting with ${contact.name}",
                  container: true,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildPhoto(ringColor, isOnline, false, language),
                      const SizedBox(width: 16),
                      Flexible(
                        child: Text(
                          contact.name,
                          style: const TextStyle(
                            fontSize: 28.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Button 1: Normal Phone Call (Green)
                _buildSeniorActionButton(
                  context: context,
                  ref: ref,
                  color: kCallGreen,
                  icon: Icons.phone,
                  label: language == 'te' ? 'ఫోన్ కాల్ (మామూలు కాల్)' : (language == 'hi' ? 'फ़ोन कॉल' : 'Phone Call'),
                  semanticsLabel: "Phone Call ${contact.name}",
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(audioCallServiceProvider).makeCall(context, contact);
                  },
                ),
                const SizedBox(height: 16),

                // Button 2: WhatsApp Video Call (Blue)
                _buildSeniorActionButton(
                  context: context,
                  ref: ref,
                  color: kVideoBlue,
                  icon: Icons.videocam,
                  label: language == 'te' ? 'వీడియో కాల్ (వాట్సాప్)' : (language == 'hi' ? 'वीडियो कॉल' : 'Video Call'),
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
                const SizedBox(height: 16),

                // Button 3: Voice Message (Orange)
                _buildSeniorActionButton(
                  context: context,
                  ref: ref,
                  color: kMessageOrange,
                  icon: Icons.mic,
                  label: language == 'te' ? 'వాయిస్ మెసేజ్ పంపు' : (language == 'hi' ? 'आवाज़ संदेश भेजें' : 'Voice Message'),
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
                const SizedBox(height: 24),

                // Close Button (Red outlined)
                SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent, width: 2.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: const Icon(Icons.close, size: 28),
                    label: Text(
                      language == 'te' ? 'మూసివేయి' : (language == 'hi' ? 'बंद करें' : 'Close'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      ref.read(ttsServiceProvider).stop();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeniorActionButton({
    required BuildContext context,
    required WidgetRef ref,
    required Color color,
    required IconData icon,
    required String label,
    required String semanticsLabel,
    required VoidCallback onTap,
    bool isEnabled = true,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 80,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isEnabled ? color : Colors.grey.shade900,
          foregroundColor: isEnabled ? Colors.white : Colors.grey.shade500,
          elevation: isEnabled ? 4 : 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: isEnabled
                ? BorderSide.none
                : BorderSide(color: Colors.grey.shade800, width: 2.0),
          ),
        ),
        onPressed: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: isEnabled ? Colors.white24 : Colors.white10,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: isEnabled ? Colors.white : Colors.grey.shade500,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: isEnabled ? Colors.white : Colors.grey.shade500,
                  ),
                ),
              ),
              if (isEnabled)
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 18,
                  color: Colors.white70,
                ),
            ],
          ),
        ),
      ),
    );
  }


  Color _getInitialsColor(int index) {
    final colors = [
      const Color(0xFF2196F3), // Blue (Manu)
      const Color(0xFFFFB300), // Gold/Yellow (Husband)
      const Color(0xFF4CAF50), // Green (Ammi)
      const Color(0xFFE91E63), // Pink (Santhosh)
      const Color(0xFFFF5722), // Orange/Coral (Nagesh)
      const Color(0xFF9C27B0), // Purple (Prashanthi)
      const Color(0xFF009688), // Teal (Ramadevi)
    ];
    return colors[index % colors.length];
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
      data: (settings) => settings.layoutMode,
      loading: () => 'classic',
      error: (err, stack) => 'classic',
    );

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

    if (layoutMode == 'classic') {
      final hasPhoto = contact.photoPath != null && contact.photoPath!.isNotEmpty;
      return RepaintBoundary(
        child: Semantics(
          label: "Contact card for ${contact.name}",
          container: true,
          child: Card(
            elevation: 0,
            color: const Color(0xFF1E2F47), // Lighter card navy blue
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: isSelected ? BorderSide(color: ringColor, width: 3.0) : BorderSide.none,
            ),
            child: InkWell(
              onTap: () => _handleTap(context, ref),
              onLongPress: () => _showSeniorActionSheet(context, ref),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. Large Rounded Square initials / photo with optional TAP AGAIN overlay
                    AspectRatio(
                      aspectRatio: 1.0,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: double.infinity,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: hasPhoto ? null : _getInitialsColor(contact.positionIndex),
                              borderRadius: BorderRadius.circular(12),
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
                            alignment: Alignment.center,
                            child: hasPhoto
                                ? null
                                : Text(
                                    _getInitials(contact.name),
                                    style: const TextStyle(
                                      fontSize: 24.0,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                          if (isSelected && !hasPhoto)
                            Positioned(
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ringColor,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6.0),

                    // 2. Name Text
                    SizedBox(
                      width: double.infinity,
                      height: 18,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Text(
                          contact.name,
                          style: const TextStyle(
                            fontSize: 13.0,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2.0),

                    // 3. Dynamic Preferred Action Subtitle Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          contact.preferredAction == 'video'
                              ? Icons.videocam
                              : contact.preferredAction == 'message'
                                  ? Icons.mic
                                  : Icons.phone,
                          size: 11.0,
                          color: contact.preferredAction == 'video'
                              ? kVideoBlue
                              : contact.preferredAction == 'message'
                                  ? kMessageOrange
                                  : const Color(0xFF90A4AE),
                        ),
                        const SizedBox(width: 3.0),
                        Flexible(
                          child: Text(
                            contact.preferredAction == 'video'
                                ? (language == 'te' ? 'వీడియో కాల్' : (language == 'hi' ? 'वीडियो कॉल' : 'Video Call'))
                                : contact.preferredAction == 'message'
                                    ? (language == 'te' ? 'వాయిస్ మెసేజ్' : (language == 'hi' ? 'आवाज़ संदेश' : 'Voice Msg'))
                                    : (language == 'te' ? 'ఫోన్ కాల్' : (language == 'hi' ? 'कॉल' : 'Mobile')),
                            style: TextStyle(
                              fontSize: 10.0,
                              fontWeight: FontWeight.bold,
                              color: contact.preferredAction == 'video'
                                  ? kVideoBlue
                                  : contact.preferredAction == 'message'
                                      ? kMessageOrange
                                      : const Color(0xFF90A4AE),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
                _buildPhoto(ringColor, isOnline, isSelected, language),
                const SizedBox(height: 6.0),
                
                // 2. Name Text
                SizedBox(
                  width: double.infinity,
                  height: 22,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      contact.name,
                      style: const TextStyle(
                        fontSize: 17.0,
                        fontWeight: FontWeight.bold,
                        color: kTextNavy,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
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
    ),
  );
}

  Widget _buildPhoto(Color ringColor, bool isOnline, bool isSelected, String language) {
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
        if (isSelected && !hasPhoto)
          Positioned(
            bottom: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ringColor,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                language == 'te' ? 'మళ్ళీ నొక్కు' : (language == 'hi' ? 'फिर दबाएं' : 'TAP AGAIN'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
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
