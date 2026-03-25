import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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
import '../screens/main/post_detail_screen.dart';

class PostCard extends StatefulWidget {
  final DocumentSnapshot doc;
  final bool isClickable;
  final VoidCallback? onDeleted;
  const PostCard({
    super.key, 
    required this.doc, 
    this.isClickable = true,
    this.onDeleted,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  bool _isLiked = false;
  int _likesCount = 0;
  int _commentsCount = 0;
  bool _isFollowing = false;
  bool _isHidden = false;
  String? _firstLikerName;
  String? _topLikerId;
  bool _isNavigating = false;
  int _currentMediaIndex = 0;
  bool _isExpanded = false;

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
          _isFollowing = following;
          _isHidden = hiddenPosts.contains(widget.doc.id) || 
                      notInterestedPosts.contains(widget.doc.id);
        });

        // Fetch liker with highest followers for summary
        if (_likesCount > 0) {
          final likesSnapshot = await postRef.collection('likes')
              .limit(5)
              .get();
          
          String? bestLikerName;
          String? bestLikerId;
          int maxFollowers = -1;

          for (var doc in likesSnapshot.docs) {
            final uDoc = await FirebaseFirestore.instance.collection('users').doc(doc.id).get();
            final uData = uDoc.data();
            if (uData != null) {
              final followers = (uData['followersList'] as List?)?.length ?? 0;
              if (followers > maxFollowers) {
                maxFollowers = followers;
                bestLikerName = uData['name'];
                bestLikerId = doc.id;
              }
            }
          }

          if (mounted) {
            setState(() {
              _firstLikerName = bestLikerName;
              _topLikerId = bestLikerId;
            });
          }
        }
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

  void _showHideOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
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
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.visibility_off_outlined, color: context.textHigh),
              title: Text('Hide', style: TextStyle(color: context.textHigh, fontWeight: FontWeight.w600)),
              subtitle: Text('See fewer posts like this', style: TextStyle(color: context.textMed, fontSize: 13)),
              onTap: () {
                Navigator.pop(context);
                _hidePost(false);
              },
            ),
            ListTile(
              leading: Icon(Icons.sentiment_dissatisfied_outlined, color: context.textHigh),
              title: Text('Not Interested', style: TextStyle(color: context.textHigh, fontWeight: FontWeight.w600)),
              subtitle: Text('Don\'t show me posts related to this', style: TextStyle(color: context.textMed, fontSize: 13)),
              onTap: () {
                Navigator.pop(context);
                _hidePost(true);
              },
            ),
          ],
        ),
      ),
    );
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
                      
                      widget.onDeleted?.call();
                      
                      if (!widget.isClickable) {
                        Navigator.pop(context, 'deleted');
                      }
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

  void _showCommentsModal() {
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
  }

  Widget _buildActionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w500)),
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
                                    data['photoUrl'] ?? '';
        final String content = data['content'] ?? '';
        final List<dynamic> mediaUrls = data['mediaUrls'] ?? [];
        final Timestamp? timestamp = data['timestamp'] as Timestamp?;
        final String timeAgo = timestamp != null ? timeago.format(timestamp.toDate()) : 'Recently';
        final bool isCurrentUser = authorId == currentUserId;
        final bool isRepost = data['isRepost'] ?? false;
        final String originalAuthorName = data['originalAuthorName'] ?? '';

        _likesCount = data['likesCount'] ?? 0;
        _commentsCount = data['commentsCount'] ?? 0;
        final bool isPrivate = data['isPrivate'] ?? false;

        return GestureDetector(
          onTap: () async {
            if (!widget.isClickable || _isNavigating) return;
            setState(() => _isNavigating = true);
            final result = await Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => PostDetailScreen(postId: widget.doc.id)),
            );
            
            if (result == 'deleted' && widget.onDeleted != null) {
              widget.onDeleted?.call();
            }

            if (mounted) {
              setState(() => _isNavigating = false);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: Border(bottom: BorderSide(color: context.dividerColor, width: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 4.0, 8.0),
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(authorId)
                      .snapshots(),
                  builder: (context, userSnap) {
                    final userData = userSnap.data?.data() as Map<String, dynamic>?;
                    final String displayAvatar = userData?['profileImageUrl'] ?? 
                                               userData?['photoUrl'] ??
                                               authorAvatar;
                    final String displayName = userData?['name'] ?? authorName;
                    final String? topSkills = userData?['skills'] != null 
                        ? (userData!['skills'] as List<dynamic>).take(3).join(' • ') 
                        : null;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (isCurrentUser) {
                              final navState = context.findAncestorStateOfType<MainNavigationState>();
                              if (navState != null) navState.setIndex(3);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                              );
                            }
                          },
                          child: UserAvatar(
                            imageUrl: displayAvatar,
                            name: displayName,
                            radius: 22,
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
                                    final navState = context.findAncestorStateOfType<MainNavigationState>();
                                    if (navState != null) navState.setIndex(3);
                                  } else {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                                    );
                                  }
                                },
                                child: Text(
                                  displayName,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14.5,
                                    color: context.textHigh,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (topSkills != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 1.0),
                                  child: Text(
                                    topSkills,
                                    style: TextStyle(color: context.primary, fontSize: 10, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    timeAgo,
                                    style: TextStyle(color: context.textMed, fontSize: 12),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(isPrivate ? Icons.people_alt_outlined : Icons.public, size: 14, color: context.textMed),
                                ],
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showMoreOptions(isCurrentUser),
                          icon: Icon(Icons.more_horiz, color: context.textMed),
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: _showHideOptions,
                          icon: Icon(Icons.close, color: context.textMed),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    );
                  },
                ),
              ),
              
              if (isRepost)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  child: Text(
                    'reposted $originalAuthorName\'s post',
                    style: TextStyle(color: context.textMed, fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ),

              if (content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final bool canExpand = content.length > 150;
                      final bool shouldTruncate = !widget.isClickable ? false : (canExpand && !_isExpanded);
                      
                      if (shouldTruncate) {
                        return RichText(
                          text: TextSpan(
                            style: TextStyle(color: context.textHigh, fontSize: 13.5, height: 1.4),
                            children: [
                              TextSpan(text: content.substring(0, 140)),
                              TextSpan(
                                text: '... See more',
                                style: TextStyle(color: context.textMed, fontWeight: FontWeight.bold),
                                recognizer: TapGestureRecognizer()..onTap = () {
                                  setState(() => _isExpanded = true);
                                },
                              ),
                            ],
                          ),
                        );
                      }
                      
                      return Text(
                        content,
                        style: TextStyle(color: context.textHigh, fontSize: 13.5, height: 1.4),
                      );
                    },
                  ),
                ),

              if (mediaUrls.isNotEmpty)
                GestureDetector(
                  onDoubleTap: _handleDoubleTap,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CarouselSlider(
                        options: CarouselOptions(
                          aspectRatio: 1.0,
                          viewportFraction: 1.0,
                          enableInfiniteScroll: false,
                          onPageChanged: (index, reason) {
                            setState(() {
                              _currentMediaIndex = index;
                            });
                          },
                        ),
                        items: mediaUrls.map((url) {
                          final bool isValidUrl = url is String && url.trim().isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'));
                          if (!isValidUrl) {
                            return Container(
                              color: context.surfaceLightColor,
                              child: Center(
                                child: Icon(Icons.image_not_supported_outlined, color: context.textLow, size: 40),
                              ),
                            );
                          }
                          return Image.network(
                            url, 
                            fit: BoxFit.cover, 
                            width: double.infinity,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: context.surfaceLightColor,
                              child: Center(
                                child: Icon(Icons.broken_image_outlined, color: context.textLow, size: 40),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      if (mediaUrls.length > 1)
                        Positioned(
                          bottom: 15,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: mediaUrls.asMap().entries.map((entry) {
                              return Container(
                                width: 6.0,
                                height: 6.0,
                                margin: const EdgeInsets.symmetric(horizontal: 3.0),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withOpacity(
                                    _currentMediaIndex == entry.key ? 0.9 : 0.4,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
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

              Padding(
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
                child: Row(
                  children: [
                    if (_likesCount > 0) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                            child: const Icon(Icons.thumb_up_alt, size: 10, color: Colors.white),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              if (_topLikerId != null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => UserProfileScreen(userId: _topLikerId!)),
                                );
                              }
                            },
                            child: Text(
                              _firstLikerName != null 
                                ? (_likesCount > 1 
                                    ? "$_firstLikerName and ${_likesCount - 1} others" 
                                    : "$_firstLikerName")
                                : '$_likesCount',
                              style: TextStyle(
                                color: context.textMed, 
                                fontSize: 13,
                                fontWeight: _firstLikerName != null ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    if (_commentsCount > 0)
                      Text(
                        '$_commentsCount ${_commentsCount == 1 ? 'comment' : 'comments'}',
                        style: TextStyle(color: context.textMed, fontSize: 13),
                      ),
                  ],
                ),
              ),

              Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: context.dividerColor, width: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      _isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                      "Like",
                      _isLiked ? Colors.blue : context.textMed,
                      _toggleLike,
                    ),
                    _buildActionButton(
                      Icons.comment_outlined,
                      "Comment",
                      context.textMed,
                      _showCommentsModal,
                    ),
                    _buildActionButton(
                      Icons.repeat_rounded,
                      "Repost",
                      context.textMed,
                      _repost,
                    ),
                    _buildActionButton(
                      Icons.send_outlined,
                      "Send",
                      context.textMed,
                      _handleShare,
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

}


