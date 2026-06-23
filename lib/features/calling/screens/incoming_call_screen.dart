import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:google_fonts/google_fonts.dart';

class IncomingCallScreen extends ConsumerStatefulWidget {
  final String callerNumber;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const IncomingCallScreen({
    super.key,
    required this.callerNumber,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  ConsumerState<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends ConsumerState<IncomingCallScreen>
    with TickerProviderStateMixin {
  late AnimationController _rippleController;
  Timer? _ttsRepeatTimer;
  Contact? _matchedContact;
  String _displayName = '';
  String _displayInitial = '?';
  bool _hasPhoto = false;

  @override
  void initState() {
    super.initState();

    // Set immersive fullscreen mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Ripple animation for concentric rings (staggered 3s loop)
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _resolveContact();
    _startTTSLoop();
  }

  void _resolveContact() {
    try {
      final contactsBox = Hive.box<Contact>('contacts');
      final cleanNumber = widget.callerNumber.replaceAll(RegExp(r'\D'), '');
      _matchedContact = contactsBox.values.firstWhere(
        (c) {
          final cleanC = c.phoneNumber.replaceAll(RegExp(r'\D'), '');
          return cleanC.isNotEmpty &&
              cleanNumber.isNotEmpty &&
              (cleanC.endsWith(cleanNumber) || cleanNumber.endsWith(cleanC));
        },
      );
    } catch (_) {
      _matchedContact = null;
    }

    if (_matchedContact != null) {
      _displayName = _matchedContact!.name;
      _hasPhoto = _matchedContact!.photoPath != null &&
          _matchedContact!.photoPath!.isNotEmpty;
    } else {
      _displayName = widget.callerNumber;
      _hasPhoto = false;
    }
    _displayInitial = _displayName.trim().isNotEmpty
        ? _displayName.trim()[0].toUpperCase()
        : '?';
  }

  void _startTTSLoop() {
    _announceCallerName();
    _ttsRepeatTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _announceCallerName();
    });
  }

  void _announceCallerName() {
    final tts = ref.read(ttsServiceProvider);
    if (_matchedContact != null) {
      tts.speak('incoming_guided_known:${_matchedContact!.name}');
    } else {
      tts.speak('incoming_guided_unknown');
    }
  }

  @override
  void dispose() {
    _ttsRepeatTimer?.cancel();
    _rippleController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use a relation text in Telugu. E.g., if there's contact, Telugu text "నుండి కాల్ వస్తోంది"
    String relationText = "కాల్ వస్తోంది"; // Incoming call
    if (_matchedContact != null) {
      relationText = "${_matchedContact!.name} నుండి కాల్ వస్తోంది";
    }

    return Scaffold(
      backgroundColor: const Color(0xFF26215C),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 36),
            // Header
            Text(
              'INCOMING CALL',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF7F77DD),
                letterSpacing: 0.08 * 11.0,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              widget.callerNumber,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: const Color(0xFFAFA9EC),
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),

            // Ripple Avatar
            _buildAnimatedRippleAvatar(),

            const Spacer(),

            // Caller name
            Text(
              _displayName,
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFEEEDFE),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // Telugu callout card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                relationText,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFAFA9EC),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const Spacer(),

            // Action buttons row (Decline, Accept)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button (Red)
                  _buildActionCircle(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      ref.read(ttsServiceProvider).stop();
                      widget.onDecline();
                    },
                    color: const Color(0xFFE24B4A),
                    icon: Icons.call_end,
                    label: "Decline",
                  ),

                  // Accept button (Green)
                  _buildActionCircle(
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      _ttsRepeatTimer?.cancel();
                      ref.read(ttsServiceProvider).stop();
                      widget.onAccept();
                    },
                    color: const Color(0xFF1D9E75),
                    icon: Icons.call,
                    label: "Accept",
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Bottom replies (Message, Remind me)
            Padding(
              padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildBottomReplyChip(
                    icon: Icons.message,
                    label: "Message",
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      // Logic or toast could go here, for now match spec
                    },
                  ),
                  const SizedBox(width: 24),
                  _buildBottomReplyChip(
                    icon: Icons.notifications,
                    label: "Remind me",
                    onTap: () {
                      HapticFeedback.mediumImpact();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedRippleAvatar() {
    const double baseAvatarSize = 88.0;

    return AnimatedBuilder(
      animation: _rippleController,
      builder: (context, child) {
        final progress = _rippleController.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Concentric Ring 3 (150px)
            Container(
              width: baseAvatarSize + 62.0 * (1.0 + progress * 0.1),
              height: baseAvatarSize + 62.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity((0.08 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 2 (130px)
            Container(
              width: baseAvatarSize + 42.0 * (1.0 + progress * 0.1),
              height: baseAvatarSize + 42.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity((0.12 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),
            // Concentric Ring 1 (110px)
            Container(
              width: baseAvatarSize + 22.0 * (1.0 + progress * 0.1),
              height: baseAvatarSize + 22.0 * (1.0 + progress * 0.1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity((0.18 * (1.0 - progress)).clamp(0.0, 1.0)),
              ),
            ),

            // Center avatar 88x88
            Container(
              width: baseAvatarSize,
              height: baseAvatarSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF3C3489),
                border: Border.all(
                  color: Colors.white.withOpacity(0.15),
                  width: 3,
                ),
                image: _hasPhoto
                    ? DecorationImage(
                        image: FileImage(File(_matchedContact!.photoPath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: _hasPhoto
                  ? null
                  : Text(
                      _displayInitial,
                      style: GoogleFonts.inter(
                        fontSize: 28,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFEEEDFE),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCircle({
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            color: const Color(0xFFAFA9EC),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomReplyChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.1),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 9,
            color: const Color(0xFFAFA9EC),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
