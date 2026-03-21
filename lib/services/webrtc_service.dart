import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class WebRTCService {
  RTCPeerConnection? peerConnection;
  MediaStream? localStream;
  MediaStream? remoteStream;

  RTCVideoRenderer localRenderer = RTCVideoRenderer();
  RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  final String callId;
  final bool isVideo;
  final bool isReceiver;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  VoidCallback? onAddRemoteStream;
  VoidCallback? onConnectionStateChange;

  // Keep subscriptions so we can cancel them on hangUp
  final List<StreamSubscription> _subscriptions = [];
  bool _disposed = false;

  WebRTCService({
    required this.callId,
    required this.isVideo,
    required this.isReceiver,
  });

  Future<void> init() async {
    await localRenderer.initialize();
    await remoteRenderer.initialize();

    await _openUserMedia(localRenderer, remoteRenderer);
    peerConnection = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
        {'urls': 'stun:stun2.l.google.com:19302'},
        {'urls': 'stun:stun3.l.google.com:19302'},
        {'urls': 'stun:stun4.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });

    _registerPeerConnectionListeners();

    localStream?.getTracks().forEach((track) {
      peerConnection?.addTrack(track, localStream!);
    });

    if (!isReceiver) {
      await _createOffer();
    }
    // Note: Receiver must call answerCall() manually from the UI
  }

  Future<void> answerCall() async {
    if (isReceiver) {
      await _joinCall();
    }
  }


  Future<void> _openUserMedia(
    RTCVideoRenderer localVideo,
    RTCVideoRenderer remoteVideo,
  ) async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': true,
      'video': isVideo ? {'facingMode': 'user'} : false,
    };

    try {
      var stream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      localVideo.srcObject = stream;
      localStream = stream;
    } catch (e) {
      debugPrint("Error opening user media: $e");
    }
  }

  void _registerPeerConnectionListeners() {
    peerConnection?.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint('ICE gathering state: $state');
    };

    peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Connection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        if (!_disposed) onConnectionStateChange?.call();
      }
    };

    peerConnection?.onSignalingState = (RTCSignalingState state) {
      debugPrint('Signaling state: $state');
    };

    // unified-plan: use onTrack (onAddStream is deprecated)
    peerConnection?.onTrack = (RTCTrackEvent event) {
      debugPrint("onTrack: ${event.track.kind}");
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        remoteStream = event.streams[0];
        if (!_disposed) onAddRemoteStream?.call();
      }
    };

    // Keep onAddStream as fallback for older devices
    peerConnection?.onAddStream = (MediaStream stream) {
      debugPrint("onAddStream (fallback)");
      remoteRenderer.srcObject = stream;
      remoteStream = stream;
      if (!_disposed) onAddRemoteStream?.call();
    };
  }

  Future<void> _createOffer() async {
    final callerCandidatesCollection = _firestore
        .collection('calls')
        .doc(callId)
        .collection('callerCandidates');
    final roomDoc = _firestore.collection('calls').doc(callId);

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidatesCollection.add(candidate.toMap());
    };

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);

    final roomWithOffer = {
      'offer': {'type': offer.type, 'sdp': offer.sdp},
      'status': 'calling',
      'createdAt': FieldValue.serverTimestamp(),
    };

    await roomDoc.set(roomWithOffer, SetOptions(merge: true));

    // Listen for remote answer
    _subscriptions.add(
      roomDoc.snapshots().listen((snapshot) async {
        if (_disposed || peerConnection == null) return;
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null &&
              data.containsKey('answer') &&
              peerConnection?.signalingState !=
                  RTCSignalingState.RTCSignalingStateStable) {
            final answer = RTCSessionDescription(
              data['answer']['sdp'],
              data['answer']['type'],
            );
            try {
              await peerConnection?.setRemoteDescription(answer);
            } catch (e) {
              debugPrint("Remote description error: $e");
            }
          }

          if (data != null && data['status'] == 'ended') {
            if (!_disposed) onConnectionStateChange?.call();
          }
        }
      }),
    );

    // Listen for remote ICE candidates
    _subscriptions.add(
      _firestore
          .collection('calls')
          .doc(callId)
          .collection('calleeCandidates')
          .snapshots()
          .listen((snapshot) {
            if (_disposed || peerConnection == null) return;
            for (var change in snapshot.docChanges) {
              if (change.type == DocumentChangeType.added) {
                final data = change.doc.data() as Map<String, dynamic>;
                peerConnection?.addCandidate(
                  RTCIceCandidate(
                    data['candidate'],
                    data['sdpMid'],
                    data['sdpMLineIndex'],
                  ),
                );
              }
            }
          }),
    );
  }

  Future<void> _joinCall() async {
    final roomDoc = _firestore.collection('calls').doc(callId);

    // Wait for the offer to be ready (caller may still be writing it)
    DocumentSnapshot<Map<String, dynamic>>? roomSnapshot;
    for (int attempt = 0; attempt < 10; attempt++) {
      roomSnapshot = await roomDoc.get();
      if (roomSnapshot.exists &&
          roomSnapshot.data() != null &&
          roomSnapshot.data()!.containsKey('offer')) {
        break;
      }
      debugPrint("Waiting for offer (attempt ${attempt + 1})...");
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (roomSnapshot == null ||
        !roomSnapshot.exists ||
        !roomSnapshot.data()!.containsKey('offer')) {
      debugPrint("Call does not exist or offer not ready after retries.");
      onConnectionStateChange?.call();
      return;
    }

    final calleeCandidatesCollection = roomDoc.collection('calleeCandidates');

    peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      calleeCandidatesCollection.add(candidate.toMap());
    };

    final offer = roomSnapshot.data()!['offer'];
    await peerConnection?.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);

    final roomWithAnswer = {
      'answer': {'type': answer.type, 'sdp': answer.sdp},
      'status': 'answered',
    };

    await roomDoc.update(roomWithAnswer);

    // Listen to changes for ended
    _subscriptions.add(
      roomDoc.snapshots().listen((snapshot) {
        if (_disposed) return;
        if (snapshot.exists && snapshot.data()?['status'] == 'ended') {
          if (!_disposed) onConnectionStateChange?.call();
        }
      }),
    );

    // Listen for remote ICE candidates
    _subscriptions.add(
      roomDoc.collection('callerCandidates').snapshots().listen((snapshot) {
        if (_disposed || peerConnection == null) return;
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data() as Map<String, dynamic>;
            peerConnection?.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              ),
            );
          }
        }
      }),
    );
  }

  Future<void> hangUp() async {
    _disposed = true;

    // Cancel all Firestore listeners first
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();

    try {
      localStream?.getTracks().forEach((track) {
        track.stop();
      });
      localStream = null;
      await peerConnection?.close();
      peerConnection = null;

      try {
        await localRenderer.dispose();
      } catch (_) {}
      try {
        await remoteRenderer.dispose();
      } catch (_) {}

      await _firestore.collection('calls').doc(callId).update({
        'status': 'ended',
      });
    } catch (e) {
      debugPrint("Hangup error: $e");
    }
  }

  void toggleMic() {
    if (localStream != null && localStream!.getAudioTracks().isNotEmpty) {
      bool enabled = localStream!.getAudioTracks()[0].enabled;
      localStream!.getAudioTracks()[0].enabled = !enabled;
    }
  }

  void toggleCamera() {
    if (localStream != null &&
        isVideo &&
        localStream!.getVideoTracks().isNotEmpty) {
      bool enabled = localStream!.getVideoTracks()[0].enabled;
      localStream!.getVideoTracks()[0].enabled = !enabled;
    }
  }

  void switchCamera() {
    if (localStream != null &&
        isVideo &&
        localStream!.getVideoTracks().isNotEmpty) {
      Helper.switchCamera(localStream!.getVideoTracks()[0]);
    }
  }

  static Future<void> endCall(String callId) async {
    try {
      await FirebaseFirestore.instance.collection('calls').doc(callId).update({
        'status': 'ended',
      });
    } catch (_) {}
  }
}
