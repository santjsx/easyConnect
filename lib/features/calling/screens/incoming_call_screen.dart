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
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

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
  Color get kAccentPurple => ref.watch(dynamicAccentColorProvider);
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

    // Repeat every 8 seconds while ringing (giving enough time for the full regional prompt to play)
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

    // 55% split for giant photo layout to aid senior visual recognition
    final double topSectionHeight = screenHeight * 0.55;
    final double bottomSectionHeight = screenHeight * 0.45;

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

          // Top section: Caller photo or avatar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topSectionHeight,
            child: _hasPhoto
                ? _buildCallerPhoto(topSectionHeight)
                : _buildCallerAvatar(screenWidth, topSectionHeight),
          ),

          // Bottom section: Call info + action buttons
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottomSectionHeight,
            child: _buildBottomPanel(bottomSectionHeight, screenWidth),
          ),
        ],
      ),
    );
  }

  Widget _buildCallerPhoto(double sectionHeight) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.file(
          File(_matchedContact!.photoPath!),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildCallerAvatar(
            MediaQuery.sizeOf(context).width,
            sectionHeight,
          ),
        ),
        // Gradient overlay at the bottom for text readability
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: sectionHeight * 0.4,
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

  Widget _buildCallerAvatar(double screenWidth, double sectionHeight) {
    final avatarSize = math.min(screenWidth * 0.45, sectionHeight * 0.6);
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

  Widget _buildBottomPanel(double sectionHeight, double screenWidth) {
    final double nameFontSize = screenWidth < 360 ? 32.0 : 42.0;
    // Scale button sizes dynamically:
    const double acceptBtnSize = 120.0;
    const double declineBtnSize = 90.0;
    final double topSpacing = sectionHeight < 280 ? 10.0 : 20.0;
    final double paddingBottom = (sectionHeight * 0.12).clamp(16.0, 48.0) + MediaQuery.paddingOf(context).bottom;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SizedBox(height: topSpacing),
          // Caller name
          Text(
            _displayName,
            style: TextStyle(
              fontSize: nameFontSize,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1.0,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          // Pulsing connection light or wave instead of text
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: kCallGreen.withValues(alpha: 0.8),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: kCallGreen.withValues(alpha: 0.4),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),

          const Spacer(),

          // Action buttons row (no text labels, widely spaced, huge touch targets)
          Padding(
            padding: EdgeInsets.only(
              bottom: paddingBottom,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Decline button (Red)
                _buildActionButton(
                  onTap: () {
                    HapticFeedback.heavyImpact();
                    ref.read(ttsServiceProvider).stop();
                    widget.onDecline();
                  },
                  color: kSosRed,
                  icon: Icons.call_end_rounded,
                  buttonSize: declineBtnSize,
                  iconSize: 44.0,
                ),

                // Accept button with glow (Green)
                _buildAcceptButton(
                  buttonSize: acceptBtnSize,
                  iconSize: 64.0,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptButton({
    required double buttonSize,
    required double iconSize,
  }) {
    return GestureDetector(
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
            width: buttonSize,
            height: buttonSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kCallGreen,
              boxShadow: [
                BoxShadow(
                  color: kCallGreen.withValues(alpha: glowIntensity),
                  blurRadius: buttonSize * 0.3,
                  spreadRadius: buttonSize * 0.11,
                ),
                BoxShadow(
                  color: kCallGreen.withValues(alpha: glowIntensity * 0.5),
                  blurRadius: buttonSize * 0.6,
                  spreadRadius: buttonSize * 0.19,
                ),
              ],
            ),
            child: Icon(
              Icons.call_rounded,
              color: Colors.white,
              size: iconSize,
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButton({
    required VoidCallback onTap,
    required Color color,
    required IconData icon,
    required double buttonSize,
    required double iconSize,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: buttonSize * 0.25,
              spreadRadius: buttonSize * 0.06,
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: iconSize,
        ),
      ),
    );
  }
}
