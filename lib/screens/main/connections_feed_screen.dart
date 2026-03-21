import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppBar(
        title: Text('Network Feed'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: const Color(0xFF18181B)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _followingList.isEmpty
            ? Center(
                child: Text(
                  'You are not following anyone yet.\nFollow people to see their posts here!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFF71717A),
                    fontSize: 16,
                  ),
                ),
              )
            : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('posts')
                    .where(
                      'authorId',
                      whereIn: _followingList.take(10).toList(),
                    )
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Text(
                        'No posts from your network yet.',
                        style: TextStyle(color: const Color(0xFF71717A)),
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;
                  return ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 120,
                      top: 16,
                      left: 24,
                      right: 24,
                    ),
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
