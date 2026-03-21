import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/user_avatar.dart';
import '../screens/main/call_screen.dart';
import 'push_notification_service.dart';

/// Holds the state of the currently active (minimised) call so the overlay
/// bubble and the full-screen [CallScreen] can share it.
class ActiveCallInfo {
  final String callId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;
  final String? chatId;
  final bool isVideo;
  final bool isReceiver;

  /// Elapsed seconds â€“ updated by [CallScreen].
  int durationSeconds;
  bool isConnected;

  ActiveCallInfo({
    required this.callId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
    this.chatId,
    required this.isVideo,
    required this.isReceiver,
    this.durationSeconds = 0,
    this.isConnected = false,
  });
}

class CallOverlayManager {
  CallOverlayManager._();

  static OverlayEntry? _overlayEntry;
  static ActiveCallInfo? activeCall;
  static Timer? _uiTimer;

  /// Show the floating mini-call bubble.
  static void showOverlay() {
    removeOverlay(); // ensure no duplicate

    final navState = PushNotificationService.navigatorKey.currentState;
    if (navState == null || activeCall == null) return;

    final overlay = navState.overlay;
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(builder: (_) => const _FloatingCallBubble());
    overlay.insert(_overlayEntry!);

    // Tick the overlay UI every second so the timer updates.
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _overlayEntry?.markNeedsBuild();
    });
  }

  /// Remove the floating bubble.
  static void removeOverlay() {
    _uiTimer?.cancel();
    _uiTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  /// Clear everything â€“ called when the call truly ends.
  static void clearActiveCall() {
    removeOverlay();
    activeCall = null;
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// The draggable floating bubble Widget shown as an OverlayEntry.
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _FloatingCallBubble extends StatefulWidget {
  const _FloatingCallBubble();

  @override
  State<_FloatingCallBubble> createState() => _FloatingCallBubbleState();
}

class _FloatingCallBubbleState extends State<_FloatingCallBubble> {
  Offset _offset = const Offset(16, 100);

  void _openFullScreen() {
    final info = CallOverlayManager.activeCall;
    if (info == null) return;

    CallOverlayManager.removeOverlay();

    final ctx = PushNotificationService.navigatorKey.currentContext;
    if (ctx == null) return;

    Navigator.of(ctx).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: info.callId,
          otherUserId: info.otherUserId,
          otherUserName: info.otherUserName,
          otherUserPhoto: info.otherUserPhoto,
          chatId: info.chatId,
          isVideo: info.isVideo,
          isReceiver: info.isReceiver,
          resumeExisting: true,
        ),
      ),
    );
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final info = CallOverlayManager.activeCall;
    if (info == null) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _offset = Offset(
              (_offset.dx + d.delta.dx).clamp(0, screenSize.width - 200),
              (_offset.dy + d.delta.dy).clamp(40, screenSize.height - 70),
            );
          });
        },
        onTap: _openFullScreen,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0F2F6A).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UserAvatar(
                  imageUrl: info.otherUserPhoto,
                  name: info.otherUserName,
                  radius: 18,
                  backgroundColor: Colors.white24,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      info.otherUserName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      info.isConnected
                          ? _fmt(info.durationSeconds)
                          : 'Connectingâ€¦',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.open_in_full_rounded,
                    color: Colors.white,
                    size: 14,
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
