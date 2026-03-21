import 'package:cloud_firestore/cloud_firestore.dart';

class Story {
  final String id;
  final String userId;
  final String userName;
  final String userAvatar;
  final String mediaUrl;
  final String caption;
  final String type; // 'image' or 'video'
  final DateTime timestamp;
  final List<String> seenBy;

  Story({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userAvatar,
    required this.mediaUrl,
    this.caption = '',
    required this.type,
    required this.timestamp,
    this.seenBy = const [],
  });

  factory Story.fromDoc(DocumentSnapshot doc) {
    if (!doc.exists) {
      return Story(
        id: '',
        userId: '',
        userName: '',
        userAvatar: '',
        mediaUrl: '',
        caption: '',
        type: 'image',
        timestamp: DateTime.now(),
        seenBy: [],
      );
    }
    final data = doc.data() as Map<String, dynamic>;
    Timestamp? ts = data['timestamp'] as Timestamp?;
    return Story(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      userAvatar: data['userAvatar'] ??
          data['authorProfileImageUrl'] ??
          data['profileImageUrl'] ??
          data['photoUrl'] ??
          '',
      mediaUrl: data['mediaUrl'] ?? '',
      caption: data['caption'] ?? '',
      type: data['type'] ?? 'image',
      timestamp: ts?.toDate() ?? DateTime.now(),
      seenBy: List<String>.from(data['seenBy'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userAvatar': userAvatar,
      'mediaUrl': mediaUrl,
      'caption': caption,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
      'seenBy': seenBy,
    };
  }
}
