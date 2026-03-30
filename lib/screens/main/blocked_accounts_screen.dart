import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';

class BlockedAccountsScreen extends StatelessWidget {
  const BlockedAccountsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocked Accounts'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: currentUser == null
          ? const Center(child: Text('Not logged in'))
          : StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final blockedUsers = List<String>.from(
                  data?['blockedUsers'] ?? [],
                );

                if (blockedUsers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.block,
                          size: 64,
                          color: colorScheme.onSurface.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No blocked accounts',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Accounts you block will appear here',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.4),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: blockedUsers.length,
                  itemBuilder: (context, index) {
                    final blockedUid = blockedUsers[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(blockedUid)
                          .get(),
                      builder: (context, userSnap) {
                        if (userSnap.connectionState ==
                            ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 12.0,
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(radius: 24),
                                SizedBox(width: 12),
                                Expanded(child: LinearProgressIndicator()),
                              ],
                            ),
                          );
                        }

                        final userData =
                            userSnap.data?.data() as Map<String, dynamic>?;
                        final name = userData?['name'] ?? 'Unknown User';
                        final username = userData?['username'] ?? '';
                        final profileImageUrl =
                            userData?['profileImageUrl'] as String?;

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 4.0,
                          ),
                          leading: UserAvatar(
                            imageUrl: profileImageUrl,
                            name: name,
                            radius: 24,
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: username.isNotEmpty
                              ? Text(
                                  '@$username',
                                  style: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                )
                              : null,
                          trailing: OutlinedButton(
                            onPressed: () => _unblockUser(
                              context,
                              currentUser.uid,
                              blockedUid,
                              name,
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.redAccent),
                              foregroundColor: Colors.redAccent,
                            ),
                            child: const Text('Unblock'),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }

  void _unblockUser(
    BuildContext context,
    String currentUid,
    String blockedUid,
    String name,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .update({
            'blockedUsers': FieldValue.arrayRemove([blockedUid]),
          });
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$name has been unblocked')));
      }
    }
  }
}
