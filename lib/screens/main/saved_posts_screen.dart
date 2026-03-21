import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: const Text(
          'Saved Posts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF18181B),
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        backgroundColor: const Color(0xFFF8F9FB),
      ),
      body: user == null
          ? Center(
              child: Text(
                'Please log in to see saved posts',
                style: TextStyle(color: const Color(0xFF71717A)),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .where('savedBy', arrayContains: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return SkeletonListView(itemCount: 5);
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: Colors.redAccent),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 20,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.bookmark_border_rounded,
                            size: 48,
                            color: const Color(0xFF0F2F6A).withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'No saved posts yet',
                          style: TextStyle(
                            color: Color(0xFF18181B),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Posts you save will appear here',
                          style: TextStyle(
                            color: const Color(0xFF71717A),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    return PostCard(doc: docs[index]);
                  },
                );
              },
            ),
    );
  }
}

