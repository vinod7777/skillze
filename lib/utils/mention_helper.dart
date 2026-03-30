import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/notification_service.dart';

class MentionHelper {
  /// Extracts all mentions starting with '@' from the given text.
  /// Returns a list of unique usernames (without the '@' symbol).
  static List<String> extractMentions(String text) {
    if (text.isEmpty) return [];

    final RegExp mentionRegex = RegExp(r'@([a-zA-Z0-9_]+)');
    final matches = mentionRegex.allMatches(text);

    return matches
        .map((m) => m.group(1)!)
        .toSet() // Remove duplicates
        .toList();
  }

  /// Processes text to find mentions and sends notifications to the mentioned users.
  static Future<void> processMentions({
    required String text,
    required String currentUserId,
    required String currentUserName,
    required String notificationType,
    required String notificationMessage,
    String? postId,
    String? commentId,
    String? chatId,
  }) async {
    final mentionedUsernames = extractMentions(text);
    if (mentionedUsernames.isEmpty) return;

    try {
      // Chunk mentioned usernames to handle Firestore 'whereIn' limits (10-30 depending on SDK)
      // Usually 30 for modern Web/Admin SDKs, 10 for some older ones.
      // We'll use 10 to be safe.
      for (int i = 0; i < mentionedUsernames.length; i += 10) {
        final chunk = mentionedUsernames.sublist(
          i,
          i + 10 > mentionedUsernames.length ? mentionedUsernames.length : i + 10,
        );

        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('username', whereIn: chunk)
            .get();

        for (var doc in query.docs) {
          final targetUserId = doc.id;
          
          if (targetUserId != currentUserId) {
            // Dispatch the notification (this now sends both Firestore & Push/FCM via NotificationService update)
            await NotificationService.sendNotification(
              targetUserId: targetUserId,
              type: notificationType,
              message: notificationMessage,
              postId: postId,
              commentId: commentId,
              chatId: chatId,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error processing mentions: $e');
    }
  }
}
