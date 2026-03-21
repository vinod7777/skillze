import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/user_avatar.dart';
import '../../services/notification_service.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/mention_helper.dart';

class CommentsModal extends StatefulWidget {
  final DocumentSnapshot postDoc;
  final VoidCallback? onCommentPosted;
  final VoidCallback? onCommentDeleted;

  const CommentsModal({
    super.key, 
    required this.postDoc,
    this.onCommentPosted,
    this.onCommentDeleted,
  });

  @override
  State<CommentsModal> createState() => _CommentsModalState();
}

class _CommentsModalState extends State<CommentsModal> {
  final _commentController = TextEditingController();
  bool _isPosting = false;

  // Reply state
  String? _replyToCommentId;
  String? _replyToAuthorName;

  // Mention state
  List<String> _followingList = [];
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchFollowingList();
    _commentController.addListener(_onCommentChanged);
  }

  Future<void> _fetchFollowingList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          _followingList = List<String>.from(doc.data()?['followingList'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error fetching following list: $e');
    }
  }

  void _onCommentChanged() {
    final text = _commentController.text;
    final selection = _commentController.selection;
    if (selection.baseOffset == -1) return;

    final cursorPosition = selection.baseOffset;
    if (cursorPosition > text.length) return;

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtSignIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSignIndex != -1) {
      if (lastAtSignIndex == 0 || textBeforeCursor[lastAtSignIndex - 1] == ' ' || textBeforeCursor[lastAtSignIndex - 1] == '\n') {
        final query = textBeforeCursor.substring(lastAtSignIndex + 1);
        if (RegExp(r'^[a-zA-Z0-9_]*$').hasMatch(query)) {
          setState(() {
            _currentMentionQuery = query;
            _mentionStartIndex = lastAtSignIndex;
          });
          _fetchMentionSuggestions(query);
          return;
        }
      }
    }

    if (_currentMentionQuery != null) {
      setState(() {
        _currentMentionQuery = null;
        _mentionSuggestions = [];
      });
    }
  }

  Future<void> _fetchMentionSuggestions(String query) async {
    if (query.isEmpty) {
      if (_followingList.isEmpty) return;
      final uidsToFetch = _followingList.take(10).toList();
      if (uidsToFetch.isEmpty) return;
      
      final snapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: uidsToFetch).get();
      if (mounted && _currentMentionQuery == "") {
        setState(() {
          _mentionSuggestions = snapshot.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
        });
      }
      return;
    }

    final queryLower = query.toLowerCase();
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: queryLower)
        .where('username', isLessThan: '${queryLower}z')
        .limit(20)
        .get();

    if (mounted && _currentMentionQuery == query) {
      final results = snapshot.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
      final filtered = results.where((u) => _followingList.contains(u['uid'])).toList();
      setState(() {
        _mentionSuggestions = filtered;
      });
    }
  }

  void _insertMention(String username) {
    if (_mentionStartIndex == -1) return;
    
    final text = _commentController.text;
    final textBefore = text.substring(0, _mentionStartIndex);
    final textAfter = text.substring(_commentController.selection.baseOffset);
    
    final newText = '$textBefore@$username $textAfter';
    
    setState(() {
      _commentController.text = newText;
      _commentController.selection = TextSelection.collapsed(offset: _mentionStartIndex + username.length + 2);
      _currentMentionQuery = null;
      _mentionSuggestions = [];
    });
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  String _getPostAuthorId() {
    final data = widget.postDoc.data() as Map<String, dynamic>? ?? {};
    return data['authorId'] ?? '';
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (ProfanityFilterService.hasProfanity(text)) {
      showProfanityWarning(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please log in to comment')));
      return;
    }

    setState(() => _isPosting = true);

    try {
      // Get user info
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final userName = userData['name'] ?? 'Unknown User';
      final userProfileImage = userData['profileImageUrl'];

      if (_replyToCommentId != null) {
        // Posting a reply to a comment
        await widget.postDoc.reference
            .collection('comments')
            .doc(_replyToCommentId)
            .collection('replies')
            .add({
              'authorId': user.uid,
              'authorName': userName,
              'authorProfileImageUrl': userProfileImage,
              'content': text,
              'timestamp': FieldValue.serverTimestamp(),
              'likes': 0,
              'likedBy': [],
            });

        // Increment reply count on parent comment
        await widget.postDoc.reference
            .collection('comments')
            .doc(_replyToCommentId)
            .update({'replyCount': FieldValue.increment(1)});

        // Increment total comments count on post
        await widget.postDoc.reference.update({
          'commentsCount': FieldValue.increment(1),
        });

        // Send Notification to comment author
        final commentDoc = await widget.postDoc.reference
            .collection('comments')
            .doc(_replyToCommentId)
            .get();
        final commentAuthorId = commentDoc.data()?['authorId'];
        if (commentAuthorId != null) {
          NotificationService.sendNotification(
            targetUserId: commentAuthorId,
            type: 'comment',
            message: 'replied to your comment',
            postId: widget.postDoc.id,
            commentId: _replyToCommentId,
          );
        }

        // Process Mentions
        await MentionHelper.processMentions(
          text: text,
          currentUserId: user.uid,
          currentUserName: userName,
          notificationType: 'mention_comment',
          notificationMessage: 'mentioned you in a comment',
          postId: widget.postDoc.id,
          commentId: _replyToCommentId,
        );
      } else {
        // Posting a top-level comment
        await widget.postDoc.reference.collection('comments').add({
          'authorId': user.uid,
          'authorName': userName,
          'authorProfileImageUrl': userProfileImage,
          'content': text,
          'timestamp': FieldValue.serverTimestamp(),
          'likes': 0,
          'likedBy': [],
          'isPinned': false,
          'replyCount': 0,
        });

        // Increment comments count on post
        await widget.postDoc.reference.update({
          'commentsCount': FieldValue.increment(1),
        });

        // Send Notification to post author
        final targetUserId = _getPostAuthorId();
        if (targetUserId.isNotEmpty) {
          NotificationService.sendNotification(
            targetUserId: targetUserId,
            type: 'comment',
            message: 'commented on your post',
            postId: widget.postDoc.id,
          );
        }

        // Process Mentions
        await MentionHelper.processMentions(
          text: text,
          currentUserId: user.uid,
          currentUserName: userName,
          notificationType: 'mention_comment',
          notificationMessage: 'mentioned you in a comment',
          postId: widget.postDoc.id,
        );
      }

      _commentController.clear();
      if (widget.onCommentPosted != null) {
        widget.onCommentPosted!();
      }
      _cancelReply();
      if (mounted) {
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to post comment: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  Future<void> _toggleCommentLike(DocumentReference commentRef) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await commentRef.get();
      if (!doc.exists) return;

      final data = doc.data() as Map<String, dynamic>? ?? {};
      List likedBy = data['likedBy'] ?? [];

      if (likedBy.contains(user.uid)) {
        await commentRef.update({
          'likes': FieldValue.increment(-1),
          'likedBy': FieldValue.arrayRemove([user.uid]),
        });
      } else {
        await commentRef.update({
          'likes': FieldValue.increment(1),
          'likedBy': FieldValue.arrayUnion([user.uid]),
        });
      }
    } catch (e) {
      // Silently fail
    }
  }

  Future<void> _pinComment(String commentId, bool currentlyPinned) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final postAuthorId = _getPostAuthorId();
    if (user.uid != postAuthorId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only the post author can pin comments')),
      );
      return;
    }

    try {
      if (!currentlyPinned) {
        // Unpin all other comments first
        final allComments = await widget.postDoc.reference
            .collection('comments')
            .where('isPinned', isEqualTo: true)
            .get();
        for (var doc in allComments.docs) {
          await doc.reference.update({'isPinned': false});
        }
      }

      // Toggle pin on this comment
      await widget.postDoc.reference
          .collection('comments')
          .doc(commentId)
          .update({'isPinned': !currentlyPinned});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              currentlyPinned ? 'Comment unpinned' : 'Comment pinned',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  void _startReply(String commentId, String authorName) {
    setState(() {
      _replyToCommentId = commentId;
      _replyToAuthorName = authorName;
    });
    // Optional: Focus the input field when starting a reply
    if (mounted) {
      // Small delay just to ensure the UI updates first
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          // You could use a FocusNode if you have one attached to the TextField
        }
      });
    }
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToAuthorName = null;
    });
  }

  String _formatTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) return 'Just now';
    final diff = DateTime.now().difference(timestamp.toDate());
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  Future<void> _deleteComment(DocumentSnapshot commentDoc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('Delete Comment', style: TextStyle(color: context.textHigh)),
        content: Text('Are you sure you want to delete this comment?', style: TextStyle(color: context.textMed)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: context.textLow)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final commentData = commentDoc.data() as Map<String, dynamic>;
        final int replyCount = commentData['replyCount'] ?? 0;
        await commentDoc.reference.delete();
        await widget.postDoc.reference.update({
          'commentsCount': FieldValue.increment(-(1 + replyCount)),
        });
        if (widget.onCommentDeleted != null) {
          widget.onCommentDeleted!();
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comment deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting comment: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteReply(DocumentReference replyRef, DocumentReference commentRef) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('Delete Reply', style: TextStyle(color: context.textHigh)),
        content: Text('Are you sure you want to delete this reply?', style: TextStyle(color: context.textMed)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: context.textLow)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await replyRef.delete();
        await commentRef.update({
          'replyCount': FieldValue.increment(-1),
        });
        // Also decrement total comments count on post
        await widget.postDoc.reference.update({
          'commentsCount': FieldValue.increment(-1),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reply deleted')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting reply: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final postAuthorId = _getPostAuthorId();
    final isPostAuthor = currentUserId == postAuthorId;

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          // Drag Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 48,
              height: 4,
              decoration: BoxDecoration(
                color: context.border.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Comments',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textHigh,
                  ),
                ),
                StreamBuilder<DocumentSnapshot>(
                  stream: widget.postDoc.reference.snapshots(),
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                    final totalComments = data?['commentsCount'] ?? 0;
                    return Text(
                      '$totalComments comments',
                      style: TextStyle(
                        color: context.textMed,
                        fontSize: 14,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Divider(color: context.border.withValues(alpha: 0.1)),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: widget.postDoc.reference
                  .collection('comments')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(color: context.primary),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No comments yet. Be the first!',
                      style: TextStyle(color: context.textMed),
                    ),
                  );
                }

                // Sort pinned comments to the top client-side
                final allDocs = snapshot.data!.docs;
                final pinned = allDocs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['isPinned'] == true;
                }).toList();
                final unpinned = allDocs.where((d) {
                  final data = d.data() as Map<String, dynamic>;
                  return data['isPinned'] != true;
                }).toList();
                final docs = [...pinned, ...unpinned];

                return ListView.separated(
                  padding: const EdgeInsets.all(24),
                  physics: const BouncingScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 24),
                  itemBuilder: (context, index) {
                    final commentDoc = docs[index];
                    final commentData =
                        commentDoc.data() as Map<String, dynamic>;
                    return _buildCommentItem(
                      commentDoc: commentDoc,
                      commentData: commentData,
                      currentUserId: currentUserId,
                      isPostAuthor: isPostAuthor,
                    );
                  },
                );
              },
            ),
          ),

          // Reply indicator
          if (_replyToAuthorName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                   Icon(
                    Icons.reply_rounded,
                    size: 16,
                    color: context.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Replying to $_replyToAuthorName',
                    style: TextStyle(
                      color: context.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _cancelReply,
                    child: Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: context.textMed,
                    ),
                  ),
                ],
              ),
            ),

          // Mentions suggestion box
          if (_mentionSuggestions.isNotEmpty && _currentMentionQuery != null) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: context.surfaceLightColor,
                border: Border(top: BorderSide(color: context.border.withValues(alpha: 0.2))),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  )
                ],
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _mentionSuggestions.length,
                itemBuilder: (context, index) {
                  final user = _mentionSuggestions[index];
                  final username = user['username'] ?? '';
                  final name = user['name'] ?? '';
                  final avatar = user['profileImageUrl'] ?? user['authorProfileImageUrl'] ?? user['photoUrl'] ?? '';
                  
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar.isEmpty ? const Icon(Icons.person, size: 14) : null,
                    ),
                    title: Text(username, style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(name, style: TextStyle(color: context.textMed, fontSize: 12)),
                    onTap: () => _insertMention(username),
                  );
                },
              ),
            ),
          ],
          
          SafeArea(
            child: Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: context.surfaceLightColor.withValues(alpha: 0.5),
                border: Border(
                  top: BorderSide(color: context.border.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: context.border.withValues(alpha: 0.2)),
                      ),
                      child: TextField(
                        controller: _commentController,
                        style: TextStyle(color: context.textHigh),
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _postComment(),
                        decoration: InputDecoration(
                          hintText: _replyToAuthorName != null
                              ? 'Reply to $_replyToAuthorName... (use @username)'
                              : 'Add a comment... (use @username to mention)',
                          hintStyle: TextStyle(
                            color: context.textLow,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _isPosting ? null : _postComment,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFF0F2F6A), Color(0xFF1A4A8A)]),
                      ),
                      child: _isPosting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentItem({
    required DocumentSnapshot commentDoc,
    required Map<String, dynamic> commentData,
    required String currentUserId,
    required bool isPostAuthor,
  }) {
    final commentId = commentDoc.id;
    final authorName = commentData['authorName'] ?? 'Unknown';
    final authorId = commentData['authorId'] ?? '';
    final content = commentData['content'] ?? '';
    final timestamp = commentData['timestamp'] as Timestamp?;
    final likesCount = commentData['likes'] ?? 0;
    final likedBy = List<String>.from(commentData['likedBy'] ?? []);
    final isPinned = commentData['isPinned'] ?? false;
    final replyCount = commentData['replyCount'] ?? 0;

    final isLikedByMe = likedBy.contains(currentUserId);
    final timeAgoLabel = _formatTimeAgo(timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isPinned)
          Padding(
            padding: const EdgeInsets.only(left: 52, bottom: 6),
            child: Row(
              children: [
                Icon(Icons.push_pin_rounded, size: 12, color: context.primary),
                const SizedBox(width: 4),
                Text(
                  'Pinned by author',
                  style: TextStyle(
                    color: context.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(authorId).snapshots(),
          builder: (context, userSnap) {
            final userData = userSnap.data?.data() as Map<String, dynamic>?;
            final displayName = userData?['name'] ?? authorName;
            final displayAvatar = userData?['profileImageUrl'] ?? 
                                userData?['photoUrl'] ?? 
                                commentData['authorProfileImageUrl'];

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(
                  imageUrl: displayAvatar,
                  name: displayName,
                  radius: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: context.textHigh,
                            ),
                          ),
                          if (authorId == _getPostAuthorId())
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: context.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Author',
                                style: TextStyle(
                                  color: context.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          const SizedBox(width: 8),
                          Text(
                            timeAgoLabel,
                            style: TextStyle(
                              color: context.textMed,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        content,
                        style: TextStyle(
                          color: context.textHigh,
                          height: 1.4,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _toggleCommentLike(commentDoc.reference),
                            child: Row(
                              children: [
                                Icon(
                                  isLikedByMe
                                      ? Icons.favorite_rounded
                                      : Icons.favorite_border_rounded,
                                  size: 16,
                                  color: isLikedByMe
                                      ? Colors.redAccent
                                      : context.textMed,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '$likesCount',
                                  style: TextStyle(
                                    color: isLikedByMe
                                        ? Colors.redAccent
                                        : context.textMed,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          GestureDetector(
                            onTap: () => _startReply(commentId, displayName),
                            child: Text(
                              'Reply',
                              style: TextStyle(
                                color: context.textMed,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isPostAuthor) ...[
                            const SizedBox(width: 20),
                            GestureDetector(
                              onTap: () => _pinComment(commentId, isPinned),
                              child: Row(
                                children: [
                                  Icon(
                                    isPinned
                                        ? Icons.push_pin_rounded
                                        : Icons.push_pin_outlined,
                                    size: 14,
                                    color: isPinned
                                        ? context.primary
                                        : context.textMed,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isPinned ? 'Unpin' : 'Pin',
                                    style: TextStyle(
                                      color: isPinned
                                          ? context.primary
                                          : context.textMed,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (currentUserId == authorId || isPostAuthor) ...[
                            const SizedBox(width: 20),
                            GestureDetector(
                              onTap: () => _deleteComment(commentDoc),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Delete',
                                    style: TextStyle(
                                      color: Colors.redAccent.withValues(alpha: 0.8),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),

                      if (replyCount > 0)
                        _buildRepliesSection(commentDoc.reference, commentId),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildRepliesSection(DocumentReference commentRef, String commentId) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: StreamBuilder<QuerySnapshot>(
        stream: commentRef
            .collection('replies')
            .orderBy('timestamp', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const SizedBox();
          }

          final replies = snapshot.data!.docs;
          final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
          final postAuthorId = _getPostAuthorId();
          final isPostAuthor = currentUserId == postAuthorId;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding: const EdgeInsets.only(left: 12),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: context.border.withValues(alpha: 0.1), width: 2),
                  ),
                ),
                child: Column(
                  children: replies.map((replyDoc) {
                    final replyData = replyDoc.data() as Map<String, dynamic>;
                    final replyAuthor = replyData['authorName'] ?? 'Unknown';
                    final replyContent = replyData['content'] ?? '';
                    final replyTimestamp = replyData['timestamp'] as Timestamp?;
                    final replyLikes = replyData['likes'] ?? 0;
                    final replyLikedBy = List<String>.from(
                      replyData['likedBy'] ?? [],
                    );
                    final isReplyLikedByMe = replyLikedBy.contains(
                      currentUserId,
                    );

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('users').doc(replyData['authorId']).snapshots(),
                            builder: (context, userSnap) {
                              final userData = userSnap.data?.data() as Map<String, dynamic>?;
                              final displayAvatar = userData?['profileImageUrl'] ?? 
                                                  userData?['authorProfileImageUrl'] ?? 
                                                  userData?['photoUrl'] ?? 
                                                  userData?['authorAvatar'] ?? 
                                                  replyData['authorProfileImageUrl'];
                              final displayName = userData?['name'] ?? replyAuthor;

                              return UserAvatar(
                                imageUrl: displayAvatar,
                                name: displayName,
                                radius: 14,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StreamBuilder<DocumentSnapshot>(
                                      stream: FirebaseFirestore.instance.collection('users').doc(replyData['authorId']).snapshots(),
                                      builder: (context, userSnap) {
                                        final userData = userSnap.data?.data() as Map<String, dynamic>?;
                                        final displayName = userData?['name'] ?? replyAuthor;
                                        return Text(
                                          displayName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: context.textHigh,
                                            fontSize: 13,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatTimeAgo(replyTimestamp),
                                      style: TextStyle(
                                        color: context.textMed,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  replyContent,
                                  style: TextStyle(
                                    color: context.textHigh,
                                    fontSize: 13,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _toggleCommentLike(
                                        replyDoc.reference,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isReplyLikedByMe
                                                ? Icons.favorite_rounded
                                                : Icons.favorite_border_rounded,
                                            size: 14,
                                            color: isReplyLikedByMe
                                                ? Colors.redAccent
                                                : context.textMed,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '$replyLikes',
                                            style: TextStyle(
                                              color: isReplyLikedByMe
                                                  ? Colors.redAccent
                                                  : context.textMed,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    GestureDetector(
                                      onTap: () => _startReply(commentId, replyAuthor),
                                      child: Text(
                                        'Reply',
                                        style: TextStyle(
                                          color: context.textMed,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    if (currentUserId == replyData['authorId'] || isPostAuthor) ...[
                                      const SizedBox(width: 16),
                                      GestureDetector(
                                        onTap: () => _deleteReply(replyDoc.reference, commentRef),
                                        child: Text(
                                          'Delete',
                                          style: TextStyle(
                                            color: Colors.redAccent.withValues(alpha: 0.8),
                                            fontSize: 11,
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
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
