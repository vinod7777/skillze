import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'push_notification_service.dart';

class NotificationService {
  // ─── In-memory actor cache to avoid repeated Firestore reads ───────────────
  static String? _cachedActorName;
  static String? _cachedActorPhoto;
  static String? _cachedActorId;

  /// Call this on login / startup to pre-warm the actor cache.
  static Future<void> preCacheActor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_cachedActorId == user.uid) return; // Already cached
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _cachedActorName = doc.data()?['name'] ?? 'Someone';
      _cachedActorPhoto = doc.data()?['profileImageUrl'] ??
          doc.data()?['photoUrl'] ??
          doc.data()?['photoURL'];
      _cachedActorId = user.uid;
    } catch (e) {
      debugPrint('NotificationService.preCacheActor error: $e');
    }
  }

  /// Clear cache on logout.
  static void clearCache() {
    _cachedActorName = null;
    _cachedActorPhoto = null;
    _cachedActorId = null;
  }

  static Future<void> sendNotification({
    required String targetUserId,
    required String type,
    required String message,
    String? postId,
    String? commentId,
    String? chatId,
    String? actorName,
    String? actorPhoto,
    // Optional: pass pre-fetched FCM token to skip the Firestore read entirely
    String? recipientFcmToken,
    bool skipFirestoreNotification = false,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid == targetUserId) return;

    // ── Resolve actor info (zero-latency if cache is warm) ──────────────────
    final String finalActorName =
        actorName ?? _cachedActorName ?? 'Someone';
    final String? finalActorPhoto = actorPhoto ?? _cachedActorPhoto;

    // ── Kick off both tasks in parallel ─────────────────────────────────────
    Future<void>? firestoreTask;
    if (!skipFirestoreNotification) {
      firestoreTask = FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': targetUserId,
        'actorId': currentUser.uid,
        'actorName': finalActorName,
        'actorPhoto': finalActorPhoto,
        'type': type,
        'message': message,
        'postId': postId,
        'commentId': commentId,
        'chatId': chatId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    // ── Get FCM tokens (all devices supported) ──────────────────────────────
    List<String> tokens = [];
    if (recipientFcmToken != null && recipientFcmToken.isNotEmpty) {
      tokens.add(recipientFcmToken);
    } else {
      try {
        final targetDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(targetUserId)
            .get();
        
        final data = targetDoc.data();
        if (data != null) {
          // Check for array fcmTokens first, fallback to single fcmToken
          final List<dynamic>? arrayTokens = data['fcmTokens'];
          if (arrayTokens != null && arrayTokens.isNotEmpty) {
            tokens.addAll(arrayTokens.whereType<String>());
          } else if (data['fcmToken'] != null) {
            tokens.add(data['fcmToken']);
          }
        }
      } catch (e) {
        debugPrint('NotificationService: failed to fetch FCM tokens: $e');
      }
    }

    // ── Pre-process unique tokens ───────────────────────────────────────────
    final uniqueTokens = tokens.where((t) => t.isNotEmpty).toSet().toList();

    // ── Wait for Firestore write & send pushes in parallel ───────────────────
    final List<Future<void>> tasks = [];
    if (firestoreTask != null) tasks.add(firestoreTask);
    
    for (final token in uniqueTokens) {
      tasks.add(
        PushNotificationService.sendNotification(
          recipientToken: token,
          title: finalActorName,
          body: message,
          imageUrl: finalActorPhoto,
          extraData: {
            'type': type,
            'postId': postId ?? '',
            'chatId': chatId ?? '',
            'commentId': commentId ?? '',
            'senderId': currentUser.uid,
            'senderName': finalActorName,
            'senderPhoto': finalActorPhoto ?? '',
            'message': message,
          },
        ),
      );
    }

    await Future.wait(tasks);
  }
}
