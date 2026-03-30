import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:ui' as ui;
import '../../widgets/user_avatar.dart';
import '../../theme/app_theme.dart';
import 'user_profile_screen.dart';
import '../../models/story_model.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  const StoryViewerScreen({super.key, required this.stories});

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  int _currentIndex = 0;
  double _progress = 0.0;
  Timer? _timer;
  bool _isPaused = false;
  bool _isMediaLoaded = false;
  bool _isDeleting = false;
  // Cache resolved avatars: userId -> url
  final Map<String, String?> _resolvedAvatars = {};

  @override
  void initState() {
    super.initState();
    _markStoryAsSeen();
    _startTimer();
    for (final story in widget.stories) {
      _resolveAvatarForStory(story);
    }
  }

  Future<void> _resolveAvatarForStory(Story story) async {
    if (_resolvedAvatars.containsKey(story.userId)) return;
    if (story.userAvatar.isNotEmpty) {
      _resolvedAvatars[story.userId] = story.userAvatar;
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(story.userId)
          .get();
      if (doc.exists && mounted) {
        final data = doc.data();
        final url = data?['profileImageUrl'] ??
            data?['photoURL'] ??
            data?['photoUrl'] ??
            data?['avatar'];
        if (mounted) setState(() => _resolvedAvatars[story.userId] = url);
      }
    } catch (_) {
      _resolvedAvatars[story.userId] = null;
    }
  }

  Future<void> _markStoryAsSeen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final story = widget.stories[_currentIndex];
    if (story.userId == user.uid) return;
    if (story.seenBy.contains(user.uid)) return;
    try {
      await FirebaseFirestore.instance
          .collection('stories')
          .doc(story.id)
          .update({'seenBy': FieldValue.arrayUnion([user.uid])});
    } catch (e) {
      debugPrint('Error marking story as seen: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (!_isPaused && _isMediaLoaded) {
        setState(() {
          _progress += 0.01;
          if (_progress >= 1.0) { _progress = 1.0; _nextStory(); }
        });
      }
    });
  }

  void _nextStory() {
    if (!mounted) return;
    if (_currentIndex < widget.stories.length - 1) {
      setState(() { _currentIndex++; _progress = 0.0; _isMediaLoaded = false; });
      _markStoryAsSeen();
    } else {
      _closeViewer();
    }
  }

  void _previousStory() {
    if (!mounted) return;
    if (_currentIndex > 0) {
      setState(() { _currentIndex--; _progress = 0.0; _isMediaLoaded = false; });
      _markStoryAsSeen();
    }
  }

  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return 'Yesterday';
  }

  void _closeViewer() {
    _timer?.cancel();
    _timer = null;
    if (mounted) Navigator.of(context).maybePop();
  }

  // ─── Delete Story ──────────────────────────────────────────────────────────
  void _showDeleteOptions() {
    _timer?.cancel();
    setState(() => _isPaused = true);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1E),
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Story Options',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Delete Story',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteStory();
                },
              ),
              ListTile(
                leading: const Icon(Icons.close_rounded, color: Colors.white60),
                title: const Text(
                  'Cancel',
                  style: TextStyle(color: Colors.white60, fontSize: 16),
                ),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPaused = false);
        _startTimer();
      }
    });
  }

  Future<void> _confirmDeleteStory() async {
    final story = widget.stories[_currentIndex];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Delete Story?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'This story will be permanently removed. This action cannot be undone.',
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await FirebaseFirestore.instance
          .collection('stories')
          .doc(story.id)
          .delete();

      if (!mounted) return;

      if (widget.stories.length > 1) {
        widget.stories.removeAt(_currentIndex);
        final newIndex = _currentIndex >= widget.stories.length
            ? widget.stories.length - 1
            : _currentIndex;
        setState(() {
          _currentIndex = newIndex;
          _progress = 0.0;
          _isMediaLoaded = false;
          _isDeleting = false;
        });
        _startTimer();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Story deleted'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } else {
        _closeViewer();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
        _startTimer();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchViewers(List<String> uids) async {
    final List<Map<String, dynamic>> users = [];
    final safeUids = uids.take(100).toList(); // limit to 100 for performance
    for (int i = 0; i < safeUids.length; i += 10) {
      final chunk = safeUids.sublist(i, i + 10 > safeUids.length ? safeUids.length : i + 10);
      try {
        final snapshot = await FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: chunk).get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          data['id'] = doc.id;
          users.add(data);
        }
      } catch (_) {}
    }
    return users;
  }

  void _showViewersSheet(Story story) {
    if (story.seenBy.isEmpty) return;
    
    // Filter out the author's own ID from the view count and list
    final realViewers = story.seenBy.where((uid) => uid != story.userId).toList();
    if (realViewers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No views yet!')));
      return;
    }

    _timer?.cancel();
    setState(() => _isPaused = true);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.remove_red_eye_rounded, color: context.textHigh, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '${realViewers.length} Viewed',
                      style: TextStyle(color: context.textHigh, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textHigh),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Divider(color: context.border.withOpacity(0.5)),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _fetchViewers(realViewers),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: context.primary));
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(child: Text('No viewer details found', style: TextStyle(color: context.textMed)));
                  }
                  final docs = snapshot.data!;
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final data = docs[index];
                      final imageUrl = data['profileImageUrl'] ?? data['photoURL'] ?? data['avatar'] ?? '';
                      final name = data['displayName'] ?? data['name'] ?? 'User';
                      final username = data['username'] ?? '';
                      return ListTile(
                        leading: UserAvatar(imageUrl: imageUrl, name: name, radius: 20),
                        title: Text(name, style: TextStyle(color: context.textHigh, fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: username.isNotEmpty ? Text('@$username', style: TextStyle(color: context.textMed, fontSize: 11)) : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: data['id'])),
                          ).then((_) {
                            if (mounted) {
                              setState(() => _isPaused = false);
                              _startTimer();
                            }
                          });
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() => _isPaused = false);
        _startTimer();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(body: Center(child: Text('No stories available')));
    }

    final story = widget.stories[_currentIndex];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isMyStory = story.userId == currentUserId;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => setState(() => _isPaused = true),
        onLongPressEnd: (_) => setState(() => _isPaused = false),
        onTapUp: (details) {
          if (_isPaused) return;
          if (details.globalPosition.dx < MediaQuery.of(context).size.width / 3) {
            _previousStory();
          } else if (details.globalPosition.dx >
              MediaQuery.of(context).size.width * 2 / 3) {
            _nextStory();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Media ────────────────────────────────────────────────────────
            story.mediaUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: story.mediaUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    imageBuilder: (context, imageProvider) {
                      if (!_isMediaLoaded) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _isMediaLoaded = true);
                        });
                      }
                      return Image(image: imageProvider, fit: BoxFit.cover);
                    },
                    placeholder: (context, url) => const Center(
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    ),
                    errorWidget: (context, url, error) {
                      if (!_isMediaLoaded) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _isMediaLoaded = true);
                        });
                      }
                      return const Center(
                        child: Icon(Icons.error_outline,
                            color: Colors.white, size: 48),
                      );
                    },
                  )
                : Builder(builder: (context) {
                    if (!_isMediaLoaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isMediaLoaded = true);
                      });
                    }
                    return const Center(
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white, size: 48),
                    );
                  }),

            // ── Deleting overlay ─────────────────────────────────────────────
            if (_isDeleting)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            // ── Top bar: progress + user info ────────────────────────────────
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isPaused ? 0.0 : 1.0,
              child: SafeArea(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Column(
                    children: [
                      // Progress bars
                      Row(
                        children: widget.stories.asMap().entries.map((entry) {
                          return Expanded(
                            child: Container(
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: entry.key < _currentIndex
                                    ? 1.0
                                    : (entry.key == _currentIndex
                                        ? _progress.clamp(0.0, 1.0)
                                        : 0.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      // User row
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _timer?.cancel();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfileScreen(userId: story.userId),
                                ),
                              ).then((_) => _startTimer());
                            },
                            child: UserAvatar(
                              imageUrl: _resolvedAvatars[story.userId] ??
                                  story.userAvatar,
                              name: story.userName,
                              radius: 20,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          GestureDetector(
                            onTap: () {
                              _timer?.cancel();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      UserProfileScreen(userId: story.userId),
                                ),
                              ).then((_) => _startTimer());
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  story.userName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                Text(
                                  _getTimeAgo(story.timestamp),
                                  style: TextStyle(
                                    color:
                                        Colors.white.withOpacity(0.7),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // ⋮ menu — only for your own stories
                          if (isMyStory)
                            IconButton(
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              onPressed: _showDeleteOptions,
                            ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 28),
                            onPressed: _closeViewer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Caption ──────────────────────────────────────────────────────
            if (story.caption.isNotEmpty)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                left: 20,
                right: 20,
                bottom: 80, // Sits above the viewers counter
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isPaused ? 0.0 : 1.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
                        ),
                        child: Text(
                          story.caption,
                          style: const TextStyle(
                            color: Colors.white, 
                            fontSize: 15, 
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
            // ── View Count (Bottom Left) ──────────────────────────────────────────────────────
            if (isMyStory)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 20,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: _isPaused ? 0.0 : 1.0,
                  child: GestureDetector(
                    onTap: () => _showViewersSheet(story),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white24, width: 0.5),
                        boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))
                        ]
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.remove_red_eye_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${story.seenBy.where((v) => v != story.userId).length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
