import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_theme.dart';
import '../../widgets/post_card.dart';

class ConnectionsFeedScreen extends StatefulWidget {
  const ConnectionsFeedScreen({super.key});

  @override
  State<ConnectionsFeedScreen> createState() => _ConnectionsFeedScreenState();
}

class _ConnectionsFeedScreenState extends State<ConnectionsFeedScreen> {
  List<String> _followingList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFollowing();
  }

  Future<void> _fetchFollowing() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data.containsKey('followingList')) {
          if (mounted) {
            setState(() {
              _followingList = List<String>.from(data['followingList']);
              _isLoading = false;
            });
          }
          return;
        }
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Network Feed',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: -0.5,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textHigh, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: context.textHigh.withOpacity(0.2)))
            : _followingList.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline_rounded, color: context.textMed.withOpacity(0.2), size: 80),
                      const SizedBox(height: 24),
                      Text(
                        'You are not following anyone yet.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textHigh,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Follow people to see their latest work in your network feed.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textMed,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .where(
                      'authorId',
                      whereIn: _followingList,
                    )
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: context.textHigh.withOpacity(0.2)));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No new posts from your network.',
                        style: TextStyle(color: context.textMed),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: docs.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      return PostCard(doc: docs[index]);
                    },
                  );
                },
              ),
      ),
    );
  }
}
