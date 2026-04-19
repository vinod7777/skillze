import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import 'push_notification_service.dart';

enum CallState { idle, connecting, ringing, connected, ended }

class CallService {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  CallState callState = CallState.idle;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? _roomId;
  String? _callerId;
  bool _isVideo = false;
  bool? _isCallerInThisSession;

  Timer? _watchdogTimer;
  StreamSubscription? _roomSubscription;
  StreamSubscription? _remoteCandidatesSubscription;

  Function(MediaStream stream)? onLocalStream;
  Function(MediaStream stream)? onRemoteStream;
  Function(CallState state)? onCallStateChanged;
  Function()? onCallEnded;

  Function(String callId, String callerName, String callerAvatar, bool isVideo)? onIncomingCall;

  // We map the codelab logic via CallService
  // In the codelab, they had "collectIceCandidates". We'll do exactly that.

  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  Future<void> initialize() async {
    _callerId = FirebaseAuth.instance.currentUser?.uid;
  }

  Future<bool> requestPermissions(bool isVideo) async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.microphone,
      if (isVideo) Permission.camera,
    ].request();

    return statuses.values.every((status) => status.isGranted);
  }

  void listenForIncomingCalls() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    FirebaseFirestore.instance
        .collection('calls')
        .where('calleeId', isEqualTo: uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && onIncomingCall != null) {
             onIncomingCall!(
               change.doc.id,
               data['callerName'] ?? 'Unknown Caller',
               data['callerAvatar'] ?? '',
               data['isVideo'] ?? false,
             );
          }
        }
      }
    });
  }

  void _setCallState(CallState state) {
    callState = state;
    onCallStateChanged?.call(state);
    debugPrint("CallState changed to: $state");
  }

  Future<void> _openUserMedia(bool isVideo) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      onLocalStream?.call(_localStream!);
    } catch (e) {
      debugPrint("Error opening user media: $e");
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_rtcConfig);

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (_roomId != null) {
        // Collect local ICE candidates and add them to Firestore
        // If I am the person who started the call, I write to callerCandidates
        // If I am the person who joined the call, I write to calleeCandidates
        final bool isCaller = _isCallerInThisSession ?? false;
        final collectionName = isCaller ? 'callerCandidates' : 'calleeCandidates';
        
        FirebaseFirestore.instance
            .collection('calls')
            .doc(_roomId)
            .collection(collectionName)
            .add(candidate.toMap());
      }
    };

    _peerConnection?.onTrack = (RTCTrackEvent event) {
      debugPrint('Got remote track: ${event.streams[0]}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    // Add local tracks to peer connection
    if (_localStream != null) {
      for (var track in _localStream!.getTracks()) {
        _peerConnection?.addTrack(track, _localStream!);
      }
    }
  }

  // 6. Creating a new room (from Codelab)
  Future<String> startCall({
    required String calleeId,
    required String calleeName,
    String? calleeAvatar,
    required String chatId,
    bool isVideo = false,
  }) async {
    if (!(await requestPermissions(isVideo))) return "";
    _isVideo = isVideo;
    _setCallState(CallState.connecting);

    await _openUserMedia(isVideo);
    await _createPeerConnection();

    _isCallerInThisSession = true;
    final roomRef = FirebaseFirestore.instance.collection('calls').doc();
    _roomId = roomRef.id;
    _callerId = FirebaseAuth.instance.currentUser?.uid;

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    final roomWithOffer = {
      'offer': {
        'type': offer.type,
        'sdp': offer.sdp,
      },
      'callerId': _callerId,
      'calleeId': calleeId,
      'callerName': FirebaseAuth.instance.currentUser?.displayName ?? 'A user',
      'callerAvatar': FirebaseAuth.instance.currentUser?.photoURL ?? '',
      'status': 'ringing',
      'chatId': chatId,
      'isVideo': isVideo,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await roomRef.set(roomWithOffer);
    
    // Listen for remote answer
    _roomSubscription = roomRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;

      if (_peerConnection?.getRemoteDescription() == null && data['answer'] != null) {
        debugPrint('Got remote answer');
        final answer = RTCSessionDescription(
          data['answer']['sdp'],
          data['answer']['type'],
        );
        await _peerConnection!.setRemoteDescription(answer);
        _setCallState(CallState.connected);
        _watchdogTimer?.cancel();
      }

      if (data['status'] == 'ended' || data['status'] == 'declined') {
        endCall();
      }
    });

    // Send push notification to callee
    await PushNotificationService.sendCallNotification(
      receiverId: calleeId,
      callId: _roomId!,
      chatId: chatId,
      callerName: roomWithOffer['callerName'] as String,
      callerAvatar: roomWithOffer['callerAvatar'] as String,
      isVideo: isVideo,
    );

    // 8. Collect remote ICE candidates (From Codelab logic)
    _listenForRemoteIceCandidates('calleeCandidates');

    // Timeout if no answer in 30 seconds
    _watchdogTimer = Timer(const Duration(seconds: 30), () {
      if (callState == CallState.connecting) {
        endCall();
      }
    });

    return _roomId!;
  }

  // 7. Joining a room (from Codelab)
  Future<void> answerCall(String callId) async {
    _isCallerInThisSession = false;
    _roomId = callId;
    _setCallState(CallState.connecting);

    final roomRef = FirebaseFirestore.instance.collection('calls').doc(callId);
    final roomSnapshot = await roomRef.get();
    
    if (!roomSnapshot.exists) {
      endCall();
      return;
    }

    final data = roomSnapshot.data() as Map<String, dynamic>;
    _isVideo = data['isVideo'] ?? false;
    if (!(await requestPermissions(_isVideo))) {
      endCall();
      return;
    }
    _callerId = data['calleeId']; // We are the callee!
    
    await _openUserMedia(_isVideo);
    await _createPeerConnection();

    final offerData = data['offer'];
    if (offerData != null) {
      final offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
      await _peerConnection!.setRemoteDescription(offer);
    }

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    final roomWithAnswer = {
      'answer': {
        'type': answer.type,
        'sdp': answer.sdp,
      },
      'status': 'connected',
    };

    await roomRef.update(roomWithAnswer);
    _setCallState(CallState.connected);

    // Listen for remote ICE candidates (from caller)
    _listenForRemoteIceCandidates('callerCandidates');

    // Listen for call ended status
    _roomSubscription = roomRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      if (data['status'] == 'ended') {
        endCall();
      }
    });
  }

  void _listenForRemoteIceCandidates(String collectionName) {
    _remoteCandidatesSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(_roomId)
        .collection(collectionName)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final candidate = RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          );
          _peerConnection?.addCandidate(candidate);
        }
      }
    });
  }

  Future<void> declineCall([String? callId]) async {
    final idToDecline = callId ?? _roomId;
    if (idToDecline != null) {
      await FirebaseFirestore.instance.collection('calls').doc(idToDecline).update({
        'status': 'declined',
      });
    }
  }

  Future<void> endCall() async {
    if (_roomId != null) {
      try {
        await FirebaseFirestore.instance.collection('calls').doc(_roomId).update({
          'status': 'ended',
        });
      } catch (_) {}
    }

    _watchdogTimer?.cancel();
    _roomSubscription?.cancel();
    _remoteCandidatesSubscription?.cancel();

    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    _localStream?.dispose();
    _localStream = null;

    _peerConnection?.close();
    _peerConnection?.dispose();
    _peerConnection = null;

    _roomId = null;
    _setCallState(CallState.ended);
    onCallEnded?.call();
    _setCallState(CallState.idle);
  }

  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        final track = audioTracks.first;
        track.enabled = !track.enabled;
      }
    }
  }

  void toggleSpeakerphone(bool isSpeaker) {
     _localStream?.getAudioTracks().forEach((track) {
        // Audio output routing relies on OS routing, but WebRTC has tools
        // In mobile, we might need flutter_webrtc helper to route audio
        // For simplicity, we just use the native default behavior
        Helper.setSpeakerphoneOn(isSpeaker);
     });
  }
}
