import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/skeleton_replacement.dart';
import 'user_profile_screen.dart';
import '../../theme/app_theme.dart';

class ChatInfoScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String chatId;

  const ChatInfoScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.chatId,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  bool _isBlocked = false;
  bool _isRestricted = false;
  bool _isMuted = false;
  bool _isLoadingStatus = true;

  @override
  void initState() {
    super.initState();
    _checkUserStatus();
  }

  Future<void> _checkUserStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (doc.exists) {
      final data = doc.data();
      final blockedUsers = List<String>.from(data?['blockedUsers'] ?? []);
      final restrictedUsers = List<String>.from(data?['restrictedUsers'] ?? []);
      final mutedUsers = List<String>.from(data?['mutedUsers'] ?? []);
      if (mounted) {
        setState(() {
          _isBlocked = blockedUsers.contains(widget.userId);
          _isRestricted = restrictedUsers.contains(widget.userId);
          _isMuted = mutedUsers.contains(widget.userId);
          _isLoadingStatus = false;
        });
      }
    }
  }

  Future<void> _toggleStatus(String field, bool currentValue, String actionName) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid);

    setState(() {
      _isLoadingStatus = true;
    });

    try {
      if (currentValue) {
        await userRef.update({
          field: FieldValue.arrayRemove([widget.userId]),
        });
      } else {
        await userRef.update({
          field: FieldValue.arrayUnion([widget.userId]),
        });
      }

      await _checkUserStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${currentValue ? 'un' : ''}$actionName.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update $actionName status.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
        });
      }
    }
  }

  void _showOptionsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              _isMuted ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
              color: context.textHigh,
            ),
            title: Text(
              _isMuted ? 'Unmute' : 'Mute',
              style: TextStyle(color: context.textHigh),
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleStatus('mutedUsers', _isMuted, 'muted');
            },
          ),
          ListTile(
            leading: Icon(
              _isRestricted ? Icons.accessibility_new_rounded : Icons.do_not_disturb_on_rounded,
              color: context.textHigh,
            ),
            title: Text(
              _isRestricted ? 'Unrestrict' : 'Restrict',
              style: TextStyle(color: context.textHigh),
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleStatus('restrictedUsers', _isRestricted, 'restricted');
            },
          ),
          ListTile(
            leading: Icon(
              _isBlocked ? Icons.security_rounded : Icons.block_rounded,
              color: Colors.redAccent,
            ),
            title: Text(
              _isBlocked ? 'Unblock' : 'Block',
              style: TextStyle(color: Colors.redAccent),
            ),
            onTap: () {
              Navigator.pop(context);
              _toggleStatus('blockedUsers', _isBlocked, 'blocked');
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Future<String?> _getProfileImageUrl() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    return doc.data()?['profileImageUrl'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert_rounded, color: context.textHigh),
            onPressed: () {
              if (!_isLoadingStatus) {
                _showOptionsSheet();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          Center(
            child: FutureBuilder<String?>(
              future: _getProfileImageUrl(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SkeletonAvatar(
                    style: SkeletonAvatarStyle(
                      shape: BoxShape.circle,
                      width: 100,
                      height: 100,
                    ),
                  );
                }
                return UserAvatar(
                  imageUrl: snapshot.data,
                  name: widget.userName,
                  radius: 50,
                  gradient: LinearGradient(colors: [context.primary, context.primary.withValues(alpha: 0.8)]),
                  fontSize: 40,
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.userName,
            style: TextStyle(
              color: context.textHigh,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    SizedBox(
                      width: 200,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.person_outline),
                        label: const Text('View Profile'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.primary,
                          foregroundColor: context.onPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  UserProfileScreen(userId: widget.userId),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          Divider(color: context.border, thickness: 1),
          SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shared Media',
                style: TextStyle(
                  color: context.textHigh,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _SharedMediaGrid(chatId: widget.chatId),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedMediaGrid extends StatelessWidget {
  final String chatId;
  const _SharedMediaGrid({required this.chatId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('imageUrl', isGreaterThan: '')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No media shared yet.',
              style: TextStyle(color: context.textMed),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final imageUrl = data['imageUrl'] as String?;
            if (imageUrl == null || imageUrl.isEmpty) {
              return SizedBox.shrink();
            }
            return GestureDetector(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => Dialog(
                    backgroundColor: Colors.transparent,
                    child: InteractiveViewer(child: Image.network(imageUrl)),
                  ),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  color: context.border,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: context.surfaceLightColor,
                      child: Icon(Icons.broken_image, color: context.textLow),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

