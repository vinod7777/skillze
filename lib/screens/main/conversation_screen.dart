import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/skeleton_replacement.dart';
import 'package:skillze/screens/main/user_profile_screen.dart';
import 'chat_info_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'custom_camera_screen.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/notification_service.dart';
import '../../services/push_notification_service.dart';

import '../../services/call_service.dart';
import 'call_screen.dart';

import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../utils/mention_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/image_viewer_dialog.dart';
import '../../utils/avatar_helper.dart';
import '../../widgets/linkified_text.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';

class ConversationScreen extends StatefulWidget {
  final String chatId;
  final String otherUserId;
  final String otherUserName;

  const ConversationScreen({
    super.key,
    required this.chatId,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen>
    with WidgetsBindingObserver {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _iBlockedOther = false;
  bool _otherBlockedMe = false;
  final FocusNode _messageFocus = FocusNode();
  final FocusNode _searchFocus = FocusNode();
  bool _isSearchFocused = false;
  Stream<QuerySnapshot>? _getMessagesStream;
  StreamSubscription<QuerySnapshot>? _messagesSubscription;
  Future<String?>? _getOtherUserProfileFuture;

  String? _cachedMyName;
  String? _cachedMyPhoto;
  String? _cachedOtherToken;
  List<String>? _cachedOtherMutedUsers;
  List<String>? _cachedOtherRestrictedUsers;

  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<int> _searchMatchIndices =
      []; // Indices of messages that match the query
  int _currentMatchIndex = -1; // Current focused match index
  final Map<int, GlobalKey> _messageKeys =
      {}; // Keys for each message item to support scrolling to result

  bool _isTyping = false;
  Timer? _typingTimer;
  bool _showEmojiPicker = false;

  Stream<QuerySnapshot> get _messagesStream {
    _getMessagesStream ??= FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
    return _getMessagesStream!;
  }

  Future<String?> get _otherUserProfileFuture {
    _getOtherUserProfileFuture ??= _getOtherUserProfileImageUrl();
    return _getOtherUserProfileFuture!;
  }

  Future<void> _sendImage() async {
    if (_iBlockedOther || _otherBlockedMe) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: context.textHigh),
              title: Text('Camera', style: TextStyle(color: context.textHigh)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? file = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
                );
                if (file != null) {
                  _showConfirmSendDialog(file);
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.photo_library_rounded,
                color: context.textHigh,
              ),
              title: Text('Gallery', style: TextStyle(color: context.textHigh)),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image = await _picker.pickImage(
                  source: ImageSource.gallery,
                );
                if (image != null) {
                  _showConfirmSendDialog(image);
                }
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showConfirmSendDialog(XFile file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text('Send Photo?', style: TextStyle(color: context.textHigh)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                onTap: () {
                  ImageViewerDialog.show(
                    context,
                    null,
                    'Preview',
                    filePath: file.path,
                    isCircular: false,
                  );
                },
                child: kIsWeb
                    ? Image.network(file.path, height: 250, fit: BoxFit.cover)
                    : Image.file(
                        io.File(file.path),
                        height: 250,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Do you want to send this photo to ${widget.otherUserName}?',
              style: TextStyle(color: context.textMed, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textLow)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadAndSendImage(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Send',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadAndSendImage(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      // Using your provided ImgBB API key
      const imgbbApiKey = '9b144936080b6683b78410f3898f743d';
      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload?key=$imgbbApiKey'),
        body: {'image': base64Image},
      );
      final jsonResp = jsonDecode(response.body);
      final imageUrl = jsonResp['data']?['url'];
      if (imageUrl != null) {
        final user = FirebaseAuth.instance.currentUser;
        await Future.wait([
          FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .collection('messages')
              .add({
                'senderId': user?.uid,
                'imageUrl': imageUrl,
                'timestamp': FieldValue.serverTimestamp(),
                'status': 'sent',
              }),
          FirebaseFirestore.instance
              .collection('chats')
              .doc(widget.chatId)
              .update({
                'lastMessage': '📸 sent a photo',
                'lastMessageTime': FieldValue.serverTimestamp(),
                'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
              }),
        ]);

        // Always send notification regardless of cached token state
        final isMuted = _cachedOtherMutedUsers?.contains(user?.uid) ?? false;
        final isRestricted =
            _cachedOtherRestrictedUsers?.contains(user?.uid) ?? false;
        if (!isMuted && !isRestricted) {
          NotificationService.sendNotification(
            targetUserId: widget.otherUserId,
            type: 'chat',
            message: '📸 Sent a photo',
            chatId: widget.chatId,
            actorName: _cachedMyName,
            actorPhoto: _cachedMyPhoto,
            recipientFcmToken: _cachedOtherToken,
          );
        }
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Photo sent!')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    PushNotificationService.activeChatId = widget.chatId;
    // Initializers are now handled lazily by getters for robustness
    _getMessagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _getOtherUserProfileFuture = _getOtherUserProfileImageUrl();
    _markAsRead();
    WidgetsBinding.instance.addObserver(this);

    _preCacheData();

    // Listen to messages to mark as read in real-time
    _messagesSubscription = _messagesStream.listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        // Find if any message from the other user is not seen yet
        bool hasUnseen = snapshot.docs.any((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['senderId'] == widget.otherUserId &&
              data['status'] != 'seen';
        });

        if (hasUnseen) {
          _markAsRead();
        }
      }
    });

    _checkBlockStatuses();

    _messageController.addListener(_onMessageChanged);
    _messageFocus.addListener(() {
      if (_messageFocus.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    _searchFocus.addListener(() => setState(() => _isSearchFocused = _searchFocus.hasFocus));
  }

  Future<void> _startCall(bool isVideo) async {
    if (_iBlockedOther || _otherBlockedMe) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot call this user')),
      );
      return;
    }

    final callService = CallService();
    await callService.initialize();

    // Get callee avatar
    String? calleeAvatar;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      calleeAvatar = doc.data()?['profileImageUrl'];
    } catch (_) {}

    await callService.startCall(
      calleeId: widget.otherUserId,
      calleeName: widget.otherUserName,
      calleeAvatar: calleeAvatar,
      chatId: widget.chatId,
      isVideo: isVideo,
    );

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const CallScreen(isIncoming: false),
        ),
      );
    }
  }

  @override
  void dispose() {
    if (PushNotificationService.activeChatId == widget.chatId) {
      PushNotificationService.activeChatId = null;
    }
    _messagesSubscription?.cancel();
    _messageController.removeListener(_onMessageChanged);
    _messageController.dispose();
    _messageFocus.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _preCacheData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      // My data
      FirebaseFirestore.instance.collection('users').doc(user.uid).get().then((
        doc,
      ) {
        if (mounted) {
          setState(() {
            _cachedMyName = doc.data()?['name'];
            _cachedMyPhoto = doc.data()?['profileImageUrl'];
          });
        }
      });

      // Other user's FCM data
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get()
          .then((doc) {
            if (mounted) {
              setState(() {
                _cachedOtherToken = doc.data()?['fcmToken'];
                _cachedOtherMutedUsers = List<String>.from(
                  doc.data()?['mutedUsers'] ?? [],
                );
                _cachedOtherRestrictedUsers = List<String>.from(
                  doc.data()?['restrictedUsers'] ?? [],
                );
              });
            }
          });
    } catch (e) {
      debugPrint('Pre-cache error: $e');
    }
  }



  void _onMessageChanged() {
    _handleTyping();
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (selection.baseOffset == -1) return;

    final cursorPosition = selection.baseOffset;
    if (cursorPosition > text.length) return;

    final textBeforeCursor = text.substring(0, cursorPosition);
    final lastAtSignIndex = textBeforeCursor.lastIndexOf('@');

    if (lastAtSignIndex != -1) {
      if (lastAtSignIndex == 0 ||
          textBeforeCursor[lastAtSignIndex - 1] == ' ' ||
          textBeforeCursor[lastAtSignIndex - 1] == '\n') {
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

  void _handleTyping() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _iBlockedOther || _otherBlockedMe) return;

    if (!_isTyping) {
      _isTyping = true;
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing_${user.uid}': true}).catchError((_) {});
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _isTyping = false;
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing_${user.uid}': false}).catchError((_) {});
    });
  }

  Future<void> _fetchMentionSuggestions(String query) async {
    if (query.isEmpty) {
      // Just fetch some general users if query is empty
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(20)
          .get();

      if (mounted && (_currentMentionQuery == null || _currentMentionQuery!.isEmpty)) {
        setState(() {
          _mentionSuggestions = snapshot.docs
              .map((d) => {'uid': d.id, ...d.data()})
              .toList();
        });
      }
      return;
    }

    // Give suggestions according to what the user types
    final queryLower = query.toLowerCase();
    final usernameSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: queryLower)
        .where('username', isLessThan: '${queryLower}z')
        .limit(20)
        .get();

    if (mounted && _currentMentionQuery == query) {
      final results = usernameSnapshot.docs
          .map((d) => {'uid': d.id, ...d.data()})
          .toList();
      setState(() {
        _mentionSuggestions = results;
      });
    }
  }

  void _insertMention(String username) {
    if (_mentionStartIndex == -1) return;

    final text = _messageController.text;
    final textBefore = text.substring(0, _mentionStartIndex);
    final textAfter = text.substring(_messageController.selection.baseOffset);

    final newText = '$textBefore@$username $textAfter';

    setState(() {
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(
        offset: _mentionStartIndex + username.length + 2,
      );
      _currentMentionQuery = null;
      _mentionSuggestions = [];
    });
  }

  Future<void> _checkBlockStatuses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Check if I blocked other
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final myBlockedList = List<String>.from(
        myDoc.data()?['blockedUsers'] ?? [],
      );

      // Check if other blocked me
      final otherDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      final otherBlockedList = List<String>.from(
        otherDoc.data()?['blockedUsers'] ?? [],
      );

      if (mounted) {
        setState(() {
          _iBlockedOther = myBlockedList.contains(widget.otherUserId);
          _otherBlockedMe = otherBlockedList.contains(user.uid);
        });
      }
    } catch (e) {
      // Ignore
    }
  }

  Future<void> _toggleBlockStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      if (_iBlockedOther) {
        await userRef.update({
          'blockedUsers': FieldValue.arrayRemove([widget.otherUserId]),
        });
      } else {
        await userRef.update({
          'blockedUsers': FieldValue.arrayUnion([widget.otherUserId]),
        });
      }
      await _checkBlockStatuses();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_iBlockedOther ? 'User blocked' : 'User unblocked'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update block status'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markAsRead();
    }
  }

  /// Marks messages from the other user as read.
  Future<void> _markAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      debugPrint('Skillze_Sync: Marking chat ${widget.chatId} as read for user ${user.uid}');
      
      // 1. Reset unread count for the current user in the chat metadata
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({
            'unreadCount_${user.uid}': 0,
            'lastRead_${user.uid}': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // 2. Find and update individual message statuses to 'seen'
      // We only query messages where the OTHER user is the sender and status is not 'seen'
      final snapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('senderId', isEqualTo: widget.otherUserId)
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('Skillze_Sync: No unread messages found from ${widget.otherUserId}');
        return;
      }

      final WriteBatch batch = FirebaseFirestore.instance.batch();
      int updatedCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final currentStatus = data['status'];
        
        // Update if status is not 'seen'
        if (currentStatus != 'seen') {
          batch.update(doc.reference, {'status': 'seen'});
          updatedCount++;
        }
      }

      if (updatedCount > 0) {
        await batch.commit();
        debugPrint('Skillze_Sync: Updated $updatedCount messages to "seen"');
      }
    } catch (e) {
      debugPrint('Skillze_Sync Error: Failed to mark messages as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _iBlockedOther || _otherBlockedMe) return;

    if (ProfanityFilterService.hasProfanity(text)) {
      showProfanityWarning(context);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSending = true);
    _messageController.clear();
    _scrollToBottom();

    try {
      // ── Run message write + chat metadata update IN PARALLEL ──────────────
      await Future.wait([
        FirebaseFirestore.instance
            .collection('chats')
            .get(), // Dummy read to bypass indexing if it was deleted entirely earlier but it's not needed here.
        FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .add({
              'senderId': user.uid,
              'text': text,
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'sent',
            }),
        FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .update({
              'lastMessage': text,
              'lastMessageTime': FieldValue.serverTimestamp(),
              'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
            }),
      ]);

      // ── Push Notification — always fire, use cached token when available ──
      final isMuted = _cachedOtherMutedUsers?.contains(user.uid) ?? false;
      final isRestricted =
          _cachedOtherRestrictedUsers?.contains(user.uid) ?? false;

      if (!isMuted && !isRestricted) {
        // Pass cached token directly → zero extra Firestore reads when cache is warm
        // If token is null (cache not ready yet), NotificationService will fetch it
        NotificationService.sendNotification(
          targetUserId: widget.otherUserId,
          type: 'chat',
          message: text,
          chatId: widget.chatId,
          actorName: _cachedMyName,
          actorPhoto: _cachedMyPhoto,
          recipientFcmToken: _cachedOtherToken, // null = fallback to Firestore
        );
      }

      await MentionHelper.processMentions(
        text: text,
        currentUserId: user.uid,
        currentUserName: _cachedMyName ?? 'Someone',
        notificationType: 'mention_chat',
        notificationMessage: 'mentioned you in a chat',
        chatId: widget.chatId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // With reverse: true, 0.0 is the bottom
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<String?> _getOtherUserProfileImageUrl() async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();
    return AvatarHelper.getAvatarUrl(doc.data());
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: context.bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        titleSpacing: 12,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () {
            if (_isSearching) {
              setState(() {
                _isSearching = false;
                _searchQuery = '';
                _searchController.clear();
                _searchMatchIndices = [];
                _currentMatchIndex = -1;
              });
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: _isSearching
            ? _buildSearchField()
            : GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatInfoScreen(
                        userId: widget.otherUserId,
                        userName: widget.otherUserName,
                        chatId: widget.chatId,
                      ),
                    ),
                  );

                  if (result == 'triggerSearch') {
                    setState(() {
                      _isSearching = true;
                    });
                  }
                },
                child: Row(
                  children: [
                    FutureBuilder<String?>(
                      future: _otherUserProfileFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return SkeletonAvatar(
                            style: SkeletonAvatarStyle(
                              shape: BoxShape.circle,
                              width: 32,
                              height: 32,
                            ),
                          );
                        }
                        return UserAvatar(
                          imageUrl: snapshot.data,
                          name: widget.otherUserName,
                          radius: 16,
                          gradient: LinearGradient(
                            colors: [
                              context.primary,
                              context.primary.withValues(alpha: 0.8),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.otherUserName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: context.textHigh,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Tap for info',
                            style: TextStyle(
                              color: context.textMed,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: Icon(Icons.search_rounded, color: context.isDark ? Colors.white : context.textHigh, size: 20),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          IconButton(
            icon: Icon(Icons.call_rounded, color: context.textHigh, size: 22),
            onPressed: () => _startCall(false),
            tooltip: 'Voice Call',
          ),
          IconButton(
            icon: Icon(Icons.videocam_rounded, color: context.textHigh, size: 24),
            onPressed: () => _startCall(true),
            tooltip: 'Video Call',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
          builder: (context, chatMetaSnapshot) {
            final chatData = chatMetaSnapshot.data?.data() as Map<String, dynamic>?;
            final deletedAtMap = chatData?['deletedAt'] as Map<String, dynamic>?;
            final userDeletedAt = deletedAtMap?[currentUserId] as Timestamp?;

            return Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Error: ${snapshot.error}',
                            style: TextStyle(color: context.textHigh),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final rawMessages = snapshot.data?.docs ?? [];
                      
                      // Filter out messages deleted before 'deletedAt' for ONLY this user
                      final messages = rawMessages.where((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final msgTimestamp = data['timestamp'] as Timestamp?;
                        if (userDeletedAt != null && msgTimestamp != null) {
                          return msgTimestamp.compareTo(userDeletedAt) > 0;
                        }
                        return true;
                      }).toList();

                      if (messages.isEmpty) {
                        return Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: context.textHigh.withValues(alpha: 0.2),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    color: context.textHigh.withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Start a conversation!',
                                  style: TextStyle(
                                    color: context.textHigh.withValues(alpha: 0.3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Update search matches for navigation
                      if (_searchQuery.isNotEmpty) {
                        final List<int> matches = [];
                        final query = _searchQuery.toLowerCase();
                        for (int i = 0; i < messages.length; i++) {
                          final data = messages[i].data() as Map<String, dynamic>;
                          final text = (data['text'] ?? '')
                              .toString()
                              .toLowerCase();
                          if (text.contains(query)) {
                            matches.add(i);
                          }
                        }
                        _searchMatchIndices = matches;
                      } else {
                        _searchMatchIndices = [];
                      }

                      return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 20,
                        ),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final doc = messages[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final isMe = data['senderId'] == currentUserId;
                          final timestamp = data['timestamp'] as Timestamp?;
                          final date = timestamp?.toDate() ?? DateTime.now();

                          // Date grouping logic
                          bool showDateHeader = false;
                          if (index == messages.length - 1) {
                            showDateHeader = true;
                          } else {
                            final nextDoc = messages[index + 1];
                            final nextTimestamp =
                                nextDoc['timestamp'] as Timestamp?;
                            if (nextTimestamp != null) {
                              if (!_isSameDay(date, nextTimestamp.toDate())) {
                                showDateHeader = true;
                              }
                            }
                          }

                          bool showTimestamp = true;
                          bool showAvatar = true;

                          if (index > 0) {
                            final newerDoc =
                                messages[index - 1].data() as Map<String, dynamic>;
                            final newerTimestamp =
                                newerDoc['timestamp'] as Timestamp?;
                            if (newerTimestamp != null &&
                                data['senderId'] == newerDoc['senderId']) {
                              final newerDate = newerTimestamp.toDate();
                              final diff = date.difference(newerDate).abs();
                              if (diff.inMinutes < 1) {
                                showTimestamp = false;
                                showAvatar = false;
                              }
                            }
                          }

                          if (!_messageKeys.containsKey(index)) {
                            _messageKeys[index] = GlobalKey();
                          }

                          Widget item = _buildMessageBubble(
                            doc,
                            isMe,
                            data,
                            showTimestamp: showTimestamp,
                            showAvatar: showAvatar,
                          );

                          if (showDateHeader) {
                            item = Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [_buildDateHeader(date), item],
                            );
                          }

                          return Container(key: _messageKeys[index], child: item);
                        },
                      );
                    },
                  ),
                ),

                StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data != null) {
                      final chatData =
                          snapshot.data!.data() as Map<String, dynamic>? ?? {};
                      final isOtherTyping =
                          chatData['typing_${widget.otherUserId}'] == true;
                      if (isOtherTyping) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(left: 16, bottom: 8, top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: context.isDark ? Colors.white12 : Colors.grey[200],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.textHigh.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.textHigh,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'typing...',
                                  style: TextStyle(
                                    color: context.textHigh,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),

                if (_iBlockedOther || _otherBlockedMe)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 24,
                    ),
                    color: context.textHigh.withValues(alpha: 0.05),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: context.textHigh,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _iBlockedOther
                              ? 'You have blocked this user'
                              : 'This user is unavailable',
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_iBlockedOther) ...[
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _toggleBlockStatus,
                            child: Text('Unblock', style: TextStyle(color: context.textHigh)),
                          ),
                        ],
                      ],
                    ),
                  ),

                if (_mentionSuggestions.isNotEmpty && _currentMentionQuery != null)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 180),
                    decoration: BoxDecoration(
                      color: context.surfaceLightColor,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(10),
                      ),
                      border: Border(
                        top: BorderSide(color: context.textHigh.withValues(alpha: 0.2)),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: _mentionSuggestions.length,
                      itemBuilder: (context, index) {
                        final user = _mentionSuggestions[index];
                        final username = user['username'] ?? '';
                        final name = user['name'] ?? '';

                        return ListTile(
                          dense: true,
                          leading: UserAvatar(
                            imageUrl: AvatarHelper.getAvatarUrl(user),
                            name: name,
                            radius: 14,
                          ),
                          title: Text(
                            username,
                            style: TextStyle(
                              color: context.textHigh,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            name,
                            style: TextStyle(color: context.textHigh.withValues(alpha: 0.5), fontSize: 12),
                          ),
                          onTap: () => _insertMention(username),
                        );
                      },
                    ),
                  ),

                // Message Input Area
                Container(
                  decoration: BoxDecoration(
                    color: context.bg,
                    border: Border(
                      top: BorderSide(
                        color: context.textHigh.withValues(alpha: 0.2),
                        width: 0.5,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SafeArea(
                        top: false,
                        bottom: !_showEmojiPicker,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: IconButton(
                                  onPressed: (_iBlockedOther || _otherBlockedMe)
                                      ? null
                                      : _sendImage,
                                  icon: Icon(
                                    Icons.add_circle_outline_rounded,
                                    color: context.textHigh,
                                    size: 26,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 44,
                                    maxHeight: 220,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.surfaceLightColor,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: context.textHigh.withValues(alpha: 0.2)),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: TextField(
                                    controller: _messageController,
                                    focusNode: _messageFocus,
                                    enabled: !(_iBlockedOther || _otherBlockedMe),
                                    maxLines: 10,
                                    minLines: 1,
                                    keyboardType: TextInputType.multiline,
                                    style: TextStyle(
                                      color: context.textHigh,
                                      fontSize: 15,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: (_iBlockedOther || _otherBlockedMe)
                                          ? 'Communication blocked'
                                          : 'Type a message...',
                                      hintStyle: TextStyle(
                                        color: context.textLow,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      prefixIcon: IconButton(
                                        iconSize: 22,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 40,
                                          minHeight: 40,
                                        ),
                                        icon: Icon(
                                          Icons.emoji_emotions_outlined,
                                          color: context.textHigh,
                                        ),
                                        onPressed: () {
                                          if (_showEmojiPicker) {
                                            setState(() => _showEmojiPicker = false);
                                            _messageFocus.requestFocus();
                                          } else {
                                            _messageFocus.unfocus();
                                            setState(() => _showEmojiPicker = true);
                                          }
                                        },
                                      ),
                                      prefixIconConstraints: const BoxConstraints(
                                        minWidth: 40,
                                        minHeight: 40,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 4,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: (_iBlockedOther || _otherBlockedMe)
                                    ? null
                                    : _sendMessage,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: context.isDark ? Colors.white : context.textHigh,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: context.textHigh.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: _isSending
                                      ? const Center(
                                          child: SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
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
                      if (_showEmojiPicker)
                        SizedBox(
                          height: 250,
                          width: double.infinity,
                          child: EmojiPicker(
                            textEditingController: _messageController,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _isSearchFocused
              ? context.primary.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        autofocus: true,
        onChanged: (val) {
          setState(() {
            _searchQuery = val.trim().toLowerCase();
            _currentMatchIndex = -1;
          });
        },
        style: TextStyle(
          color: context.textHigh,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          hintText: 'Search chat history...',
          hintStyle: TextStyle(color: context.textLow, fontSize: 14),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: context.primary,
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
          suffixIcon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _searchMatchIndices.isNotEmpty
                ? Container(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${_currentMatchIndex + 1}/${_searchMatchIndices.length}',
                          style: TextStyle(
                            color: context.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 24,
                            color: context.primary,
                          ),
                          onPressed: () => _navigateSearch(1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 24,
                            color: context.primary,
                          ),
                          onPressed: () => _navigateSearch(-1),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  void _navigateSearch(int delta) {
    if (_searchMatchIndices.isEmpty) return;
    int nextIndex = _currentMatchIndex + delta;
    if (nextIndex >= 0 && nextIndex < _searchMatchIndices.length) {
      _jumpToMatch(nextIndex);
    }
  }

  void _jumpToMatch(int matchIndex) {
    if (matchIndex < 0 || matchIndex >= _searchMatchIndices.length) return;
    final int itemIndex = _searchMatchIndices[matchIndex];
    final key = _messageKeys[itemIndex];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        alignment: 0.5,
      );
    } else {
      // Fallback scroll
      _scrollController.animateTo(
        itemIndex * 80.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
    setState(() {
      _currentMatchIndex = matchIndex;
    });
  }

  bool _isSameDay(DateTime d1, DateTime d2) {
    return d1.year == d2.year && d1.month == d2.month && d1.day == d2.day;
  }

  Widget _buildDateHeader(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _getDateHeaderText(date),
            style: TextStyle(
              color: context.textHigh.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _getDateHeaderText(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return "Today";
    if (messageDate == yesterday) return "Yesterday";
    if (messageDate.year == now.year) {
      final months = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec",
      ];
      return "${date.day} ${months[date.month - 1]}";
    }
    return "${date.day}/${date.month}/${date.year}";
  }

  Widget _buildMessageBubble(
    DocumentSnapshot doc,
    bool isMe,
    Map<String, dynamic> data, {
    bool showTimestamp = true,
    bool showAvatar = true,
  }) {
    final timestamp = data['timestamp'] as Timestamp?;
    String timeLabel = '';
    if (timestamp != null) {
      final dt = timestamp.toDate();
      timeLabel =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    final text = data['text'] ?? '';
    final imageUrl = data['imageUrl'] as String?;
    final isEdited = data['isEdited'] ?? false;
    final status = data['status'] ?? 'sent';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (showAvatar)
              FutureBuilder<String?>(
                future: _getOtherUserProfileFuture,
                builder: (context, avatarSnap) => UserAvatar(
                  imageUrl: avatarSnap.data,
                  name: widget.otherUserName,
                  radius: 14,
                ),
              )
            else
              const SizedBox(width: 28), // Placeholder for missing avatar
            const SizedBox(width: 8),
          ],
          Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onLongPress: () => _showMessageOptions(doc.id, data, isMe),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  padding: imageUrl != null && imageUrl.isNotEmpty
                      ? const EdgeInsets.all(4)
                      : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isMe 
                        ? context.primary
                        : (context.isDark ? context.surfaceLightColor : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isMe ? 20 : 0),
                      bottomRight: Radius.circular(isMe ? 0 : 20),
                    ),
                    border: !isMe 
                        ? Border.all(color: context.isDark ? Colors.white24 : Colors.grey[300]!)
                        : null,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (imageUrl != null && imageUrl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: GestureDetector(
                            onTap: () => ImageViewerDialog.show(
                              context,
                              imageUrl,
                              'Message Image',
                              isCircular: false,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.6,
                                  maxHeight: 250,
                                ),
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  loadingBuilder:
                                      (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Container(
                                          height: 200,
                                          width: 200,
                                          alignment: Alignment.center,
                                          color: context.isDark
                                              ? Colors.white.withValues(alpha: 0.05)
                                              : Colors.black.withValues(alpha: 0.05),
                                          child: CircularProgressIndicator(
                                            value:
                                                loadingProgress
                                                        .expectedTotalBytes !=
                                                    null
                                                ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                : null,
                                            color: context.primary.withValues(alpha: 0.5),
                                            strokeWidth: 2,
                                          ),
                                        );
                                      },
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        height: 200,
                                        width: 200,
                                        alignment: Alignment.center,
                                        color: context.isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.black.withValues(alpha: 0.05),
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          color: context.textLow,
                                        ),
                                      ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (text.isNotEmpty)
                        LinkifiedText(
                          text: text,
                          highlightText: _searchQuery,
                          onMentionTap: (u) => _navigateToProfileByUsername(u),
                          style: TextStyle(
                            color: isMe ? context.onPrimary : context.textHigh,
                            fontSize: 15,
                            height: 1.3,
                          ),
                          linkStyle: TextStyle(
                            color: isMe ? context.onPrimary.withValues(alpha: 0.8) : context.primary,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      // Extract link and show AnyLinkPreview
                      if (text.isNotEmpty &&
                          RegExp(r"(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})", caseSensitive: false)
                              .hasMatch(text))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: AnyLinkPreview(
                            link: RegExp(r"(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})", caseSensitive: false).firstMatch(text)!.group(0)!,
                            displayDirection: UIDirection.uiDirectionHorizontal,
                            cache: const Duration(hours: 1),
                            backgroundColor: Colors.transparent,
                            errorWidget: const SizedBox.shrink(),
                            titleStyle: TextStyle(
                              color: isMe ? context.onPrimary : context.textHigh,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            bodyStyle: TextStyle(
                              color: isMe ? context.onPrimary.withValues(alpha: 0.7) : context.textMed,
                              fontSize: 12,
                            ),
                            borderRadius: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (showTimestamp) const SizedBox(height: 4),
              // Time and Ticks completely outside the bubble
              if (showTimestamp)
                Padding(
                  padding: EdgeInsets.only(
                    left: isMe ? 0 : 4,
                    right: isMe ? 4 : 0,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isEdited)
                        Text(
                          'edited ',
                          style: TextStyle(
                            color: context.textMed.withValues(alpha: 0.6),
                            fontSize: 10,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          color: context.isDark ? Colors.white60 : Colors.black54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(
                          status == 'seen' ? Icons.done_all : Icons.done,
                          size: 14,
                          color: status == 'seen'
                              ? Colors.blue[400]
                              : (context.isDark ? Colors.white54 : Colors.grey[600]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }

  void _showMessageOptions(
    String messageId,
    Map<String, dynamic> msgData,
    bool isMe,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            if (msgData['text'] != null)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: context.textHigh),
                title: Text(
                  'Copy Text',
                  style: TextStyle(color: context.textHigh),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: msgData['text']));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
            if (isMe && msgData['text'] != null)
              ListTile(
                leading: Icon(Icons.edit_rounded, color: context.textHigh),
                title: Text(
                  'Edit Message',
                  style: TextStyle(color: context.textHigh),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(messageId, msgData['text']);
                },
              ),
            if (isMe)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.redAccent,
                ),
                title: const Text(
                  'Unsend',
                  style: TextStyle(color: Colors.redAccent),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMessage(messageId);
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showEditDialog(String messageId, String currentText) {
    final controller = TextEditingController(text: currentText);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        title: Text('Edit Message', style: TextStyle(color: context.textHigh)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: context.textHigh),
          decoration: InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: TextStyle(color: context.textLow),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: context.textLow)),
          ),
          TextButton(
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != currentText) {
                _editMessage(messageId, newText);
              }
              Navigator.pop(context);
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: context.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToProfileByUsername(String username) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final userId = query.docs.first.id;
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: userId),
          ),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('User @$username not found')));
      }
    } catch (e) {
      debugPrint('Error navigating to profile: $e');
    }
  }

  Future<void> _editMessage(String messageId, String newText) async {
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(messageId)
          .update({'text': newText, 'isEdited': true});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
