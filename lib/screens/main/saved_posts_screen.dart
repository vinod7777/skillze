import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/post_card.dart';
import '../../widgets/skeleton_replacement.dart';
import '../../theme/app_theme.dart';

class SavedPostsScreen extends StatelessWidget {
  const SavedPostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title:  Text(
          'Saved Posts',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: context.textHigh,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon:  Icon(Icons.arrow_back_ios_new_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        elevation: 0,
        backgroundColor: context.bg,
      ),
      body: user == null
          ? Center(
              child: Text(
                'Please log in to see saved posts',
                style: TextStyle(color: context.textMed),
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
                      style: const TextStyle(color: Colors.redAccent),
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
                            color: context.surfaceColor,
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
                            color: context.primary.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 24),
                         Text(
                          'No saved posts yet',
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Posts you save will appear here',
                          style: TextStyle(
                            color: context.textMed,
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
