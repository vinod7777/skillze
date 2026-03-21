import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:share_plus/share_plus.dart';
import '../screens/main/user_profile_screen.dart';
import '../screens/main/main_navigation.dart';
import '../screens/main/create_post_screen.dart';
import '../screens/main/about_account_screen.dart';
import '../theme/app_theme.dart';
import '../services/localization_service.dart';
import 'user_avatar.dart';
import '../services/notification_service.dart';
import '../screens/main/comments_modal.dart';
import '../services/deep_link_service.dart';

class PostCard extends StatefulWidget {
  final DocumentSnapshot doc;
  const PostCard({super.key, required this.doc});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  bool _isLiked = false;
  bool _isSaved = false;
  int _likesCount = 0;
  int _commentsCount = 0;
  bool _isFollowing = false;
  bool _isHidden = false;

  late AnimationController _heartController;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
    @override
  void initState() {
    super.initState();
    final data = widget.doc.data() as Map<String, dynamic>;
    _likesCount = data['likesCount'] ?? 0;
    _commentsCount = data['commentsCount'] ?? 0;

    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _heartScale = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.2), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.2, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.linear));

    _heartOpacity = TweenSequence([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.linear));

    _checkStatus();
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.doc.id);
      final likeDoc = await postRef.collection('likes').doc(user.uid).get();

      final data = widget.doc.data() as Map<String, dynamic>?;
      final String authorId = data?['authorId'] ?? '';
      final List savedBy = data?['savedBy'] ?? [];

      // Fetch current user data for following and hidden lists
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      
      final List followingList = userData?['followingList'] ?? [];
      final List hiddenPosts = userData?['hiddenPosts'] ?? [];
      final List notInterestedPosts = userData?['notInterestedPosts'] ?? [];
      
      final bool following = followingList.contains(authorId);

      if (mounted) {
        setState(() {
          _isLiked = likeDoc.exists;
          _isSaved = savedBy.contains(user.uid);
          _isFollowing = following;
          _isHidden = hiddenPosts.contains(widget.doc.id) || 
                      notInterestedPosts.contains(widget.doc.id);
        });
      }
    }
  }

  Future<void> _toggleLike() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.doc.id);
    final likeRef = postRef.collection('likes').doc(user.uid);

    setState(() {
      if (_isLiked) {
        _isLiked = false;
        _likesCount--;
      } else {
        _isLiked = true;
        _likesCount++;
      }
    });

    if (_isLiked) {
      await likeRef.set({'timestamp': FieldValue.serverTimestamp()});
      await postRef.update({'likesCount': FieldValue.increment(1)});
    } else {
      await likeRef.delete();
      await postRef.update({'likesCount': FieldValue.increment(-1)});
    }
  }

  void _handleDoubleTap() {
    if (!_isLiked) {
      _toggleLike();
    }
    _heartController.forward(from: 0.0);
  }

  Future<void> _toggleSave() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final saveRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('savedPosts')
        .doc(widget.doc.id);

    final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.doc.id);

    setState(() {
      _isSaved = !_isSaved;
    });

    if (_isSaved) {
      // Update subcollection for user
      await saveRef.set({
        'postId': widget.doc.id,
        'savedAt': FieldValue.serverTimestamp(),
      });
      // Update post document array for efficient querying
      await postRef.update({
        'savedBy': FieldValue.arrayUnion([user.uid])
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post saved'), duration: Duration(seconds: 1)),
        );
      }
    } else {
      // Remove from subcollection
      await saveRef.delete();
      // Remove from post document array
      await postRef.update({
        'savedBy': FieldValue.arrayRemove([user.uid])
      });
    }
  }

  Future<void> _handleShare() async {
    final data = widget.doc.data() as Map<String, dynamic>;
    final content = data['content'] ?? '';
    final authorName = data['authorName'] ?? 'Someone';
    final postLink = DeepLinkService.generatePostLink(widget.doc.id);
    
    // ignore: deprecated_member_use
    await Share.share('Check out this post by $authorName on Skillze:\n\n$content\n\nLink: $postLink');
  }

  Future<void> _handleFollow() async {
    final user = FirebaseAuth.instance.currentUser;
    final data = widget.doc.data() as Map<String, dynamic>;
    final String authorId = data['authorId'] ?? '';

    if (user == null || authorId.isEmpty || authorId == user.uid) return;

    final targetUserRef = FirebaseFirestore.instance.collection('users').doc(authorId);
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    setState(() {
      _isFollowing = !_isFollowing;
    });

    try {
      if (_isFollowing) {
        await targetUserRef.update({
          'followersList': FieldValue.arrayUnion([user.uid]),
        });
        await currentUserRef.update({
          'followingList': FieldValue.arrayUnion([authorId]),
        });
        NotificationService.sendNotification(
          targetUserId: authorId,
          type: 'follow',
          message: 'started following you',
        );
      } else {
        await targetUserRef.update({
          'followersList': FieldValue.arrayRemove([user.uid]),
        });
        await currentUserRef.update({
          'followingList': FieldValue.arrayRemove([authorId]),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = !_isFollowing;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update follow status.')),
        );
      }
    }
  }

  Future<void> _repost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = widget.doc.data() as Map<String, dynamic>;
    
    try {
      await FirebaseFirestore.instance.collection('posts').add({
        'authorId': user.uid,
        'authorName': user.displayName ?? 'User',
        'authorAvatar': user.photoURL ?? '',
        'content': data['content'],
        'mediaUrls': data['mediaUrls'],
        'timestamp': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
        'isRepost': true,
        'originalPostId': widget.doc.id,
        'originalAuthorName': data['authorName'],
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

  Future<void> _hidePost(bool notInterested) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isHidden = true;
    });

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
    if (notInterested) {
      await userRef.update({
        'notInterestedPosts': FieldValue.arrayUnion([widget.doc.id])
      });
    } else {
      await userRef.update({
        'hiddenPosts': FieldValue.arrayUnion([widget.doc.id])
      });
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(notInterested ? 'Thanks. We\'ll show fewer posts like this.' : 'Post hidden.')),
      );
    }
  }

  void _showMoreOptions(bool isCurrentUser) {
    final data = widget.doc.data() as Map<String, dynamic>;
    final String authorId = data['authorId'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            if (!isCurrentUser) ...[
              ListTile(
                leading: Icon(Icons.repeat_rounded, color: context.textHigh),
                title: Text(context.t('repost'), style: TextStyle(color: context.textHigh)),
                onTap: () {
                  Navigator.pop(context);
                  _repost();
                },
              ),
              ListTile(
                leading: Icon(Icons.sentiment_dissatisfied_outlined, color: context.textHigh),
                title: Text(context.t('not_interested'), style: TextStyle(color: context.textHigh)),
                onTap: () {
                  Navigator.pop(context);
                  _hidePost(true);
                },
              ),
              ListTile(
                leading: Icon(
                  _isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
                  color: context.textHigh,
                ),
                title: Text(
                  _isFollowing ? context.t('unfollow') : context.t('follow'),
                  style: TextStyle(color: context.textHigh),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _handleFollow();
                },
              ),
              ListTile(
                leading: Icon(Icons.visibility_off_outlined, color: context.textHigh),
                title: Text(context.t('hide'), style: TextStyle(color: context.textHigh)),
                onTap: () {
                  Navigator.pop(context);
                  _hidePost(false);
                },
              ),
              ListTile(
                leading: Icon(Icons.info_outline_rounded, color: context.textHigh),
                title: Text(context.t('about_this_account'), style: TextStyle(color: context.textHigh)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => AboutAccountScreen(userId: authorId),
                    ),
                  );
                },
              ),
              const Divider(),
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
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF0F2F6A)),
                title: Text(context.t('edit_post'), style: const TextStyle(color: Color(0xFF0F2F6A))),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CreatePostScreen(postDoc: widget.doc),
                    ),
                  );
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
                    await FirebaseFirestore.instance.collection('posts').doc(widget.doc.id).delete();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(context.t('post_deleted_success'))),
                      );
                      // Pop back to root and then push main to effectively 'reload' to Home screen
                      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil('/main', (route) => false);
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (_isHidden) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: widget.doc.reference.snapshots(),
      builder: (context, snapshot) {
        final data = (snapshot.data?.data() as Map<String, dynamic>?) ?? 
                     (widget.doc.data() as Map<String, dynamic>);
        
        final String authorId = data['authorId'] ?? '';
        final String authorName = data['authorName'] ?? 'Unknown';
        final String authorAvatar = data['authorAvatar'] ?? 
                                    data['authorProfileImageUrl'] ?? 
                                    data['profileImageUrl'] ?? 
                                    data['photoUrl'] ?? '';
        final String content = data['content'] ?? '';
        final List<dynamic> mediaUrls = data['mediaUrls'] ?? [];
        final Timestamp? timestamp = data['timestamp'] as Timestamp?;
        final String timeAgo = timestamp != null ? timeago.format(timestamp.toDate()) : 'Recently';
        final bool isCurrentUser = authorId == currentUserId;

        // Update local counts from stream if possible
        _likesCount = data['likesCount'] ?? 0;
        _commentsCount = data['commentsCount'] ?? 0;

        return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(authorId)
                  .snapshots(),
              builder: (context, userSnap) {
                final userData = userSnap.data?.data() as Map<String, dynamic>?;
                final String displayAvatar = userData?['profileImageUrl'] ?? 
                                           userData?['authorProfileImageUrl'] ??
                                           userData?['photoUrl'] ??
                                           userData?['authorAvatar'] ??
                                           authorAvatar;
                final String displayName = userData?['name'] ?? authorName;

                return Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isCurrentUser) {
                          final navState = context
                              .findAncestorStateOfType<MainNavigationState>();
                          if (navState != null) navState.setIndex(3);
                        } else {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => 
                                  UserProfileScreen(userId: authorId),
                            ),
                          );
                        }
                      },
                      child: UserAvatar(
                        imageUrl: displayAvatar,
                        name: displayName,
                        radius: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (isCurrentUser) {
                                final navState = context
                                    .findAncestorStateOfType<MainNavigationState>();
                                if (navState != null) navState.setIndex(3);
                              } else {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => 
                                        UserProfileScreen(userId: authorId),
                                  ),
                                );
                              }
                            },
                            child: Text(
                              displayName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                color: context.textHigh,
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                timeAgo,
                                style: TextStyle(
                                  color: context.textMed,
                                  fontSize: 12,
                                ),
                              ),
                              if (data['location'] != null) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '•',
                                    style: TextStyle(
                                      color: context.textMed,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Text(
                                  data['location'],
                                  style: TextStyle(
                                    color: context.textMed,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _showMoreOptions(isCurrentUser),
                      icon: Icon(Icons.more_horiz, color: context.textHigh),
                    ),
                  ],
                );
              },
            ),
          ),
          // Media
          if (mediaUrls.isNotEmpty)
            GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CarouselSlider(
                    options: CarouselOptions(
                      height: 400,
                      viewportFraction: 1.0,
                      enableInfiniteScroll: false,
                    ),
                    items: mediaUrls.map((url) {
                      final bool isValidUrl = url is String && url.trim().isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'));
                      if (!isValidUrl) {
                        return Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Center(
                            child: Icon(Icons.image_not_supported_outlined, color: Color(0xFFA1A1AA), size: 40),
                          ),
                        );
                      }
                      return Image.network(
                        url, 
                        fit: BoxFit.cover, 
                        width: double.infinity,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: const Color(0xFFF1F5F9),
                          child: const Center(
                            child: Icon(Icons.broken_image_outlined, color: Color(0xFFA1A1AA), size: 40),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  AnimatedBuilder(
                    animation: _heartController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _heartOpacity.value,
                        child: Transform.scale(
                          scale: _heartScale.value,
                          child: const Icon(
                            Icons.favorite_rounded,
                            color: Colors.white,
                            size: 100,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

          // Actions Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _toggleLike,
                  child: Icon(
                    _isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isLiked ? Colors.red : context.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => CommentsModal(
                        postDoc: widget.doc,
                        onCommentPosted: () {
                          setState(() {
                            _commentsCount++;
                          });
                        },
                        onCommentDeleted: () {
                          setState(() {
                            _commentsCount--;
                          });
                        },
                      ),
                    );
                  },
                  child: Row(
                    children: [
                      Icon(Icons.chat_bubble_outline_rounded, size: 26, color: context.primary),
                      if (_commentsCount > 0) ...[
                        const SizedBox(width: 4),
                        Text('$_commentsCount', style: TextStyle(color: context.primary, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _handleShare,
                  child: Icon(Icons.share_outlined, size: 26, color: context.primary),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: _toggleSave,
                  child: Icon(
                    _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                    size: 28,
                    color: context.primary,
                  ),
                ),
              ],
            ),
          ),

          // Likes Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              '${_likesCount.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} likes',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: context.primary,
              ),
            ),
          ),

          // Content / Caption
          if (content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12.0, 8.0, 12.0, 16.0),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(color: context.textHigh, fontSize: 15, height: 1.3),
                  children: [
                    TextSpan(
                      text: '$authorName ',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: context.primary,
                      ),
                    ),
                    TextSpan(
                      text: content,
                      style: TextStyle(color: context.textMed),
                    ),
                  ],
                ),
              ),
            ),

          // Skills/Roles Tags
          if (data['skills'] != null || data['roles'] != null)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 16.0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                   ...((data['skills'] as List? ?? []).map((s) => _buildTag(s.toString()))),
                   ...((data['roles'] as List? ?? []).map((r) => _buildTag(r.toString()))),
                ],
              ),
            ),

          if (data['rules'] != null && (data['rules'] as String).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.primary.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.gavel_rounded, size: 14, color: context.primary),
                        const SizedBox(width: 8),
                        Text(
                          'RULES',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: context.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data['rules'],
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textMed,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Divider(height: 1, color: context.dividerColor),
        ],
      ),
    );
      },
    );
  }

  Widget _buildTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: context.isDark ? context.accent : context.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}


