import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter/material.dart';
import 'webrtc_service.dart';
import '../screens/main/call_screen.dart';
import 'push_notification_service.dart';
import 'call_overlay_manager.dart';

class CallKitService {
  static Future<void> init() async {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      _handleCallEvent(event);
    });

    // Initial check on startup
    await checkActiveCalls();
  }

  static Future<void> checkActiveCalls() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls is List && calls.isNotEmpty) {
        final call = calls.first;
        final data = Map<String, dynamic>.from(call['extra'] ?? {});
        final callId = data['callId'] as String?;
        final isVideo = data['isVideo'] == 'true';
        final callerId = data['callerId'] as String?;
        final callerName = data['callerName'] as String? ?? 'Unknown';

        // Check if this call was already accepted
        final isAccepted = (call['isAccepted'] == true) || (call['accepted'] == true);
        
        if (isAccepted && callId != null && callerId != null) {
          _navigateToCallScreen(
            callId: callId,
            otherUserId: callerId,
            otherUserName: callerName,
            isVideo: isVideo,
            isReceiver: true,
            autoAnswer: true,
            resumeExisting: true, // Try to resume if service already exists
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking active calls: $e");
    }
  }

  static Future<void> _handleCallEvent(CallEvent event) async {
    switch (event.event) {
      case Event.actionCallIncoming:
        break;
      case Event.actionCallStart:
        break;
      case Event.actionCallAccept:
        final data = Map<String, dynamic>.from(event.body['extra'] ?? {});
        final callId = data['callId'] as String?;
        final isVideo = data['isVideo'] == 'true';
        final callerId = data['callerId'] as String?;
        final callerName = data['callerName'] as String? ?? 'Unknown';

        if (callId != null && callerId != null) {
          // Small delay to let the app fully foreground before navigating
          await Future.delayed(const Duration(milliseconds: 500));
          _navigateToCallScreen(
            callId: callId,
            otherUserId: callerId,
            otherUserName: callerName,
            isVideo: isVideo,
            isReceiver: true,
            autoAnswer: true,
          );
        }
        break;
      case Event.actionCallDecline:
        final data = Map<String, dynamic>.from(event.body['extra'] ?? {});
        final callId = data['callId'] as String?;
        if (callId != null) {
          await WebRTCService.endCall(callId);
        }
        break;
      case Event.actionCallEnded:
        break;
      case Event.actionCallTimeout:
        final data = Map<String, dynamic>.from(event.body['extra'] ?? {});
        final callId = data['callId'] as String?;
        if (callId != null) {
          await WebRTCService.endCall(callId);
        }
        break;
      default:
        break;
    }
  }

  static Future<void> showCallNotification({
    required String callerId,
    required String callerName,
    required String callId,
    required bool isVideo,
  }) async {
    await FlutterCallkitIncoming.endAllCalls();

    CallKitParams callKitParams = CallKitParams(
      id: callId,
      nameCaller: callerName,
      appName: 'Feed Native',
      handle: isVideo ? 'Video Call' : 'Audio Call',
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{
        'callId': callId,
        'callerId': callerId,
        'callerName': callerName,
        'isVideo': isVideo.toString(),
      },
      headers: <String, dynamic>{'apiKey': 'v1'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        isShowFullLockedScreen: true,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(callKitParams);
  }

  static Future<void> endCall(String callId) async {
    await FlutterCallkitIncoming.endCall(callId);
  }

  static Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }

  static void _navigateToCallScreen({
    required String callId,
    required String otherUserId,
    required String otherUserName,
    required bool isVideo,
    required bool isReceiver,
    required bool autoAnswer,
    bool resumeExisting = false,
  }) {
    _tryNavigate(
      callId: callId,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      isVideo: isVideo,
      isReceiver: isReceiver,
      autoAnswer: autoAnswer,
      resumeExisting: resumeExisting,
      attempts: 0,
    );
  }

  static void _tryNavigate({
    required String callId,
    required String otherUserId,
    required String otherUserName,
    required bool isVideo,
    required bool isReceiver,
    required bool autoAnswer,
    required bool resumeExisting,
    required int attempts,
  }) {
    final navState = PushNotificationService.navigatorKey.currentState;
    
    if (navState == null) {
      if (attempts < 10) {
        // App is still starting up, wait and try again
        Future.delayed(const Duration(milliseconds: 500), () {
          _tryNavigate(
            callId: callId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            isVideo: isVideo,
            isReceiver: isReceiver,
            autoAnswer: autoAnswer,
            resumeExisting: resumeExisting,
            attempts: attempts + 1,
          );
        });
      }
      return;
    }

    // Check if we are already in this call to avoid duplicate screens
    // But if we are resuming, we DO want to ensure the screen is showing
    if (CallOverlayManager.activeCall != null &&
        CallOverlayManager.activeCall!.callId == callId) {
      if (!resumeExisting) return; 
    }

    navState.push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          callId: callId,
          otherUserId: otherUserId,
          otherUserName: otherUserName,
          isVideo: isVideo,
          isReceiver: isReceiver,
          autoAnswer: autoAnswer,
          resumeExisting: resumeExisting,
        ),
      ),
    );
  }
}
