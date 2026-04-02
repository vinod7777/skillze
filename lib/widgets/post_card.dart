import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:carousel_slider/carousel_slider.dart';
import 'package:share_plus/share_plus.dart';
import '../screens/main/user_profile_screen.dart';
import '../screens/main/create_post_screen.dart';
import '../screens/main/about_account_screen.dart';
import '../theme/app_theme.dart';
import '../services/localization_service.dart';
import 'user_avatar.dart';
import '../services/notification_service.dart';
import '../screens/main/comments_modal.dart';
import '../services/deep_link_service.dart';
import '../screens/main/post_detail_screen.dart';
import 'linkified_text.dart';
import 'quick_zoom_image.dart';
import 'fullscreen_post_viewer.dart';
import '../utils/avatar_helper.dart';

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
  
  // Track recognizers for proper disposal
  final List<TapGestureRecognizer> _recognizers = [];

  bool _isSaved = false;
  
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
    for (final r in _recognizers) {
      r.dispose();
    }
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
      final savedDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('saved_posts')
          .doc(widget.doc.id)
          .get();

      if (mounted) {
        setState(() {
          _isLiked = likeDoc.exists;
          _isFollowing = following;
          _isSaved = savedDoc.exists;
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
      
      // Send notification to post author
      final postData = widget.doc.data() as Map<String, dynamic>;
      final authorId = postData['authorId'] ?? '';
      if (authorId.isNotEmpty && authorId != user.uid) {
        NotificationService.sendNotification(
          targetUserId: authorId,
          type: 'like',
          message: 'liked your post',
          postId: widget.doc.id,
        );
      }
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

  Future<void> _navigateToPostDetail() async {
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
          SnackBar(
            content: const Text('Failed to update follow status.', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
        );
      }
    }
  }

  void _showRepostOptions() {
    final user = FirebaseAuth.instance.currentUser;
    final data = widget.doc.data() as Map<String, dynamic>;
    final String authorId = data['authorId'] ?? '';
    
    if (user != null && authorId == user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("You can't repost your own post.", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16),
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
            const SizedBox(height: 24),
            ListTile(
              leading: Icon(Icons.repeat_rounded, color: context.textHigh, size: 28),
              title: Text('Repost', style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text('Instantly share this post with others', style: TextStyle(color: context.textMed, fontSize: 13)),
              onTap: () {
                Navigator.pop(context);
                _performRepost(null);
              },
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.edit_note_rounded, color: context.textHigh, size: 28),
              title: Text('Repost with your thoughts', style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 16)),
              subtitle: Text('Create a new post quoting this one', style: TextStyle(color: context.textMed, fontSize: 13)),
              onTap: () {
                Navigator.pop(context);
                _showQuoteDialog();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showQuoteDialog() {
    final TextEditingController quoteController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        title: Text('Add your thoughts', style: TextStyle(color: context.textHigh, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: quoteController,
          autofocus: true,
          maxLines: 4,
          style: TextStyle(color: context.textHigh, fontSize: 15),
          decoration: InputDecoration(
            hintText: 'What do you want to talk about?',
            hintStyle: TextStyle(color: context.textMed),
            border: InputBorder.none,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textMed, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            onPressed: () {
              Navigator.pop(context);
              if (quoteController.text.trim().isNotEmpty) {
                _performRepost(quoteController.text.trim());
              } else {
                _performRepost(null);
              }
            },
            child: const Text('Post', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performRepost(String? thought) async {
    final user = FirebaseAuth.instance.currentUser;
    final data = widget.doc.data() as Map<String, dynamic>;
    final String authorId = data['authorId'] ?? '';

    if (user == null) return;
    if (authorId == user.uid) return; // Double check

    final bool isQuote = thought != null && thought.isNotEmpty;
    
    try {
      final payload = {
        'authorId': user.uid,
        'authorName': user.displayName ?? 'User',
        'authorAvatar': user.photoURL ?? '',
        'timestamp': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
        'isRepost': true,
        'originalPostId': widget.doc.id,
        'originalAuthorName': data['authorName'] ?? 'Unknown',
        'originalAuthorId': data['authorId'] ?? '',
      };

      if (isQuote) {
        payload['isQuote'] = true;
        payload['content'] = thought;
        payload['originalContent'] = data['content'] ?? '';
        payload['originalMediaUrls'] = data['mediaUrls'] ?? [];
        payload['originalAuthorAvatar'] = data['authorAvatar'] ?? data['authorProfileImageUrl'] ?? data['photoUrl'] ?? '';
        payload['mediaUrls'] = []; 
      } else {
        payload['content'] = data['content'];
        payload['mediaUrls'] = data['mediaUrls'];
      }

      await FirebaseFirestore.instance.collection('posts').add(payload);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isQuote ? 'Quote posted successfully!' : 'Post reposted successfully!',
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to repost.', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
        );
      }
    }
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
          .doc(widget.doc.id);
      
      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.doc.id);

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
            SnackBar(
              content: const Text('Post removed from saved.', style: TextStyle(color: Colors.black)),
              backgroundColor: Colors.white,
              action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
            ),
          );
        }
      } else {
        // Prepare batch for atomicity
        final batch = FirebaseFirestore.instance.batch();
        batch.set(savedRef, {
          'postId': widget.doc.id,
          'savedAt': FieldValue.serverTimestamp(),
        });
        batch.update(postRef, {
          'savedBy': FieldValue.arrayUnion([user.uid])
        });
        await batch.commit();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Post saved successfully!', style: TextStyle(color: Colors.black)),
              backgroundColor: Colors.white,
              action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
            ),
          );
        }
      }
    } catch (e) {
      setState(() {
        _isSaved = !_isSaved;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to save post.', style: TextStyle(color: Colors.black)),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
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
        SnackBar(
          content: Text(
            notInterested ? 'Thanks. We\'ll show fewer posts like this.' : 'Post hidden.',
            style: const TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ),
      );
    }
  }



  Future<void> _navigateToUserByUsername(String username) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => UserProfileScreen(userId: query.docs.first.id)),
        );
      }
    } catch (e) {
      debugPrint('Err lookup username: $e');
    }
  }

  void _showHideOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceLightColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
                  _showRepostOptions();
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
              ListTile(
                leading: Icon(
                  _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, 
                  color: context.textHigh
                ),
                title: Text(
                  _isSaved ? context.t('saved') : context.t('save'),
                  style: TextStyle(color: context.textHigh)
                ),
                onTap: () {
                  Navigator.pop(context);
                  _savePost();
                },
              ),
              const Divider(),
              ListTile(
                leading: Icon(Icons.report_problem_outlined, color: context.textHigh),
                title: Text(context.t('report_post'), style: TextStyle(color: context.textHigh)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Post reported.', style: TextStyle(color: Colors.black)),
                      backgroundColor: Colors.white,
                      action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
                    ),
                  );
                },
              ),
            ],
            if (isCurrentUser) ...[
              ListTile(
                leading: Icon(Icons.edit_outlined, color: context.primary),
                title: Text(context.t('edit_post'), style: TextStyle(color: context.primary)),
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
                leading: Icon(Icons.delete_outline, color: context.textHigh),
                title: Text(context.t('delete_post'), style: TextStyle(color: context.textHigh)),
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
                          child: Text(context.t('delete'), style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await FirebaseFirestore.instance.collection('posts').doc(widget.doc.id).delete();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(context.t('post_deleted_success'), style: const TextStyle(color: Colors.black)),
                          backgroundColor: Colors.white,
                          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
                        ),
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
            Text(
              label, 
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
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
        final List<dynamic> skills = data['skills'] ?? [];
        final List<dynamic> roles = data['roles'] ?? [];
        final Timestamp? timestamp = data['timestamp'] as Timestamp?;
        final String timeAgo = timestamp != null ? timeago.format(timestamp.toDate()) : 'Recently';
        final bool isCurrentUser = authorId == currentUserId;
         final bool isRepost = data['isRepost'] ?? false;
         final String originalAuthorName = data['originalAuthorName'] ?? '';
         final bool isEdited = data['isEdited'] == true;

        _likesCount = data['likesCount'] ?? 0;
        _commentsCount = data['commentsCount'] ?? 0;
        
        final bool isQuote = data['isQuote'] == true;
        final String originalContent = data['originalContent'] ?? '';
        final List<dynamic> originalMediaUrls = data['originalMediaUrls'] ?? [];
        final String originalAuthorAvatar = data['originalAuthorAvatar'] ?? '';
        final String originalAuthorId = data['originalAuthorId'] ?? '';

        final bool isPrivate = data['isPrivate'] ?? false;
        final String? location = data['location'];

        return GestureDetector(
          onTap: _navigateToPostDetail,
          child: Container(
            margin: EdgeInsets.only(bottom: widget.isClickable ? 8 : 0),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            border: widget.isClickable ? Border(bottom: BorderSide(color: context.dividerColor, width: 0.5)) : null,
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
                    final String displayAvatar = AvatarHelper.getAvatarUrl(userData) ?? authorAvatar;
                    final String displayName = userData?['name'] ?? authorName;
                    final String? topSkills = userData?['skills'] != null 
                        ? (userData!['skills'] as List<dynamic>).take(3).join(' • ') 
                        : null;

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                            );
                          },
                          child: UserAvatar(
                            imageUrl: displayAvatar,
                            name: displayName,
                            radius: 24,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => UserProfileScreen(userId: authorId)),
                                    );
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
                                Text(
                                  topSkills,
                                  style: TextStyle(
                                    color: context.primary.withOpacity(0.9), 
                                    fontSize: 10, 
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              Row(
                                 children: [
                                  Text(
                                    timeAgo,
                                    style: TextStyle(
                                      color: context.textMed.withOpacity(0.7), 
                                      fontSize: 11,
                                      height: 1.1,
                                    ),
                                  ),
                                  if (isEdited) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '• (edited)',
                                      style: TextStyle(
                                        color: context.textMed.withOpacity(0.8), 
                                        fontSize: 10,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 4),
                                  Icon(
                                    isPrivate ? Icons.people_alt_outlined : Icons.public, 
                                    size: 11, 
                                    color: context.textMed.withOpacity(0.7),
                                  ),
                                  if (location != null && location.isNotEmpty) ...[
                                    const SizedBox(width: 4),
                                    Text('•', style: TextStyle(color: context.textMed.withOpacity(0.7), fontSize: 11)),
                                    const SizedBox(width: 4),
                                    Icon(Icons.location_on_outlined, size: 10, color: context.primary),
                                    const SizedBox(width: 2),
                                    Flexible(
                                      child: Text(
                                        location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: context.primary.withOpacity(0.8),
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
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
              
              if (isRepost && !isQuote)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                  child: GestureDetector(
                    onTap: () {
                      final originalId = data['originalAuthorId'];
                      if (originalId != null && originalId is String && originalId.isNotEmpty) {
                         Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => UserProfileScreen(userId: originalId)),
                        );
                      }
                    },
                    child: Text(
                      'reposted $originalAuthorName\'s post',
                      style: TextStyle(
                        color: context.primary, 
                        fontSize: 12, 
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              // Description
              if (content.isNotEmpty || skills.isNotEmpty || roles.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12.0, 4.0, 12.0, 12.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      String displayContent = content;
                      if (skills.isNotEmpty || roles.isNotEmpty) {
                        final tagParts = [
                          ...roles.map((r) => '#${r.toString().replaceAll(' ', '_')}'),
                          ...skills.map((s) => '#${s.toString().replaceAll(' ', '_')}'),
                        ];
                        if (displayContent.isNotEmpty) displayContent += '\n\n';
                        displayContent += tagParts.join(' ');
                      }
                      
                      final bool canExpand = displayContent.length > 200;
                      final bool shouldTruncate = !widget.isClickable ? false : (canExpand && !_isExpanded);
                      
                      final String textToShow = shouldTruncate 
                          ? displayContent.substring(0, 180) 
                          : displayContent;


                      final recognizer = TapGestureRecognizer()..onTap = () {
                        setState(() => _isExpanded = true);
                      };
                      _recognizers.add(recognizer);

                      return RichText(
                        text: TextSpan(
                          style: TextStyle(color: context.textHigh, fontSize: 13.5, height: 1.4, fontFamily: 'Outfit'),
                          children: [
                            ...LinkifiedText.parse(textToShow, context, 
                              onMentionTap: _navigateToUserByUsername,
                            ),
                            if (shouldTruncate)
                              TextSpan(
                                text: '... See more',
                                style: TextStyle(color: context.textMed, fontWeight: FontWeight.bold),
                                recognizer: recognizer,
                              ),
                          ],
                        ),
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
                          aspectRatio: widget.isClickable ? 1.5 : 1.1, // Taller image in detail view (isClickable=false)
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
                          return QuickZoomImage(
                            imageUrl: url,
                            heroTag: 'post_image_${url}_${widget.doc.id}',
                            fit: BoxFit.cover,
                            onTap: () {
                              if (widget.isClickable) {
                                _navigateToPostDetail();
                              } else {
                                FullScreenPostViewer.show(
                                  context, 
                                  widget.doc.id, 
                                  imageUrl: url
                                );
                              }
                            },
                            onDoubleTap: _handleDoubleTap,
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

              if (isQuote)
                GestureDetector(
                  onTap: () {
                    final originalId = data['originalPostId'];
                    if (originalId != null && originalId is String) {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => PostDetailScreen(postId: originalId)));
                    }
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: context.textHigh.withOpacity(0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  if (originalAuthorId.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => UserProfileScreen(userId: originalAuthorId)),
                                    );
                                  }
                                },
                                child: Row(
                                  children: [
                                    UserAvatar(imageUrl: originalAuthorAvatar, name: originalAuthorName, radius: 14),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        originalAuthorName,
                                        style: TextStyle(fontWeight: FontWeight.w600, color: context.textHigh, fontSize: 13),
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (originalContent.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Text(
                              originalContent,
                              style: TextStyle(color: context.textHigh, fontSize: 13, height: 1.3),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        if (originalMediaUrls.isNotEmpty)
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
                            child: AspectRatio(
                              aspectRatio: 2.0,
                              child: Image.network(
                                originalMediaUrls.first.toString(),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 12.0),
                child: Row(
                  children: [
                    if (_likesCount > 0) ...[
                      Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
                              child: const Icon(Icons.thumb_up_alt, size: 10, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: GestureDetector(
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: context.textMed, 
                                    fontSize: 13,
                                    fontWeight: _firstLikerName != null ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (_likesCount == 0) const Spacer(),
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
                    Expanded(
                      child: _buildActionButton(
                        _isLiked ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
                        "Like",
                        _isLiked ? context.textHigh : context.textMed,
                        _toggleLike,
                      ),
                    ),
                    Expanded(
                      child: _buildActionButton(
                        Icons.comment_outlined,
                        "Comment",
                        context.textMed,
                        _showCommentsModal,
                      ),
                    ),
                    Expanded(
                      child: _buildActionButton(
                        Icons.repeat_rounded,
                        "Repost",
                        context.textMed,
                        _showRepostOptions,
                      ),
                    ),
                    Expanded(
                      child: _buildActionButton(
                        _isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
                        "Save",
                        _isSaved ? context.textHigh : context.textMed,
                        _savePost,
                      ),
                    ),
                    Expanded(
                      child: _buildActionButton(
                        Icons.share_outlined,
                        "Share",
                        context.textMed,
                        _handleShare,
                      ),
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


