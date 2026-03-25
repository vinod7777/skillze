import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';

class HiddenContentScreen extends StatefulWidget {
  const HiddenContentScreen({super.key});

  @override
  State<HiddenContentScreen> createState() => _HiddenContentScreenState();
}

class _HiddenContentScreenState extends State<HiddenContentScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _undoAction(String postId, String field) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      field: FieldValue.arrayRemove([postId])
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Action undone. Post will now appear in your feed.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('Hidden Content'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: context.primary,
          unselectedLabelColor: context.textMed,
          indicatorColor: context.primary,
          tabs: const [
            Tab(text: 'Hidden Posts'),
            Tab(text: 'Not Interested'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPostsList('hiddenPosts'),
          _buildPostsList('notInterestedPosts'),
        ],
      ),
    );
  }

  Widget _buildPostsList(String field) {
    final user = _auth.currentUser;
    if (user == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(user.uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
        
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final List<String> postIds = List<String>.from(userData?[field] ?? []);
        
        if (postIds.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.visibility_off_outlined, size: 64, color: context.textLow),
                const SizedBox(height: 16),
                Text(
                  'No posts here',
                  style: TextStyle(color: context.textMed, fontSize: 16),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: postIds.length,
          itemBuilder: (context, index) {
            final postId = postIds[index];
            return FutureBuilder<DocumentSnapshot>(
              future: _firestore.collection('posts').doc(postId).get(),
              builder: (context, postSnap) {
                if (!postSnap.hasData) return const SizedBox.shrink();
                if (!postSnap.data!.exists) {
                  // Clean up deleted posts from user's list
                  _undoAction(postId, field);
                  return const SizedBox.shrink();
                }

                final data = postSnap.data!.data() as Map<String, dynamic>;
                final authorName = data['authorName'] ?? 'Unknown';

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: context.surfaceLightColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    title: Text(
                      'Post by $authorName',
                      style: TextStyle(fontWeight: FontWeight.bold, color: context.textHigh),
                    ),
                    subtitle: Text(
                      data['content'] ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: context.textMed),
                    ),
                    trailing: TextButton(
                      onPressed: () => _undoAction(postId, field),
                      child: const Text('Undo'),
                    ),
                    onTap: () {
                       // Optional: navigate to the post?
                       // Since it's hidden, maybe just showing it here is enough or use a preview.
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
