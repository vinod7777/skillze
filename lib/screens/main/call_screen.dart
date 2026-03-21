import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/webrtc_service.dart';
import '../../services/callkit_service.dart';
import '../../services/call_overlay_manager.dart';
import '../../widgets/user_avatar.dart';

/// Generates ringback tone WAV bytes (440 + 480 Hz, 2s on / 4s off).
Uint8List _generateRingbackWav() {
  const sampleRate = 22050;
  const onSec = 2;
  const offSec = 4;
  const totalSamples = sampleRate * (onSec + offSec);
  final data = ByteData(44 + totalSamples * 2);

  // RIFF header
  const riff = [0x52, 0x49, 0x46, 0x46];
  for (int i = 0; i < riff.length; i++) {
    data.setUint8(i, riff[i]);
  }
  data.setUint32(4, 36 + totalSamples * 2, Endian.little);
  const wave = [0x57, 0x41, 0x56, 0x45];
  for (int i = 0; i < wave.length; i++) {
    data.setUint8(8 + i, wave[i]);
  }
  const fmt = [0x66, 0x6D, 0x74, 0x20];
  for (int i = 0; i < fmt.length; i++) {
    data.setUint8(12 + i, fmt[i]);
  }
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  const dataTag = [0x64, 0x61, 0x74, 0x61];
  for (int i = 0; i < dataTag.length; i++) {
    data.setUint8(36 + i, dataTag[i]);
  }
  data.setUint32(40, totalSamples * 2, Endian.little);

  const onSamples = sampleRate * onSec;
  for (int i = 0; i < totalSamples; i++) {
    int sample = 0;
    if (i < onSamples) {
      final t = i / sampleRate;
      final val = 0.25 * (sin(2 * pi * 440 * t) + sin(2 * pi * 480 * t));
      sample = (val * 32767).round().clamp(-32768, 32767);
    }
    data.setInt16(44 + i * 2, sample, Endian.little);
  }
  return data.buffer.asUint8List();
}

class CallScreen extends StatefulWidget {
  final String callId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;
  final String? chatId;
  final bool isVideo;
  final bool isReceiver;
  final bool resumeExisting;
  final bool autoAnswer;

  const CallScreen({
    super.key,
    required this.callId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
    this.chatId,
    required this.isVideo,
    required this.isReceiver,
    this.resumeExisting = false,
    this.autoAnswer = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  WebRTCService? _webRTCService;
  bool _isMicOn = true;
  bool _isCameraOn = true;
  bool _isFrontCamera = true;
  bool _isSpeakerOn = false;
  bool _isConnected = false;
  String? _otherUserPhoto;
  String? _chatId;

  // Call timer
  Timer? _callTimer;
  int _callDurationSeconds = 0;

  // Call log tracking
  String? _callLogMessageId;
  bool _callWasAnswered = false;

  // Ringback tone & auto-timeout
  AudioPlayer? _ringPlayer;
  Timer? _ringTimeout;

  // Animations
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Draggable PiP
  Offset _pipOffset = const Offset(double.infinity, 0);
  bool _pipInitialized = false;

  @override
  void initState() {
    super.initState();

    _otherUserPhoto = widget.otherUserPhoto;
    _chatId = widget.chatId;

    // Pulse animation for ringing state
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Fade-in animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    _fetchOtherUserPhoto();

    if (widget.resumeExisting && CallOverlayManager.activeCall != null) {
      // Resuming from overlay â€“ reuse existing service
      final info = CallOverlayManager.activeCall!;
      _webRTCService = _existingService;
      _isConnected = info.isConnected;
      _callDurationSeconds = info.durationSeconds;
      _callWasAnswered = info.isConnected;
      if (_isConnected) {
        _pulseController.stop();
        _startCallTimer();
      }
    } else {
      _resolveChatId();
      _startCall();
    }
  }

  /// A static reference so the service survives across minimize/restore.
  static WebRTCService? _existingService;

  Future<void> _resolveChatId() async {
    if (_chatId != null) return;
    // Try to find or create a chatId between current user and other user.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: uid)
          .get();
      for (final doc in snap.docs) {
        final users = List<String>.from(doc.data()['users'] ?? []);
        if (users.contains(widget.otherUserId)) {
          _chatId = doc.id;
          return;
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchOtherUserPhoto() async {
    if (_otherUserPhoto != null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      if (mounted && doc.exists) {
        setState(() {
          _otherUserPhoto = doc.data()?['profileImageUrl'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _startCall() async {
    _webRTCService = WebRTCService(
      callId: widget.callId,
      isVideo: widget.isVideo,
      isReceiver: widget.isReceiver,
    );
    _existingService = _webRTCService;

    _webRTCService!.onAddRemoteStream = () {
      if (mounted) {
        setState(() => _isConnected = true);
        _callWasAnswered = true;
        _stopRingback();
        _ringTimeout?.cancel();
        _pulseController.stop();
        _startCallTimer();
        _writeCallLogMessage();
        // Sync overlay info
        CallOverlayManager.activeCall?.isConnected = true;
      }
    };

    _webRTCService!.onConnectionStateChange = () {
      if (mounted) _endCallLocally();
    };

    await _webRTCService!.init();

    // Write initial call log (will be updated when answered or ended)
    await _writeCallLogMessage();

    // Register in overlay manager
    CallOverlayManager.activeCall = ActiveCallInfo(
      callId: widget.callId,
      otherUserId: widget.otherUserId,
      otherUserName: widget.otherUserName,
      otherUserPhoto: _otherUserPhoto,
      chatId: _chatId,
      isVideo: widget.isVideo,
      isReceiver: widget.isReceiver,
    );

    if (widget.isReceiver) {
      await CallKitService.endAllCalls();
      // If opened via 'Accept' button in CallKit, auto-answer now
      if (widget.autoAnswer) {
        // Small delay to ensure init is complete
        Future.delayed(const Duration(milliseconds: 500), () {
          _webRTCService?.answerCall();
        });
      }
    } else {
      // Outgoing call: play ringback tone and set 30-second auto-timeout
      _startRingback();
      _ringTimeout = Timer(const Duration(seconds: 30), () {
        if (!_isConnected && mounted) _endCallLocally();
      });
    }
  }

  Future<void> _startRingback() async {
    _ringPlayer = AudioPlayer();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/ringback_tone.wav');
      if (!file.existsSync()) {
        file.writeAsBytesSync(_generateRingbackWav());
      }
      await _ringPlayer!.setFilePath(file.path);
      await _ringPlayer!.setLoopMode(LoopMode.one);
      await _ringPlayer!.setVolume(0.7);
      _ringPlayer!.play();
    } catch (e) {
      debugPrint('Ringback tone error: $e');
    }
  }

  void _stopRingback() {
    _ringPlayer?.stop();
    _ringPlayer?.dispose();
    _ringPlayer = null;
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
      CallOverlayManager.activeCall?.durationSeconds = _callDurationSeconds;
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // â”€â”€â”€ Minimize to floating overlay â”€â”€â”€
  void _minimizeCall() {
    if (CallOverlayManager.activeCall == null) return;
    // Update overlay info before minimizing
    final info = CallOverlayManager.activeCall!;
    info.durationSeconds = _callDurationSeconds;
    info.isConnected = _isConnected;
    _callTimer?.cancel();
    CallOverlayManager.showOverlay();
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/main');
      }
    }
  }

  // â”€â”€â”€ End call + write history â”€â”€â”€
  bool _isEndingCall = false;

  void _endCallLocally() {
    if (_isEndingCall) return; // guard against double-fire
    _isEndingCall = true;
    _stopRingback();
    _ringTimeout?.cancel();
    _callTimer?.cancel();
    _updateCallLogOnEnd();
    CallKitService.endAllCalls();
    CallOverlayManager.clearActiveCall();

    // Pop first, then dispose resources after the screen is removed.
    if (mounted) {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/main');
      }
    }

    // Defer hangUp so renderers aren't destroyed while the widget tree
    // still references them during the pop animation.
    Future.delayed(const Duration(milliseconds: 300), () {
      _webRTCService?.hangUp();
      _existingService = null;
    });
  }

  void _toggleSpeaker() {
    setState(() => _isSpeakerOn = !_isSpeakerOn);
    Helper.setSpeakerphoneOn(_isSpeakerOn);
  }

  @override
  void dispose() {
    _stopRingback();
    _ringTimeout?.cancel();
    _callTimer?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    // Only hang up if we're not minimising (overlay not active)
    if (CallOverlayManager.activeCall == null && !_isEndingCall) {
      _webRTCService?.hangUp();
      _existingService = null;
    }
    super.dispose();
  }

  // â”€â”€â”€ Call history in chat â”€â”€â”€
  Future<void> _writeCallLogMessage() async {
    if (_chatId == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    if (_callLogMessageId != null) return; // already written

    try {
      final ref = await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .add({
            'senderId': uid,
            'type': 'call',
            'callId': widget.callId,
            'isVideo': widget.isVideo,
            'callStatus': 'missed', // default, updated on end
            'callDuration': 0,
            'timestamp': FieldValue.serverTimestamp(),
          });
      _callLogMessageId = ref.id;
    } catch (_) {}
  }

  Future<void> _updateCallLogOnEnd() async {
    if (_chatId == null || _callLogMessageId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(_callLogMessageId)
          .update({
            'callStatus': _callWasAnswered ? 'answered' : 'missed',
            'callDuration': _callDurationSeconds,
          });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    if (!_pipInitialized) {
      _pipOffset = Offset(screenSize.width - 130, 100);
      _pipInitialized = true;
    }

    final showVideoFullscreen = widget.isVideo && _isConnected;
    final showAudioUI = !widget.isVideo || !_isConnected;

    return Scaffold(
      backgroundColor: const Color(0xFF0F111A),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Stack(
          children: [
            // Background for audio or connecting state
            if (showAudioUI) _buildAudioBackground(screenSize),

            // Fullscreen Remote Video
            if (showVideoFullscreen && _webRTCService != null)
              Positioned.fill(
                child: RTCVideoView(
                  _webRTCService!.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            // UI Elements (Avatar, Name, Status)
            if (showAudioUI) _buildCallingUI(screenSize),

            // Video overlays
            if (showVideoFullscreen) ...[
              Positioned(
                top: 0, left: 0, right: 0, height: 140,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 0, left: 0, right: 0, height: 200,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ],

            // Draggable local PiP
            if (widget.isVideo) _buildLocalVideoPiP(screenSize),

            // Top Bar
            _buildTopBar(),

            // Conditional Bottom Controls: Accept/Decline if incoming, else standard controls
            if (widget.isReceiver && !_isConnected)
              _buildIncomingResponseButtons()
            else
              _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioBackground(Size screenSize) {
    return Positioned.fill(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F111A), Color(0xFF1A1040), Color(0xFF0F111A)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: screenSize.height * 0.15,
              left: -60,
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [const Color(0xFF0F2F6A).withValues(alpha: 0.15), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCallingUI(Size screenSize) {
    return Positioned.fill(
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(height: screenSize.height * 0.12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 12, color: Colors.white.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text(
                  'End-to-end encrypted',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11),
                ),
              ],
            ),
            SizedBox(height: screenSize.height * 0.06),
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isConnected ? 1.0 : _pulseAnimation.value,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF0F2F6A).withValues(alpha: 0.5),
                        width: 3,
                      ),
                    ),
                    child: UserAvatar(
                      imageUrl: _otherUserPhoto,
                      name: widget.otherUserName,
                      radius: 56,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            Text(
              widget.otherUserName,
              style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _isConnected
                  ? _formatDuration(_callDurationSeconds)
                  : widget.isReceiver ? 'Incoming Call' : 'Ringing...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingResponseButtons() {
    return Positioned(
      bottom: 60,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildActionCircle(
              icon: Icons.call_end_rounded,
              color: const Color(0xFFFF3B30),
              label: 'Decline',
              onTap: _endCallLocally,
            ),
            _buildActionCircle(
              icon: widget.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
              color: const Color(0xFF34C759),
              label: 'Accept',
              onTap: () => _webRTCService?.answerCall(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCircle({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(36),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(36),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: _isMicOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      label: _isMicOn ? 'Mute' : 'Unmute',
                      isActive: !_isMicOn,
                      onTap: () {
                        _webRTCService?.toggleMic();
                        setState(() => _isMicOn = !_isMicOn);
                      },
                    ),
                    if (widget.isVideo)
                      _buildControlButton(
                        icon: _isCameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                        label: _isCameraOn ? 'Cam Off' : 'Cam On',
                        isActive: !_isCameraOn,
                        onTap: () {
                          _webRTCService?.toggleCamera();
                          setState(() => _isCameraOn = !_isCameraOn);
                        },
                      ),
                    _buildEndCallButton(),
                    _buildControlButton(
                      icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                      label: 'Speaker',
                      isActive: _isSpeakerOn,
                      onTap: _toggleSpeaker,
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

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isActive ? Colors.black : Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildEndCallButton() {
    return GestureDetector(
      onTap: _endCallLocally,
      child: Container(
        width: 64, height: 52,
        decoration: BoxDecoration(color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(26)),
        child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 28),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              IconButton(onPressed: _minimizeCall, icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white)),
              const Spacer(),
              if (_isConnected && widget.isVideo)
                IconButton(
                  onPressed: () {
                    _webRTCService?.switchCamera();
                    setState(() => _isFrontCamera = !_isFrontCamera);
                  },
                  icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocalVideoPiP(Size screenSize) {
    return Positioned(
      left: _pipOffset.dx, top: _pipOffset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _pipOffset = Offset(
              (_pipOffset.dx + details.delta.dx).clamp(8, screenSize.width - 118),
              (_pipOffset.dy + details.delta.dy).clamp(50, screenSize.height - 280),
            );
          });
        },
        child: Container(
          width: 110, height: 160,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _isCameraOn && _webRTCService != null
                ? RTCVideoView(_webRTCService!.localRenderer, mirror: _isFrontCamera, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                : Container(color: Colors.black, child: const Icon(Icons.videocam_off, color: Colors.white24)),
          ),
        ),
      ),
    );
  }
}
