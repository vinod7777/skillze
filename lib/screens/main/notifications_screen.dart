import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/user_avatar.dart';

import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import '../../services/push_notification_service.dart';
import 'post_detail_screen.dart';

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
                                color: Colors.black.withValues(alpha: 0.1),
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
                  ? const Center(
                      child: Text(
                        'Please log in',
                        style: TextStyle(color: Color(0xFF71717A)),
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
                        if (snapshot.hasError ||
                            !snapshot.hasData ||
                            snapshot.data!.docs.isEmpty) {
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
    final actorPhoto = data['actorPhoto'] as String?;
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
        if (postId != null && postId.isNotEmpty && context.mounted) {
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
                ? context.primary.withValues(alpha: 0.15)
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
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(data['actorId']).snapshots(),
                builder: (context, userSnap) {
                  final userData = userSnap.data?.data() as Map<String, dynamic>?;
                  final displayAvatar = userData?['profileImageUrl'] ?? 
                                      userData?['authorProfileImageUrl'] ?? 
                                      userData?['photoUrl'] ?? 
                                      userData?['authorAvatar'] ?? 
                                      actorPhoto;
                  final displayName = userData?['name'] ?? actorName;

                  return UserAvatar(
                    imageUrl: displayAvatar,
                    name: displayName,
                    radius: 22,
                  );
                },
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
                            text: data['actorId'] != null ? '' : actorName, // We'll use StreamBuilder for the name too
                          ),
                          WidgetSpan(
                            child: StreamBuilder<DocumentSnapshot>(
                              stream: FirebaseFirestore.instance.collection('users').doc(data['actorId']).snapshots(),
                              builder: (context, userSnap) {
                                final userData = userSnap.data?.data() as Map<String, dynamic>?;
                                final displayName = userData?['name'] ?? actorName;
                                return Text(
                                  displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: context.textHigh,
                                  ),
                                );
                              },
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
                      child: const Center(
                        child: Text(
                          'Decline',
                          style: TextStyle(
                            color: Color(0xFF18181B),
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
                accepted ? const Color(0xFF0F2F6A) : Colors.grey,
          ),
        );
      }
    } catch (_) {}
  }
}
