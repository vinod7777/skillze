import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/call_service.dart';

class CallScreen extends StatefulWidget {
  final bool isIncoming;
  final String? callId;

  const CallScreen({
    super.key,
    required this.isIncoming,
    this.callId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final CallService _callService = CallService();
  
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  
  bool _isMuted = false;
  bool _isSpeaker = false;
  CallState _callState = CallState.connecting;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    
    _callService.onCallStateChanged = (state) {
      if (mounted) setState(() => _callState = state);
      if (state == CallState.ended) {
        if (mounted) Navigator.pop(context);
      }
    };

    _callService.onLocalStream = (stream) {
      if (mounted) {
        _localRenderer.srcObject = stream;
        setState(() {});
      }
    };

    _callService.onRemoteStream = (stream) {
      if (mounted) {
        _remoteRenderer.srcObject = stream;
        setState(() {});
      }
    };

    _callService.onCallEnded = () {
      if (mounted) {
        Navigator.pop(context);
      }
    };
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    
    // Default speaker to false for voice, true for video (we'll assume voice by default here)
    _callService.toggleSpeakerphone(_isSpeaker);
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  void _endCall() {
    _callService.endCall();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    _callService.toggleMute();
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeaker = !_isSpeaker;
    });
    _callService.toggleSpeakerphone(_isSpeaker);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Remote Video or Avatar
          if (_remoteRenderer.srcObject != null && _remoteRenderer.srcObject!.getVideoTracks().isNotEmpty)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.grey[900]!, Colors.black],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                      ),
                      child: const CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.white10,
                        child: Icon(Icons.person, size: 60, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _callState == CallState.connecting ? 'CONNECTING...' : 
                      _callState == CallState.connected ? 'CONNECTED' : 'ENDED',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Top Bar with Minimize button
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 28),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.green, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'End-to-end encrypted',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 44), // To balance the back button
              ],
            ),
          ),

          // Local Video (PiP)
          if (_localRenderer.srcObject != null && _localRenderer.srcObject!.getVideoTracks().isNotEmpty)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              right: 20,
              child: Container(
                width: 100,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // Bottom Controls
          Positioned(
            bottom: 40,
            left: 30,
            right: 30,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(30),
               // blur background could be added with BackdropFilter
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _controlButton(
                    icon: _isSpeaker ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: 'Speaker',
                    isActive: _isSpeaker,
                    onTap: _toggleSpeaker,
                  ),
                  _controlButton(
                    icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: 'Mute',
                    isActive: _isMuted,
                    onTap: _toggleMute,
                  ),
                  _controlButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.redAccent,
                    iconColor: Colors.white,
                    onTap: _endCall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
    Color? iconColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color ?? (isActive ? Colors.white : Colors.white.withValues(alpha: 0.1)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon, 
              color: iconColor ?? (isActive ? Colors.black : Colors.white), 
              size: 28
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 10,
            fontWeight: FontWeight.w500
          ),
        )
      ],
    );
  }
}
