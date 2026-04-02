import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../utils/avatar_helper.dart';
import '../screens/main/comments_modal.dart';
import '../screens/main/user_profile_screen.dart';
import '../screens/main/about_account_screen.dart';
import '../services/localization_service.dart';

class FullScreenPostViewer extends StatefulWidget {
  final String postId;
  final String? initialImageUrl;

  const FullScreenPostViewer({
    super.key,
    required this.postId,
    this.initialImageUrl,
  });

  static void show(BuildContext context, String postId, {String? imageUrl}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenPostViewer(postId: postId, initialImageUrl: imageUrl),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  State<FullScreenPostViewer> createState() => _FullScreenPostViewerState();
}

class _FullScreenPostViewerState extends State<FullScreenPostViewer> {
  Map<String, dynamic>? _data;
  bool _isLiked = false;
  bool _isExpanded = false;
  bool _isFollowing = false;
  Stream<DocumentSnapshot>? _postStream;
  Stream<DocumentSnapshot>? _userStream;
  int _currentMediaIndex = 0;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _postStream = FirebaseFirestore.instance.collection('posts').doc(widget.postId).snapshots();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('posts').doc(widget.postId).get();
      if (!doc.exists) return;
      _data = doc.data() as Map<String, dynamic>;
      
      final likeDoc = await doc.reference.collection('likes').doc(user.uid).get();
      
      final authorId = _data?['authorId'];
      if (authorId != null) {
        _userStream = FirebaseFirestore.instance.collection('users').doc(authorId).snapshots();
        
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        final userData = userDoc.data();
        final List followingList = userData?['followingList'] ?? [];
        
        if (mounted) {
          final savedDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('saved_posts')
              .doc(widget.postId)
              .get();

          setState(() {
            _isLiked = likeDoc.exists;
            _isFollowing = followingList.contains(authorId);
            _isSaved = savedDoc.exists;
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking status: $e");
    }
  }

  void _showComments(DocumentSnapshot postSnap) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: CommentsModal(
                  postDoc: postSnap,
                  onCommentPosted: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
    });
    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
    postRef.update({
      'likesCount': FieldValue.increment(_isLiked ? 1 : -1),
    });
  }

  Future<void> _repost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _data == null) return;

    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'authorName': user.displayName ?? 'User',
        'authorAvatar': user.photoURL ?? '',
        'content': _data!['content'],
        'mediaUrls': _data!['mediaUrls'],
        'timestamp': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
        'isRepost': true,
        'originalPostId': widget.postId,
        'originalAuthorName': _data!['authorName'],
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post reposted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to repost.')),
        );
      }
    }
  }

  Future<void> _handleShare() async {
    if (_data == null) return;
    final content = _data!['content'] ?? '';
    final authorName = _data!['authorName'] ?? 'Someone';
    await Share.share('Check out this post by $authorName on Skillze:\n\n$content');
  }

  Future<void> _savePost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    try {
      final savedRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_posts')
          .doc(widget.postId);
      
      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

      if (!_isSaved) {
        // Prepare batch for atomicity
        final batch = FirebaseFirestore.instance.batch();
        batch.delete(savedRef);
        batch.update(postRef, {
          'savedBy': FieldValue.arrayRemove([user.uid])
        });
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post removed from saved.')),
          );
        }
      } else {
        // Prepare batch for atomicity
        final batch = FirebaseFirestore.instance.batch();
        batch.set(savedRef, {
          'postId': widget.postId,
          'savedAt': FieldValue.serverTimestamp(),
        });
        batch.update(postRef, {
          'savedBy': FieldValue.arrayUnion([user.uid])
        });
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Post saved successfully!')),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isSaved = !_isSaved;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save post.')),
        );
      }
    }
  }

  Future<void> _hidePost(bool notInterested) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    if (notInterested) {
      await userRef.update({
        'notInterestedPosts': FieldValue.arrayUnion([widget.postId])
      });
    } else {
      await userRef.update({
        'hiddenPosts': FieldValue.arrayUnion([widget.postId])
      });
    }
    if (mounted) {
      Navigator.pop(context); 
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notInterested ? 'Fewer posts like this will be shown.' : 'Post hidden.')),
      );
    }
  }

  void _showMoreOptions() {
    if (_data == null) return;
    final user = FirebaseAuth.instance.currentUser;
    final bool isCurrentUser = user?.uid == _data!['authorId'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCurrentUser) ...[
              ListTile(
                leading: Icon(
                  _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                  color: _isSaved ? Colors.blue : Colors.white,
                ),
                title: Text(
                  _isSaved ? context.t('saved') : context.t('save'),
                  style: TextStyle(color: _isSaved ? Colors.blue : Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _savePost();
                },
              ),
              ListTile(
                leading: const Icon(Icons.repeat_rounded, color: Colors.white),
                title: Text(context.t('repost'), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _repost();
                },
              ),
              ListTile(
                leading: const Icon(Icons.sentiment_dissatisfied_outlined, color: Colors.white),
                title: Text(context.t('not_interested'), style: const TextStyle(color: Colors.white)),
                onTap: () => _hidePost(true),
              ),
              ListTile(
                leading: Icon(
                  _isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
                  color: Colors.white,
                ),
                title: Text(
                  _isFollowing ? context.t('unfollow') : context.t('follow'),
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _toggleFollow();
                },
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined, color: Colors.white),
                title: Text(context.t('hide'), style: const TextStyle(color: Colors.white)),
                onTap: () => _hidePost(false),
              ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: Colors.white),
                title: Text(context.t('about_this_account'), style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AboutAccountScreen(userId: _data!['authorId']),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
                title: Text(context.t('report_post'), style: const TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Post reported.')),
                  );
                },
              ),
            ],
            if (isCurrentUser) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.blue),
                title: Text(context.t('edit_post'), style: const TextStyle(color: Colors.blue)),
                onTap: () {
                  Navigator.pop(context);
                  // Since widget.postDoc is no longer used, we need to fetch it or pass DocumentSnapshot 
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(context.t('delete_post'), style: const TextStyle(color: Colors.red)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(context.t('delete_post')),
                      content: Text(context.t('delete_post_confirm')),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.t('cancel'))),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(context.t('delete'), style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await FirebaseFirestore.instance.collection('posts').doc(widget.postId).delete();
                    if (!mounted) return;
                    Navigator.pop(context); // Close viewer
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.t('post_deleted_success'))),
                    );
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleFollow() async {
    if (_data == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final authorId = _data!['authorId'];
    if (authorId == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final authorRef = FirebaseFirestore.instance.collection('users').doc(authorId);

    try {
      if (_isFollowing) {
        await userRef.update({'followingList': FieldValue.arrayRemove([authorId])});
        await authorRef.update({'followersList': FieldValue.arrayRemove([user.uid])});
      } else {
        await userRef.update({'followingList': FieldValue.arrayUnion([authorId])});
        await authorRef.update({'followersList': FieldValue.arrayUnion([user.uid])});
      }
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isFollowing ? 'Following' : 'Unfollowed')),
        );
      }
    } catch (e) {
      debugPrint("Error toggling follow: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<DocumentSnapshot>(
        stream: _postStream,
        builder: (context, postSnap) {
          final livePostData = postSnap.data?.data() as Map<String, dynamic>? ?? _data;
          if (livePostData == null) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          final int liveLikesCount = livePostData['likesCount'] ?? 0;
          final int liveCommentsCount = livePostData['commentsCount'] ?? 0;
          final String liveContent = livePostData['content'] ?? '';
          final List<dynamic> mediaUrls = livePostData['mediaUrls'] ?? (widget.initialImageUrl != null ? [widget.initialImageUrl] : []);

          return Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: mediaUrls.isEmpty
                    ? const Icon(Icons.image_not_supported_outlined, color: Colors.white54, size: 64)
                    : (mediaUrls.length > 1)
                        ? CarouselSlider(
                            options: CarouselOptions(
                              height: MediaQuery.of(context).size.height,
                              viewportFraction: 1.0,
                              enableInfiniteScroll: false,
                              onPageChanged: (index, reason) {
                                setState(() {
                                  _currentMediaIndex = index;
                                });
                              },
                            ),
                            items: mediaUrls.map((url) {
                              return InteractiveViewer(
                                minScale: 1.0,
                                maxScale: 4.0,
                                child: Image.network(
                                  url,
                                  fit: BoxFit.contain,
                                  width: MediaQuery.of(context).size.width,
                                ),
                              );
                            }).toList(),
                          )
                        : InteractiveViewer(
                            minScale: 1.0,
                            maxScale: 4.0,
                            child: Image.network(
                              mediaUrls.first,
                              fit: BoxFit.contain,
                              width: MediaQuery.of(context).size.width,
                            ),
                          ),
              ),
              if (mediaUrls.length > 1)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 60,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: mediaUrls.asMap().entries.map((entry) {
                      return Container(
                        width: 8.0,
                        height: 8.0,
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(_currentMediaIndex == entry.key ? 0.9 : 0.4),
                          boxShadow: [
                            BoxShadow(color: Colors.black26, blurRadius: 4, spreadRadius: 1),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                left: 10,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Positioned(
                right: 15,
                bottom: 120,
                child: Column(
                  children: [
                    _buildVerticalAction(
                      icon: _isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                      label: '$liveLikesCount',
                      color: _isLiked ? Colors.blue : Colors.white,
                      onTap: _toggleLike,
                    ),
                    const SizedBox(height: 20),
                    _buildVerticalAction(
                      icon: Icons.comment_outlined,
                      label: '$liveCommentsCount',
                      color: Colors.white,
                      onTap: () {
                        if (postSnap.hasData) {
                          _showComments(postSnap.data!);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildVerticalAction(
                      icon: Icons.repeat_rounded,
                      label: '',
                      color: Colors.white,
                      onTap: _repost,
                    ),
                    const SizedBox(height: 20),
                    _buildVerticalAction(
                      icon: Icons.share_outlined,
                      label: '',
                      color: Colors.white,
                      onTap: _handleShare,
                    ),
                    const SizedBox(height: 20),
                    _buildVerticalAction(
                      icon: _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                      label: '',
                      color: _isSaved ? Colors.blue : Colors.white,
                      onTap: _savePost,
                    ),
                    const SizedBox(height: 20),
                    _buildVerticalAction(
                      icon: Icons.more_horiz_rounded,
                      label: '',
                      color: Colors.white,
                      onTap: _showMoreOptions,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 15,
                bottom: 30,
                right: 80, 
                child: StreamBuilder<DocumentSnapshot>(
                  stream: _userStream,
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() as Map<String, dynamic>?;
                    final liveAuthorName = userData?['name'] ?? livePostData['authorName'] ?? 'User';
                    final liveAuthorHeadline = userData?['headline'] ?? livePostData['authorHeadline'];
                    final liveAuthorProfileUrl = userData?['profileImageUrl'] ?? livePostData['authorAvatar'] ?? livePostData['authorProfileImageUrl'];

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                               onTap: () {
                                final authorId = livePostData['authorId'];
                                if (authorId != null) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                                  );
                                }
                              },
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: Colors.white24,
                                backgroundImage: AvatarHelper.getAvatarProvider(liveAuthorProfileUrl, liveAuthorName),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  final authorId = livePostData['authorId'];
                                  if (authorId != null) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                                    );
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      liveAuthorName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (liveAuthorHeadline != null)
                                      Text(
                                        liveAuthorHeadline,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 15),
                        GestureDetector(
                          onTap: () => setState(() => _isExpanded = !_isExpanded),
                          child: RichText(
                            maxLines: _isExpanded ? null : 2,
                            overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: liveContent,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                                if (!_isExpanded && liveContent.length > 60)
                                  const TextSpan(
                                    text: ' ...more',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildVerticalAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
