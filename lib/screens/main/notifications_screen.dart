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
import 'conversation_screen.dart';
import '../../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _notificationsEnabled = true;
  List<String> _followingList = [];

  @override
  void initState() {
    super.initState();
    _loadNotificationPreference();
  }

  Future<void> _loadNotificationPreference() async {
    final enabled = await PushNotificationService.areNotificationsEnabled();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _followingList = List<String>.from(doc.data()?['followingList'] ?? []);
        });
      }
    } else {
      if (mounted) {
        setState(() => _notificationsEnabled = enabled);
      }
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
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textHigh, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          context.t('notifications'),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: context.textHigh,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _notificationsEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              color: _notificationsEnabled ? context.primary : context.textLow,
              size: 22,
            ),
            onPressed: () => _toggleNotifications(!_notificationsEnabled),
          ),
          if (currentUser != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton(
                icon: Icon(Icons.done_all_rounded, color: context.primary, size: 22),
                tooltip: 'Mark all as read',
                onPressed: () => _markAllAsRead(currentUser.uid),
              ),
            ),
        ],
      ),
      body: currentUser == null
          ? Center(
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: context.primary));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Error loading notifications: ${snapshot.error}',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.redAccent)),
                    ),
                  );
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return _buildEmptyState();
                }

                final docs = snapshot.data!.docs;
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
                  if (diff.inDays == 0 && now.day == date.day) {
                    today.add(doc);
                  } else if (diff.inDays <= 1) {
                    yesterday.add(doc);
                  } else {
                    earlier.add(doc);
                  }
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    if (today.isNotEmpty) ...[
                      _buildSectionHeader('TODAY'),
                      ...today.map((doc) => _buildNotificationRow(context, doc)),
                    ],
                    if (yesterday.isNotEmpty) ...[
                      _buildSectionHeader('YESTERDAY'),
                      ...yesterday.map((doc) => _buildNotificationRow(context, doc)),
                    ],
                    if (earlier.isNotEmpty) ...[
                      _buildSectionHeader('EARLIER'),
                      ...earlier.map((doc) => _buildNotificationRow(context, doc)),
                    ],
                    const SizedBox(height: 80),
                  ],
                );
              },
            ),
    );
  }

  Widget _buildEmptyState() {
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
            child: Icon(Icons.notifications_none_rounded, size: 48, color: context.textLow),
          ),
          const SizedBox(height: 16),
          Text(
            'No notifications yet',
            style: TextStyle(color: context.textHigh, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Activities will appear here',
            style: TextStyle(color: context.textMed, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: context.textLow,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNotificationRow(BuildContext context, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] ?? 'general';
    final actorName = data['actorName'] ?? 'Someone';
    final message = data['message'] ?? '';
    final timestamp = data['timestamp'] as Timestamp?;
    final isRead = data['isRead'] ?? false;
    final actorId = data['actorId'] as String?;
    final postId = data['postId'] as String?;
    final chatId = data['chatId'] as String?;

    String timeAgo = '';
    if (timestamp != null) {
      final diff = DateTime.now().difference(timestamp.toDate());
      if (diff.inDays > 0) {
        timeAgo = '${diff.inDays}d';
      } else if (diff.inHours > 0) {
        timeAgo = '${diff.inHours}h';
      } else if (diff.inMinutes > 0) {
        timeAgo = '${diff.inMinutes}m';
      } else {
        timeAgo = 'now';
      }
    }

    return Dismissible(
      key: Key(doc.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) => doc.reference.delete(),
      child: InkWell(
        onTap: () async {
          if (!isRead) await doc.reference.update({'isRead': true});
          _handleCoreAction(type, actorId, postId, chatId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar with unread indicator
                  Stack(
                    children: [
                      UserAvatar(
                        imageUrl: AvatarHelper.getAvatarUrl(data),
                        name: actorName,
                        radius: 24,
                      ),
                      if (!isRead)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: context.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: context.bg, width: 2),
                            ),
                          ),
                        ),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: _buildTypeIcon(type),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: context.textHigh,
                              height: 1.4,
                              fontFamily: 'Inter',
                            ),
                            children: [
                              TextSpan(
                                text: actorName,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' $message',
                                style: TextStyle(
                                  color: isRead ? context.textMed : context.textHigh,
                                  fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          timeAgo,
                          style: TextStyle(
                            color: context.textLow,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        // Action Area for Professional feel
                        _buildActionArea(doc, type, actorId, postId, chatId, actorName),
                      ],
                    ),
                  ),
                  // Tool Menu
                  _buildOptionsMenu(doc, isRead),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'follow':
        icon = Icons.person_add_rounded;
        color = Colors.blue;
        break;
      case 'like':
        icon = Icons.favorite_rounded;
        color = Colors.red;
        break;
      case 'comment':
        icon = Icons.chat_bubble_rounded;
        color = Colors.green;
        break;
      case 'chat':
      case 'message':
        icon = Icons.mail_rounded;
        color = Colors.orange;
        break;
      case 'mention':
        icon = Icons.alternate_email_rounded;
        color = Colors.purple;
        break;
      default:
        icon = Icons.notifications_rounded;
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: context.bg, shape: BoxShape.circle),
      child: Icon(icon, size: 12, color: color),
    );
  }

  Widget _buildActionArea(QueryDocumentSnapshot doc, String type, String? actorId, String? postId, String? chatId, String actorName) {
    if (type == 'class_request') {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            _buildQuickAction('Accept', () => _handleClassRequest(context, doc, true), isPrimary: true),
            const SizedBox(width: 8),
            _buildQuickAction('Decline', () => _handleClassRequest(context, doc, false)),
          ],
        ),
      );
    }

    final isFollowingActor = actorId != null && _followingList.contains(actorId);
    final List<Widget> actions = [];

    if (type == 'follow' && actorId != null) {
      if (!isFollowingActor) {
        actions.add(_buildQuickAction('Follow Back', () => _followWork(actorId), isPrimary: true));
      }
      actions.add(_buildQuickAction('View Profile', () => _navToProfile(actorId)));
    } else if (type == 'chat' || type == 'message') {
      actions.add(_buildQuickAction('Open Chat', () => _navToChat(chatId, actorId, actorName), isPrimary: true));
      actions.add(_buildQuickAction('View Profile', () => _navToProfile(actorId)));
    } else if (postId != null && postId.isNotEmpty) {
      actions.add(_buildQuickAction('View Post', () => _navToPost(postId), isPrimary: true));
      actions.add(_buildQuickAction('View Profile', () => _navToProfile(actorId)));
    }

    if (actions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: actions,
      ),
    );
  }

  Widget _buildQuickAction(String label, VoidCallback onTap, {bool isPrimary = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isPrimary ? context.primary : (context.isDark ? Colors.white12 : Colors.grey[100]),
          borderRadius: BorderRadius.circular(6),
          border: isPrimary ? null : Border.all(color: context.border.withValues(alpha: 0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isPrimary ? Colors.white : context.textHigh,
          ),
        ),
      ),
    );
  }

  Widget _buildOptionsMenu(QueryDocumentSnapshot doc, bool isRead) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 20, color: context.textLow),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (val) {
        if (val == 'unread') doc.reference.update({'isRead': false});
        if (val == 'read') doc.reference.update({'isRead': true});
        if (val == 'delete') doc.reference.delete();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: isRead ? 'unread' : 'read',
          child: Row(
            children: [
              Icon(isRead ? Icons.mark_chat_unread_rounded : Icons.mark_chat_read_rounded, size: 18),
              const SizedBox(width: 10),
              Text(isRead ? 'Mark as unread' : 'Mark as read'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Delete notification', style: TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ],
    );
  }

  void _handleCoreAction(String type, String? actorId, String? postId, String? chatId) {
    if (type == 'follow' && actorId != null) {
      _navToProfile(actorId);
    } else if (postId != null && postId.isNotEmpty) {
      _navToPost(postId);
    } else if (chatId != null && chatId.isNotEmpty) {
      _navToChat(chatId, actorId, 'User');
    }
  }

  void _navToProfile(String? uid) {
    if (uid == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: uid)));
  }

  void _navToPost(String? pid) {
    if (pid == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => PostDetailScreen(postId: pid)));
  }

  void _navToChat(String? cid, String? uid, String name) {
    if (cid == null || uid == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(
      chatId: cid,
      otherUserId: uid,
      otherUserName: name,
    )));
  }

  Future<void> _followWork(String uid) async {
    // Reusing logic from UserProfile if possible, or simple firestore update
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid == uid) return;
    
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'followersList': FieldValue.arrayUnion([currentUid]),
      });
      await FirebaseFirestore.instance.collection('users').doc(currentUid).update({
        'followingList': FieldValue.arrayUnion([uid]),
      });
      // Optionally send a notification back
       NotificationService.sendNotification(
          targetUserId: uid,
          type: 'follow',
          message: 'followed you back',
        );
      setState(() {
        _followingList.add(uid);
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Followed back!')));
    } catch (e) {
      debugPrint('Follow back error: $e');
    }
  }

  Future<void> _markAllAsRead(String uid) async {
    final batch = FirebaseFirestore.instance.batch();
    final snapshots = await FirebaseFirestore.instance
        .collection('notifications')
        .where('targetUserId', isEqualTo: uid)
        .where('isRead', isEqualTo: false)
        .get();
    
    for (var doc in snapshots.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
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
