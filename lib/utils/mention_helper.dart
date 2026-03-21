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
      final usersSnapshot = await FirebaseFirestore.instance.collection('users').get();
      
      // Map usernames to their respective User IDs
      for (var doc in usersSnapshot.docs) {
        final username = doc.data()['username'] as String?;
        final targetUserId = doc.id;
        
        if (username != null && 
            mentionedUsernames.contains(username) &&
            targetUserId != currentUserId) {
          
          // Dispatch the notification
          await NotificationService.sendNotification(
            targetUserId: targetUserId,
            type: notificationType,
            message: notificationMessage,
            postId: postId,
            commentId: commentId,
            chatId: chatId, // Pass chatId to the notification service
          );
        }
      }
    } catch (e) {
      debugPrint('Error processing mentions: $e');
    }
  }
}
