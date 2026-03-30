import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/avatar_helper.dart';

import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import '../../services/push_notification_service.dart';
import 'post_detail_screen.dart';
import 'user_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final enabled = await PushNotificationService.areNotificationsEnabled();
    if (mounted) {
      setState(() => _notificationsEnabled = enabled);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await PushNotificationService.setNotificationsEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header – matches Figma: back arrow + "Notifications" title + toggle
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                   GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: context.textHigh,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // User Profile for context
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(FirebaseAuth.instance.currentUser?.uid)
                        .snapshots(),
                    builder: (context, userSnap) {
                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                      return UserAvatar(
                        imageUrl: AvatarHelper.getAvatarUrl(userData),
                        name: userData?['name'] ?? '',
                        radius: 14,
                      );
                    },
                  ),
                  Expanded(
                    child: Text(
                      context.t('notifications'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: context.textHigh,
                      ),
                    ),
                  ),
                  // Functional Toggle
                  GestureDetector(
                    onTap: () => _toggleNotifications(!_notificationsEnabled),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44,
                      height: 26,
                      decoration: BoxDecoration(
                        color: _notificationsEnabled ? context.primary : context.surfaceLightColor,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: AnimatedAlign(
                        duration: const Duration(milliseconds: 200),
                        alignment: _notificationsEnabled ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: context.bg,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.bg, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),

            // Notifications list
            Expanded(
              child: currentUser == null
                  ?  Center(
                      child: Text(
                        'Please log in',
                        style: TextStyle(color: context.textLow),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('notifications')
                          .where('targetUserId', isEqualTo: currentUser.uid)
                          .orderBy('timestamp', descending: true)
                          .limit(50)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: context.primary,
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text(
                                'Error loading notifications: ${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.redAccent.withOpacity(0.8)),
                              ),
                            ),
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: context.surfaceLightColor,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.notifications_none_rounded,
                                    size: 48,
                                    color: context.textLow,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No notifications yet',
                                  style: TextStyle(
                                    color: context.textHigh,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Activities will appear here',
                                  style: TextStyle(
                                    color: context.textMed,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final docs = snapshot.data!.docs;

                        // Group by Today / Yesterday / Earlier
                        final today = <QueryDocumentSnapshot>[];
                        final yesterday = <QueryDocumentSnapshot>[];
                        final earlier = <QueryDocumentSnapshot>[];

                        final now = DateTime.now();
                        for (var doc in docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          final ts = data['timestamp'] as Timestamp?;
                          if (ts == null) {
                            earlier.add(doc);
                            continue;
                          }
                          final date = ts.toDate();
                          final diff = now.difference(date);
                          if (diff.inDays == 0) {
                            today.add(doc);
                          } else if (diff.inDays == 1) {
                            yesterday.add(doc);
                          } else {
                            earlier.add(doc);
                          }
                        }

                        return ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            if (today.isNotEmpty) ...[
                              _buildSectionHeader('TODAY'),
                              ...today.map(
                                (doc) => _buildNotificationItem(
                                  context,
                                  doc,
                                  doc.data() as Map<String, dynamic>,
                                ),
                              ),
                            ],
                            if (yesterday.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildSectionHeader('YESTERDAY'),
                              ...yesterday.map(
                                (doc) => _buildNotificationItem(
                                  context,
                                  doc,
                                  doc.data() as Map<String, dynamic>,
                                ),
                              ),
                            ],
                            if (earlier.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              _buildSectionHeader('EARLIER'),
                              ...earlier.map(
                                (doc) => _buildNotificationItem(
                                  context,
                                  doc,
                                  doc.data() as Map<String, dynamic>,
                                ),
                              ),
                            ],
                            const SizedBox(height: 80),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4, left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: context.textLow,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    QueryDocumentSnapshot doc,
    Map<String, dynamic> data,
  ) {
    final type = data['type'] ?? 'general';
    final actorName = data['actorName'] ?? 'Someone';
    final message = data['message'] ?? '';
    final timestamp = data['timestamp'] as Timestamp?;
    final isRead = data['isRead'] ?? false;
    final isClassRequest = type == 'class_request';

    String timeAgo = '';
    if (timestamp != null) {
      final diff = DateTime.now().difference(timestamp.toDate());
      if (diff.inDays > 0) {
        timeAgo = '${diff.inDays}d ago';
      } else if (diff.inHours > 0) {
        timeAgo = '${diff.inHours}h ago';
      } else if (diff.inMinutes > 0) {
        timeAgo = '${diff.inMinutes}m ago';
      } else {
        timeAgo = 'Just now';
      }
    }

    // Show unread dot for new class requests
    final showUnreadDot = !isRead;

    return GestureDetector(
      onTap: () async {
        if (!isRead) {
          await doc.reference.update({'isRead': true});
        }
        final postId = data['postId'] as String?;
        final actorId = data['actorId'] as String?;
        
        if (type == 'follow' && actorId != null && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: actorId)),
          );
        } else if (postId != null && postId.isNotEmpty && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: showUnreadDot
                ? context.primary.withOpacity(0.15)
                : context.border,
          ),
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar or icon
              Stack(
                children: [
                UserAvatar(
                  imageUrl: AvatarHelper.getAvatarUrl(data),
                  name: actorName,
                  radius: 22,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/logo.png',
                        width: 14,
                        height: 14,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ],
            ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textHigh,
                          height: 1.4,
                        ),
                        children: [
                          TextSpan(
                            text: actorName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: context.textHigh,
                            ),
                          ),

                          TextSpan(text: ' $message'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        color: context.textLow,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (showUnreadDot)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.primary,
                  ),
                ),
            ],
          ),
          // Accept / Decline buttons for class requests
          if (isClassRequest) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleClassRequest(context, doc, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: context.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'Accept',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _handleClassRequest(context, doc, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.border),
                      ),
                      child: Center(
                        child: Text(
                          'Decline',
                          style: TextStyle(
                            color: context.textHigh,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      ),
    );
  }

  Future<void> _handleClassRequest(
    BuildContext context,
    QueryDocumentSnapshot doc,
    bool accepted,
  ) async {
    try {
      await doc.reference.update({
        'isRead': true,
        'type': accepted ? 'class_accepted' : 'class_declined',
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accepted
                  ? context.t('class_request_accepted')
                  : context.t('class_request_declined'),
            ),
            backgroundColor:
                accepted ? context.primary : Colors.grey,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {}
  }
}
