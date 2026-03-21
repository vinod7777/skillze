import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static Future<void> sendNotification({
    required String targetUserId,
    required String type,
    required String message,
    String? postId,
    String? commentId,
    String? chatId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.uid == targetUserId) return;

    try {
      // Get current user data for the actor name
      final actorDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final actorName = actorDoc.data()?['name'] ?? 'Someone';

      await FirebaseFirestore.instance.collection('notifications').add({
        'targetUserId': targetUserId,
        'actorId': currentUser.uid,
        'actorName': actorName,
        'type': type,
        'message': message,
        'postId': postId,
        'commentId': commentId,
        'chatId': chatId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }
}
