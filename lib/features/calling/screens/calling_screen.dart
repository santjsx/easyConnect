import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:easyconnect/core/constants/app_colours.dart';
import 'package:easyconnect/features/contacts/models/contact_model.dart';
import 'package:easyconnect/features/calling/repositories/call_log_repository.dart';
import 'package:easyconnect/services/tts_service.dart';
import 'package:easyconnect/features/settings/models/app_settings_model.dart';
import 'package:easyconnect/features/calling/services/system_call_service.dart';
import 'package:easyconnect/features/calling/providers/is_calling_active_provider.dart';
import 'package:easyconnect/features/settings/providers/settings_provider.dart';

/// Full call lifecycle states matching Android Telecom.
/// idle → outgoing(dialing) → ongoing(active) ↔ onHold → disconnecting → ended
/// idle → incoming(ringing) → ongoing(active) ↔ onHold → disconnecting → ended
enum CallingState { incoming, outgoing, ongoing, onHold, disconnecting }

class CallStatus {
  static const String idle = '';
  static const String incomingVoice = 'Incoming Call';
  static const String incomingVideo = 'Incoming Video Call';
  static const String calling = 'Calling...';
  static const String ringing = 'Ringing...';
  static const String connecting = 'Connecting...';
  static const String connected = 'Connected';
  static const String onHold = 'On Hold';
  static const String reconnecting = 'Reconnecting...';
  static const String ended = 'Call Ended';
  static const String declined = 'Call Declined';
  static const String noAnswer = 'No Answer';
  static const String failed = 'Call Failed';
  static const String busy = 'Busy';
  static const String unavailable = 'Unavailable';
}

const MethodChannel _channel = MethodChannel('com.easyconnect.app/calling');

// ─────────────────────────────────────────────────────────────────────────────
// CallingScreen
// ─────────────────────────────────────────────────────────────────────────────
class CallingScreen extends ConsumerStatefulWidget {
  final Contact contact;
  final CallingState initialState;
  final bool isSystemCall;

  const CallingScreen({
    super.key,
    required this.contact,
    required this.initialState,
    this.isSystemCall = false,
  });

  @override
  ConsumerState<CallingScreen> createState() => _CallingScreenState();
}

class _CallingScreenState extends ConsumerState<CallingScreen>
    with TickerProviderStateMixin {
  Color get kAccentPurple => ref.watch(dynamicAccentColorProvider);
  // ── Call State ──
  late CallingState _currentState;

  bool _isSpeakerOn = false;
  bool _isMuted = false;
  bool _isOnHold = false;
  bool _showDtmfKeypad = false;
  bool _isAllowedToPop = false;
  String _dtmfInput = '';
  bool _isDisposed = false;

  // ── Timers ──
  Timer? _stateTimer;
  Timer? _ttsTimer;
  Timer? _callDurationTimer;
  int _callSeconds = 0;
  String _language = 'en';

  // ── Animation Controllers ──
  late AnimationController _pulseController;
  late AnimationController _swipeHintController;

  @override
  void initState() {
    super.initState();
    _currentState = widget.initialState;
    _loadLanguage();
    _initAnimations();
    _handleStateInit();
    Future.microtask(() {
      if (mounted) {
        ref.read(isCallingScreenActiveProvider.notifier).state = true;
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stateTimer?.cancel();
    _ttsTimer?.cancel();
    _callDurationTimer?.cancel();
    _pulseController.dispose();
    _swipeHintController.dispose();
    // Note: Do not call ref.read(ttsServiceProvider).stop() here, because we want
    // the "Call ended" spoken feedback to play completely in the background after the screen pops.
    final activeNotifier = ref.read(isCallingScreenActiveProvider.notifier);
    Future.microtask(() {
      activeNotifier.state = false;
    });
    super.dispose();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _swipeHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    if (_currentState == CallingState.incoming ||
        _currentState == CallingState.outgoing) {
      _pulseController.repeat();
    }
    if (_currentState == CallingState.incoming) {
      _swipeHintController.repeat(reverse: true);
    }
  }

  void _loadLanguage() {
    final settingsBox =
        Hive.isBoxOpen('settings') ? Hive.box<AppSettings>('settings') : null;
    if (settingsBox != null && settingsBox.isNotEmpty) {
      _language = settingsBox.values.first.language;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Initialization
  // ─────────────────────────────────────────────────────────────────────────
  void _handleStateInit() {
    ref.read(ttsServiceProvider).stop();

    if (_currentState == CallingState.incoming) {
      _startIncomingTtsLoop();
    } else if (_currentState == CallingState.outgoing) {
      _speakOutgoingPrompt();
      if (!widget.isSystemCall) {
        // Demo mode: simulate connection after 2.5s
        _stateTimer = Timer(const Duration(milliseconds: 2500), () {
          if (mounted) _handleCallConnected();
        });
      }
    } else if (_currentState == CallingState.ongoing) {
      _startCallDurationTimer();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TTS
  // ─────────────────────────────────────────────────────────────────────────
  void _speakOutgoingPrompt() {
    if (_isDisposed || !mounted) return;
    ref.read(ttsServiceProvider).speak('Calling ${widget.contact.name}');
  }

  void _startIncomingTtsLoop() {
    if (_isDisposed || !mounted) return;
    final tts = ref.read(ttsServiceProvider);
    void speak() {
      if (_isDisposed || !mounted) return;
      tts.speak('incoming_guided_known:${widget.contact.name}');
    }

    speak();
    _ttsTimer = Timer.periodic(const Duration(seconds: 8), (_) => speak());
  }

  void _speakCallConnected() {
    if (_isDisposed || !mounted) return;
    ref.read(ttsServiceProvider).speak('Call connected');
  }

  void _speakCallEnded() {
    if (_isDisposed || !mounted) return;
    ref.read(ttsServiceProvider).speak('Call ended');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // State Transitions
  // ─────────────────────────────────────────────────────────────────────────
  void _handleCallConnected() {
    if (_isDisposed || !mounted) return;
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    try {
      _pulseController.repeat(reverse: true);
    } catch (_) {}
    try {
      _swipeHintController.stop();
    } catch (_) {}
    _speakCallConnected();
    setState(() {
      _currentState = CallingState.ongoing;
      _isOnHold = false;
    });
    _startCallDurationTimer();
  }

  void _handleDisconnect() {
    if (_isDisposed || !mounted) return;
    if (_currentState == CallingState.disconnecting) return; // Already disconnecting
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _callDurationTimer?.cancel();
    try {
      _pulseController.stop();
    } catch (_) {}
    try {
      _swipeHintController.stop();
    } catch (_) {}
    _speakCallEnded();
    setState(() {
      _currentState = CallingState.disconnecting;
      _showDtmfKeypad = false;
      _isAllowedToPop = true;
    });
    ref.read(systemCallProvider.notifier).clear();
    Navigator.of(context).pop();
  }

  void _handleHoldStateChange(bool isHeld) {
    if (_isDisposed || !mounted) return;
    setState(() {
      _isOnHold = isHeld;
      _currentState = isHeld ? CallingState.onHold : CallingState.ongoing;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Call Actions
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _acceptCall() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _swipeHintController.stop();
    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    if (widget.isSystemCall) {
      _channel.invokeMethod('acceptSystemCall');
      // State update will arrive from the system call listener
      return;
    }
    _handleCallConnected();
  }

  Future<void> _declineCall() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _swipeHintController.stop();
    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    await ref.read(callLogRepositoryProvider).addLog(
          widget.contact.name,
          widget.contact.phoneNumber,
          'missed',
        );
    if (!mounted) return;

    if (widget.isSystemCall) {
      _channel.invokeMethod('hangUpSystemCall');
      _handleDisconnect();
      return;
    }

    _speakCallEnded();
    if (mounted) {
      setState(() => _isAllowedToPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> _hangUp() async {
    _ttsTimer?.cancel();
    _stateTimer?.cancel();
    _callDurationTimer?.cancel();
    await HapticFeedback.heavyImpact();
    if (!mounted) return;

    final logType =
        widget.initialState == CallingState.incoming ? 'incoming' : 'dialed';
    await ref.read(callLogRepositoryProvider).addLog(
          widget.contact.name,
          widget.contact.phoneNumber,
          logType,
        );
    if (!mounted) return;

    if (widget.isSystemCall) {
      _channel.invokeMethod('hangUpSystemCall');
      _handleDisconnect();
      return;
    }

    _speakCallEnded();
    if (mounted) {
      setState(() => _isAllowedToPop = true);
      Navigator.pop(context);
    }
  }



  void _toggleSpeaker() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final next = !_isSpeakerOn;
    setState(() => _isSpeakerOn = next);
    if (widget.isSystemCall) {
      _channel.invokeMethod('setCallSpeaker', {'speaker': next});
    }
    ref.read(ttsServiceProvider).speak(next ? 'speaker_loud' : 'speaker_soft');
  }

  void _toggleMute() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    final next = !_isMuted;
    setState(() => _isMuted = next);
    if (widget.isSystemCall) {
      _channel.invokeMethod('setCallMute', {'mute': next});
    }
    ref.read(ttsServiceProvider).speak(next ? 'microphone_muted' : 'microphone_unmuted');
  }



  void _sendDtmfTone(String digit) async {
    await HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() => _dtmfInput += digit);
    if (widget.isSystemCall) {
      _channel.invokeMethod('playDtmfTone', {'digit': digit});
      Future.delayed(const Duration(milliseconds: 200), () {
        _channel.invokeMethod('stopDtmfTone');
      });
    }
  }

  void _toggleDtmfKeypad() {
    HapticFeedback.mediumImpact();
    setState(() {
      _showDtmfKeypad = !_showDtmfKeypad;
      if (!_showDtmfKeypad) _dtmfInput = '';
    });
  }



  // ─────────────────────────────────────────────────────────────────────────
  // Timer
  // ─────────────────────────────────────────────────────────────────────────
  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callSeconds = 0;
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callSeconds++);
    });
  }

  String _formatDuration(int totalSeconds) {
    final h = totalSeconds ~/ 3600;
    final m = (totalSeconds % 3600) ~/ 60;
    final s = totalSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  String _translate(String text) {
    if (_language == 'te') {
      switch (text) {
        case 'Cancel Call': return 'కాల్ రద్దు';
        case 'End Call': return 'ముగించు';
        case 'Speaker On': return 'స్పీకర్ ఆన్';
        case 'Speaker Off': return 'స్పీకర్ ఆఫ్';
        case 'Decline': return 'తిరస్కరించు';
        case 'Answer': return 'సమాధానం';
        case 'Calling...': return 'కాల్ కలుపుతోంది...';
        case 'is calling you': return 'కాల్ చేస్తున్నారు';
        case 'Call Ended': return 'కాల్ मुగిసింది';
        default: return text;
      }
    } else if (_language == 'hi') {
      switch (text) {
        case 'Cancel Call': return 'कॉल रद्द';
        case 'End Call': return 'समाप्त';
        case 'Speaker On': return 'स्पीकर ऑन';
        case 'Speaker Off': return 'स्पीकर ऑफ';
        case 'Decline': return 'अस्वीकार';
        case 'Answer': return 'स्वीकार';
        case 'Calling...': return 'कॉल हो रही है...';
        case 'is calling you': return 'कॉल आ रही है';
        case 'Call Ended': return 'कॉल समाप्त';
        default: return text;
      }
    }
    return text;
  }

  Color _getBackgroundColor() {
    switch (_currentState) {
      case CallingState.incoming:
        return const Color(0xFFF0F7FF); // Soft blue
      case CallingState.outgoing:
        return const Color(0xFFF3F0FF); // Soft lavender
      case CallingState.ongoing:
      case CallingState.onHold:
        return const Color(0xFFF0FDF4); // Soft green
      case CallingState.disconnecting:
        return const Color(0xFFFEF2F2); // Soft red
    }
  }

  Gradient _getBackgroundGradient() {
    final baseColor = _getBackgroundColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        baseColor,
        Color.lerp(baseColor, const Color(0xFFF8FAFC), 0.4)!,
        const Color(0xFFF8FAFC),
      ],
      stops: const [0.0, 0.6, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read systemCallProvider during build, we trigger rebuilds via setState in the listener!
    final systemCall = widget.isSystemCall ? ref.read(systemCallProvider) : null;

    // ── System call state listener ──
    if (widget.isSystemCall) {
      ref.listen<SystemCallState?>(systemCallProvider, (prev, next) {
        if (_isDisposed || !mounted) return;
        if (next == null) return;

        if (next.isDisconnected || next.rawState == 7 || next.rawState == 10) { // 7 = DISCONNECTED, 10 = DISCONNECTING
          _handleDisconnect();
          return;
        }

        // Trigger a rebuild to update status pill and state if rawState changes
        if (next.rawState != prev?.rawState) {
          final oldState = _currentState;
          final wasOnHold = _isOnHold;

          switch (next.rawState) {
            case 2: // Call.STATE_RINGING
              setState(() {
                _currentState = CallingState.incoming;
              });
              break;
            case 8: // Call.STATE_SELECT_PHONE_ACCOUNT
            case 9: // Call.STATE_CONNECTING
            case 1: // Call.STATE_DIALING
              setState(() {
                _currentState = CallingState.outgoing;
              });
              break;
            case 4: // Call.STATE_ACTIVE
              if (oldState == CallingState.onHold || wasOnHold) {
                _handleHoldStateChange(false); // Resumed from hold
              } else if (oldState != CallingState.ongoing) {
                _handleCallConnected(); // Connected for the first time
              }
              break;
            case 3: // Call.STATE_HOLDING
              if (!wasOnHold || oldState != CallingState.onHold) {
                _handleHoldStateChange(true); // Put on hold
              }
              break;
          }
        }
      });
    }

    Color ringColor;
    try {
      ringColor = _parseHexColor(widget.contact.colorTheme);
    } catch (_) {
      ringColor = const Color(0xFF6C6BF8);
    }

    // Set System UI overlay style to dynamically match caller screen background
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: _getBackgroundColor(),
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    return PopScope(
      canPop: _isAllowedToPop,
      child: Scaffold(
        backgroundColor: _getBackgroundColor(),
        body: Container(
          decoration: BoxDecoration(
            gradient: _getBackgroundGradient(),
          ),
          child: SafeArea(
            child: Stack(
              children: [
                // ── Main content ──
                _buildMainContent(ringColor, systemCall),
                // ── DTMF Keypad Overlay ──
                if (_showDtmfKeypad) _buildDtmfOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashingGreenDot() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: const Color(0xFF16A34A).withValues(alpha: 0.3 + 0.7 * _pulseController.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF16A34A).withValues(alpha: 0.4 * _pulseController.value),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }

  // Main Content Layout
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildMainContent(Color ringColor, SystemCallState? systemCall) {
    final showPhoneNumber =
        widget.contact.phoneNumber != widget.contact.name &&
            widget.contact.phoneNumber.isNotEmpty;

    // Determine subtext/timer color and text
    Color statusColor;
    String statusLabel = '';
    Widget? statusWidget;

    if (_currentState == CallingState.outgoing) {
      statusColor = const Color(0xFF7C3AED); // purple
      statusLabel = 'Calling...';
      statusWidget = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _translate(statusLabel),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          const SizedBox(height: 12),
          _CallingConnectionIndicator(color: statusColor),
        ],
      );
    } else if (_currentState == CallingState.ongoing || _currentState == CallingState.onHold) {
      statusColor = const Color(0xFF16A34A); // green
      if (_currentState == CallingState.onHold) {
        final onHoldPrefix = _language == 'te' ? 'హోల్డ్ లో ఉంది' : (_language == 'hi' ? 'होल्ड पर' : 'On Hold');
        statusLabel = '$onHoldPrefix · ${_formatDuration(_callSeconds)}';
      } else {
        statusLabel = _formatDuration(_callSeconds);
      }
      statusWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _flashingGreenDot(),
          const SizedBox(width: 8),
          Text(
            statusLabel,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: statusColor,
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
    } else if (_currentState == CallingState.incoming) {
      statusColor = const Color(0xFF3F51B5); // indigo
      statusLabel = _language == 'te' ? 'కాల్ చేస్తున్నారు' : (_language == 'hi' ? 'कॉल आ रही है' : 'is calling you');
      statusWidget = Text(
        statusLabel,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: statusColor,
        ),
      );
    } else {
      // Disconnecting
      statusColor = kStopRed;
      statusLabel = 'Call Ended';
      statusWidget = Text(
        _translate(statusLabel),
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: statusColor,
        ),
      );
    }

    // Glow color for avatar
    Color avatarGlowColor;
    switch (_currentState) {
      case CallingState.incoming:
        avatarGlowColor = const Color(0xFF3F51B5);
        break;
      case CallingState.outgoing:
        avatarGlowColor = const Color(0xFF7C3AED);
        break;
      case CallingState.ongoing:
      case CallingState.onHold:
        avatarGlowColor = const Color(0xFF16A34A);
        break;
      default:
        avatarGlowColor = kStopRed;
    }

    return Column(
      children: [
        const SizedBox(height: 56),
        
        // Name
        Semantics(
          header: true,
          child: Text(
            widget.contact.name,
            style: const TextStyle(
              fontSize: 40.0,
              fontWeight: FontWeight.bold,
              color: kTextNavy,
              letterSpacing: -1.0,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // Phone number (if different from name)
        if (showPhoneNumber) ...[
          const SizedBox(height: 4.0),
          Text(
            widget.contact.phoneNumber,
            style: TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w600,
              color: kTextNavy.withValues(alpha: 0.5),
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],

        const SizedBox(height: 12.0),

        // Status/Timer text or dots
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: SizedBox(
            key: ValueKey('${_currentState.name}_status'),
            height: 64, // Fixed height to avoid layout shifts when timer/dots switch
            child: Align(
              alignment: Alignment.center,
              child: statusWidget,
            ),
          ),
        ),

        const Spacer(),

        // Centered Avatar with pulsing glow
        _CallingAvatar(
          contact: widget.contact,
          glowColor: avatarGlowColor,
          isActive: _currentState == CallingState.incoming || _currentState == CallingState.outgoing,
        ),

        const Spacer(),

        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: _buildRedesignedControls(),
          ),
        ),
        
        const SizedBox(height: 48),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Controls Routing & Control Views
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildRedesignedControls() {
    switch (_currentState) {
      case CallingState.incoming:
        return _buildIncomingControls();
      case CallingState.outgoing:
        return _buildCancelCallButton();
      case CallingState.ongoing:
      case CallingState.onHold:
        return _buildOngoingControls();
      case CallingState.disconnecting:
        return _buildDisconnectingView();
    }
  }

  Widget _buildSpeakerMuteRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Speaker Button
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _isSpeakerOn ? const Color(0xFF007AFF) : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isSpeakerOn ? const Color(0xFF007AFF) : const Color(0xFF94A3B8),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isSpeakerOn 
                    ? const Color(0xFF007AFF).withValues(alpha: 0.3) 
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleSpeaker,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
                  color: _isSpeakerOn ? Colors.white : kTextNavy,
                  size: 32,
                ),
              ),
            ),
          ),
        ),

        // Mute Button
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _isMuted ? const Color(0xFFFF8C00) : const Color(0xFFF1F5F9),
            shape: BoxShape.circle,
            border: Border.all(
              color: _isMuted ? const Color(0xFFFF8C00) : const Color(0xFF94A3B8),
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: _isMuted 
                    ? const Color(0xFFFF8C00).withValues(alpha: 0.3) 
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleMute,
              customBorder: const CircleBorder(),
              child: Center(
                child: Icon(
                  _isMuted ? Icons.mic_off : Icons.mic,
                  color: _isMuted ? Colors.white : kTextNavy,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEndCallButton() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: kStopRed,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: kStopRed.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _hangUp,
          customBorder: const CircleBorder(),
          child: const Center(
            child: Icon(
              Icons.call_end,
              color: Colors.white,
              size: 44,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCancelCallButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSpeakerMuteRow(),
          const SizedBox(height: 28),
          _buildEndCallButton(),
        ],
      ),
    );
  }

  Widget _buildOngoingControls() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSpeakerMuteRow(),
          const SizedBox(height: 28),
          _buildEndCallButton(),
        ],
      ),
    );
  }

  Widget _buildIncomingControls() {
    const double acceptBtnSize = 120.0;
    const double declineBtnSize = 90.0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Decline button (Red)
        GestureDetector(
          onTap: _declineCall,
          child: Container(
            width: declineBtnSize,
            height: declineBtnSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kSosRed,
              boxShadow: [
                BoxShadow(
                  color: kSosRed.withValues(alpha: 0.3),
                  blurRadius: declineBtnSize * 0.25,
                  spreadRadius: declineBtnSize * 0.06,
                ),
              ],
            ),
            child: const Icon(
              Icons.call_end_rounded,
              color: Colors.white,
              size: 44.0,
            ),
          ),
        ),

        // Accept button with glow (Green)
        GestureDetector(
          onTap: _acceptCall,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              final glowIntensity = 0.15 + _pulseController.value * 0.35;
              return Container(
                width: acceptBtnSize,
                height: acceptBtnSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kCallGreen,
                  boxShadow: [
                    BoxShadow(
                      color: kCallGreen.withValues(alpha: glowIntensity),
                      blurRadius: acceptBtnSize * 0.3,
                      spreadRadius: acceptBtnSize * 0.11,
                    ),
                    BoxShadow(
                      color: kCallGreen.withValues(alpha: glowIntensity * 0.5),
                      blurRadius: acceptBtnSize * 0.6,
                      spreadRadius: acceptBtnSize * 0.19,
                ),
                  ],
                ),
                child: const Icon(
                  Icons.call_rounded,
                  color: Colors.white,
                  size: 64.0,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDisconnectingView() {
    return Column(
      key: const ValueKey('disconnecting_view'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.call_end, size: 48, color: kStopRed),
        const SizedBox(height: 16),
        Text(
          _translate('Call Ended'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: kStopRed,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DTMF Keypad Overlay
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildDtmfOverlay() {
    const dtmfKeys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    const subLabels = {
      '2': 'ABC',
      '3': 'DEF',
      '4': 'GHI',
      '5': 'JKL',
      '6': 'MNO',
      '7': 'PQRS',
      '8': 'TUV',
      '9': 'WXYZ',
      '0': '+',
    };

    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleDtmfKeypad,
        child: Container(
          color: Colors.black.withValues(alpha: 0.3),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {}, // Prevent tap-through
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 30,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // DTMF Input display
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: kAppBackground,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        _dtmfInput.isEmpty ? 'Enter digits' : _dtmfInput,
                        style: TextStyle(
                          fontSize: _dtmfInput.isEmpty ? 16 : 24,
                          fontWeight: FontWeight.w600,
                          color: _dtmfInput.isEmpty ? kTextSlate : kTextNavy,
                          letterSpacing: 2,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Keypad grid
                    ...dtmfKeys.map((row) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: row
                                .map((digit) => _DtmfKey(
                                      digit: digit,
                                      subLabel: subLabels[digit],
                                      onTap: () => _sendDtmfTone(digit),
                                    ))
                                .toList(),
                          ),
                        )),

                    const SizedBox(height: 8),
                    // Close button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: _toggleDtmfKeypad,
                        style: TextButton.styleFrom(
                          backgroundColor: kAppBackground,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Close Keypad',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: kAccentPurple,
                          ),
                        ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // Reusable Widgets
  // ─────────────────────────────────────────────────────────────────────────


}

// ═══════════════════════════════════════════════════════════════════════════
// SWIPE-TO-ANSWER ROW
// ═══════════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════════
// CALLING AVATAR WITH GLOW RINGS
// ═══════════════════════════════════════════════════════════════════════════
class _CallingAvatar extends StatefulWidget {
  final Contact contact;
  final Color glowColor;
  final bool isActive;

  const _CallingAvatar({
    required this.contact,
    required this.glowColor,
    required this.isActive,
  });

  @override
  State<_CallingAvatar> createState() => _CallingAvatarState();
}

class _CallingAvatarState extends State<_CallingAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.isActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _CallingAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = widget.contact.photoPath != null &&
        widget.contact.photoPath!.isNotEmpty;
    final initial = widget.contact.name.isNotEmpty
        ? widget.contact.name[0].toUpperCase()
        : '?';

    final avatarInner = hasPhoto
        ? Image.file(
            File(widget.contact.photoPath!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildFallbackAvatar(initial),
          )
        : _buildFallbackAvatar(initial);

    // Profile photo size
    const double imageSize = 160.0;
    const double borderSize = 8.0;
    const double totalAvatarSize = imageSize + (borderSize * 2);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // If not active, just return static rings
        final double animationValue = widget.isActive ? _controller.value : 0.0;
        
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring 2 (largest, fades out)
            Container(
              width: totalAvatarSize + 80.0 * (1.0 + animationValue * 0.4),
              height: totalAvatarSize + 80.0 * (1.0 + animationValue * 0.4),
              decoration: ShapeDecoration(
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(64 * (1.0 + animationValue * 0.4)),
                ),
                color: widget.glowColor.withValues(alpha: (0.04 * (1.0 - animationValue)).clamp(0.0, 1.0)),
              ),
            ),
            // Outer glow ring 1 (medium)
            Container(
              width: totalAvatarSize + 40.0 * (1.0 + animationValue * 0.2),
              height: totalAvatarSize + 40.0 * (1.0 + animationValue * 0.2),
              decoration: ShapeDecoration(
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(56 * (1.0 + animationValue * 0.2)),
                ),
                color: widget.glowColor.withValues(alpha: (0.08 * (1.0 - animationValue)).clamp(0.0, 1.0)),
              ),
            ),
            // Static soft glow base
            Container(
              width: totalAvatarSize + 20.0,
              height: totalAvatarSize + 20.0,
              decoration: ShapeDecoration(
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(52),
                ),
                color: widget.glowColor.withValues(alpha: 0.12),
              ),
            ),
            // White card border container with shadow
            Container(
              width: totalAvatarSize,
              height: totalAvatarSize,
              decoration: ShapeDecoration(
                shape: ContinuousRectangleBorder(
                  borderRadius: BorderRadius.circular(48),
                  side: const BorderSide(color: Colors.white, width: borderSize),
                ),
                color: Colors.white,
                shadows: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    spreadRadius: 2,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: widget.glowColor.withValues(alpha: 0.15),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: ClipPath(
                clipper: ShapeBorderClipper(
                  shape: ContinuousRectangleBorder(
                    borderRadius: BorderRadius.circular(44),
                  ),
                ),
                child: avatarInner,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFallbackAvatar(String initial) {
    Color baseColor;
    try {
      baseColor = _parseHexColor(widget.contact.colorTheme);
    } catch (_) {
      baseColor = const Color(0xFF4F46E5);
    }

    final hsl = HSLColor.fromColor(baseColor);
    final color2 = HSLColor.fromAHSL(1.0, hsl.hue, hsl.saturation, (hsl.lightness - 0.25).clamp(0.0, 1.0)).toColor();

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [baseColor, color2],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontSize: 64.0,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

Color _parseHexColor(String hex) {
  String cleanHex = hex.replaceAll('#', '');
  if (cleanHex.length == 6) {
    cleanHex = 'FF$cleanHex';
  }
  return Color(int.parse(cleanHex, radix: 16));
}

// ═══════════════════════════════════════════════════════════════════════════
// DTMF KEY
// ═══════════════════════════════════════════════════════════════════════════
class _DtmfKey extends StatelessWidget {
  final String digit;
  final String? subLabel;
  final VoidCallback onTap;

  const _DtmfKey({
    required this.digit,
    this.subLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            onTap();
          },
          customBorder: const CircleBorder(),
          splashColor: primaryColor.withValues(alpha: 0.1),
          highlightColor: primaryColor.withValues(alpha: 0.05),
          child: Container(
            margin: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFF1F5F9),
                width: 1.0,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  digit,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    color: kTextNavy,
                    height: 1.0,
                  ),
                ),
                if (subLabel != null)
                  Text(
                    subLabel!,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: kTextSlate.withValues(alpha: 0.6),
                      letterSpacing: 1.0,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



// ═══════════════════════════════════════════════════════════════════════════
// CALLING CONNECTION INDICATOR (three glowing dots pulsing sequentially)
// ═══════════════════════════════════════════════════════════════════════════
class _CallingConnectionIndicator extends StatefulWidget {
  final Color color;
  const _CallingConnectionIndicator({required this.color});

  @override
  State<_CallingConnectionIndicator> createState() => _CallingConnectionIndicatorState();
}

class _CallingConnectionIndicatorState extends State<_CallingConnectionIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Sequential delay for wave effect
            final delay = index * 0.22;
            double progress = _controller.value - delay;
            if (progress < 0) progress += 1.0;
            progress = progress % 1.0;

            // Sinusoidal scaling and breathing opacity
            final double scale = 0.65 + (math.sin(progress * math.pi * 2) * 0.35);
            final double opacity = 0.25 + ((math.sin(progress * math.pi * 2) + 1.0) / 2.0) * 0.75;

            return Opacity(
              opacity: opacity.clamp(0.2, 1.0),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.35),
                        blurRadius: 4,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

