import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_profile_screen.dart';
import '../../widgets/user_avatar.dart';
import '../../theme/app_theme.dart';

enum UserListType { followers, following }

class UserListScreen extends StatefulWidget {
  final String userId;
  final String title;
  final UserListType type;

  const UserListScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.type,
  });

  @override
  State<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() ?? {};
      List uids = [];

      if (widget.type == UserListType.followers) {
        uids = userData['followersList'] ?? [];
      } else {
        uids = userData['followingList'] ?? [];
      }

      List<Map<String, dynamic>> users = [];
      for (String uid in uids) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        if (doc.exists) {
          users.add({'uid': uid, ...doc.data()!});
        }
      }

      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching user list: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: context.primary),
            )
          : _users.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.type == UserListType.followers
                        ? Icons.people_outline_rounded
                        : Icons.person_add_outlined,
                    size: 64,
                    color: context.textLow,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No ${widget.type == UserListType.followers ? 'followers' : 'following'} yet',
                    style: TextStyle(
                      color: context.textMed,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (context, index) => SizedBox(height: 12),
              itemBuilder: (context, index) {
                final user = _users[index];
                final name = user['name'] ?? 'Unknown';
                final bio = user['bio'] ?? '';
                final uid = user['uid'] ?? '';
                final profileImageUrl = user['profileImageUrl'];

                return Container(
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.border, width: 1),
                  ),
                  child: ListTile(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(userId: uid),
                        ),
                      );
                    },
                    leading: UserAvatar(
                      imageUrl: profileImageUrl?.toString(),
                      name: name,
                      radius: 24,
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: context.textHigh,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      bio,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textMed,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: context.textLow,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

