import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/story_model.dart';
import '../../widgets/user_avatar.dart';

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

  @override
  void initState() {
    super.initState();
    _markStoryAsSeen();
    _startTimer();
  }

  Future<void> _markStoryAsSeen() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    final story = widget.stories[_currentIndex];
    if (story.seenBy.contains(user.uid)) return;

    try {
      await FirebaseFirestore.instance.collection('stories').doc(story.id).update({
        'seenBy': FieldValue.arrayUnion([user.uid])
      });
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
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_isPaused && _isMediaLoaded) {
        setState(() {
          _progress += 0.01; // Exactly 5 seconds (50ms * 100 steps)
          if (_progress >= 1.0) {
            _progress = 1.0;
            _nextStory();
          }
        });
      }
    });
  }

  void _nextStory() {
    if (!mounted) return;
    if (_currentIndex < widget.stories.length - 1) {
      setState(() {
        _currentIndex++;
        _progress = 0.0;
        _isMediaLoaded = false;
      });
      _markStoryAsSeen();
    } else {
      _closeViewer();
    }
  }

  void _previousStory() {
    if (!mounted) return;
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _progress = 0.0;
        _isMediaLoaded = false;
      });
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
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stories.isEmpty) {
      return const Scaffold(body: Center(child: Text("No stories available")));
    }
    
    final story = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: (_) => setState(() => _isPaused = true),
        onLongPressEnd: (_) => setState(() => _isPaused = false),
        onTapUp: (details) {
          if (_isPaused) return; // Prevent tap actions if we were holding
          if (details.globalPosition.dx < MediaQuery.of(context).size.width / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > MediaQuery.of(context).size.width * 2 / 3) {
            _nextStory();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media
            story.mediaUrl.isNotEmpty
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      CachedNetworkImage(
                        imageUrl: story.mediaUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        imageBuilder: (context, imageProvider) {
                          // Once the image is ready, we start the timer
                          if (!_isMediaLoaded) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _isMediaLoaded = true);
                            });
                          }
                          return Image(image: imageProvider, fit: BoxFit.cover);
                        },
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: (context, url, error) {
                           if (!_isMediaLoaded) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _isMediaLoaded = true);
                            });
                          }
                          return const Center(
                            child: Icon(Icons.error_outline, color: Colors.white, size: 48),
                          );
                        },
                      ),
                    ],
                  )
                : Builder(builder: (context) {
                    if (!_isMediaLoaded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) setState(() => _isMediaLoaded = true);
                      });
                    }
                    return const Center(
                      child: Icon(Icons.broken_image_outlined, color: Colors.white, size: 48),
                    );
                  }),

            // Top Progress Bar & User Info (Folded/Faded during hold)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _isPaused ? 0.0 : 1.0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  child: Column(
                    children: [
                      Row(
                        children: widget.stories.asMap().entries.map((entry) {
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              height: 3,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: entry.key < _currentIndex 
                                  ? 1.0 
                                  : (entry.key == _currentIndex ? _progress.clamp(0.0, 1.0) : 0.0),
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
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1),
                            ),
                            child: UserAvatar(
                              imageUrl: story.userAvatar,
                              name: story.userName,
                              radius: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
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
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.close, color: Colors.white, size: 28),
                            onPressed: _closeViewer,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Caption (Folded/Faded during hold)
            if (story.caption.isNotEmpty)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: _isPaused ? 0.0 : 1.0,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        story.caption,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
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
