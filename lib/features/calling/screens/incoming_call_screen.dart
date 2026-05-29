import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';

/// Ultra-streamlined, lightweight full-screen takeover widget for incoming ringing state.
///
/// UI Rules:
/// - No status bar, no nav bar — fully immersive
/// - Caller photo fills top 50% of the screen (if available)
/// - If no photo: large colored ring with first letter, TTS name loop every 4s
/// - Giant 130x130dp circular green (Accept) and red (Decline) touch targets
/// - Glow ring concentric ripple animations surrounding the Accept button
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
  late AnimationController _pulseController;
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

    // Pulse animation for the accept button glow
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    // Ripple animation for concentric rings
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
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
    // Announce immediately
    _announceCallerName();

    // Repeat every 4 seconds while ringing
    _ttsRepeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _announceCallerName();
    });
  }

  void _announceCallerName() {
    final tts = ref.read(ttsServiceProvider);
    if (_matchedContact != null) {
      tts.speak('incoming_known:${_matchedContact!.name}');
    } else {
      tts.speak('incoming_unknown');
    }
  }

  @override
  void dispose() {
    _ttsRepeatTimer?.cancel();
    _pulseController.dispose();
    _rippleController.dispose();
    // Restore normal UI mode
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1A1A2E),
                  Color(0xFF0F172A),
                  Color(0xFF0A0A1A),
                ],
              ),
            ),
          ),

          // Top 50%: Caller photo or avatar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.5,
            child: _hasPhoto
                ? _buildCallerPhoto()
                : _buildCallerAvatar(screenWidth),
          ),

          // Bottom 50%: Call info + action buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.5,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildCallerPhoto() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(_matchedContact!.photoPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildCallerAvatar(
            MediaQuery.sizeOf(context).width,
          ),
        ),
        // Gradient overlay at the bottom for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Color(0xFF0F172A),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallerAvatar(double screenWidth) {
    final avatarSize = screenWidth * 0.45;
    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Animated concentric ripple rings
          ...List.generate(3, (index) {
            return AnimatedBuilder(
              animation: _rippleController,
              builder: (context, child) {
                final progress = (_rippleController.value + index * 0.33) % 1.0;
                final scale = 1.0 + progress * 0.6;
                final opacity = (1.0 - progress).clamp(0.0, 0.4);
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: kAccentPurple.withValues(alpha: opacity),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            );
          }),

          // Main avatar circle
          Container(
            width: avatarSize * 0.75,
            height: avatarSize * 0.75,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF6E44FF),
                  Color(0xFF9B59B6),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: kAccentPurple.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _displayInitial,
                style: TextStyle(
                  fontSize: avatarSize * 0.3,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 24),
          // Caller name
          Text(
            _displayName,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // "Incoming Call" subtitle
          Text(
            'Incoming Call',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.6),
              letterSpacing: 1.5,
            ),
          ),

          const Spacer(),

          // Action buttons row
          Padding(
            padding: EdgeInsets.only(
              bottom: 48 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button
                _buildActionButton(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    ref.read(ttsServiceProvider).stop();
                    widget.onDecline();
                  },
                  color: kSosRed,
                  icon: Icons.call_end_rounded,
                  label: 'Decline',
                ),

                // Accept button with glow
                _buildAcceptButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptButton() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            HapticFeedback.heavyImpact();
            _ttsRepeatTimer?.cancel();
            ref.read(ttsServiceProvider).stop();
            widget.onAccept();
          },
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final glowIntensity = 0.15 + _pulseController.value * 0.35;
              return Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCallGreen,
                  boxShadow: [
                    BoxShadow(
                      color: kCallGreen.withValues(alpha: glowIntensity),
                      blurRadius: 40,
                      spreadRadius: 15,
                    ),
                    BoxShadow(
                      color: kCallGreen.withValues(alpha: glowIntensity * 0.5),
                      blurRadius: 80,
                      spreadRadius: 25,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Accept',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
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
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }
}
