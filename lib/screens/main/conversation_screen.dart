import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../widgets/user_avatar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/skeleton_replacement.dart';
import 'chat_info_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../services/push_notification_service.dart';
import 'custom_camera_screen.dart';
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;

import 'call_screen.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../utils/mention_helper.dart';
import '../../theme/app_theme.dart';

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

class _ConversationScreenState extends State<ConversationScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _iBlockedOther = false;
  bool _otherBlockedMe = false;
  Stream<QuerySnapshot>? _getMessagesStream;
  Future<String?>? _getOtherUserProfileFuture;
  
  List<String> _followingList = [];
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;

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

  Future<void> _startWebRTCCall(bool isVideo) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (widget.otherUserId == user.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot call yourself')),
      );
      return;
    }

    final callId = FirebaseFirestore.instance.collection('calls').doc().id;
    final myName =
        (await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get())
            .data()?['name'] ??
        'Someone';

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CallScreen(
            callId: callId,
            otherUserId: widget.otherUserId,
            otherUserName: widget.otherUserName,
            chatId: widget.chatId,
            isVideo: isVideo,
            isReceiver: false,
          ),
        ),
      );
    }

    final otherUserDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.otherUserId)
        .get();
    final otherUserToken = otherUserDoc.data()?['fcmToken'];
    final mutedUsers = List<String>.from(otherUserDoc.data()?['mutedUsers'] ?? []);
    final restrictedUsers = List<String>.from(otherUserDoc.data()?['restrictedUsers'] ?? []);
    if (otherUserToken != null && !mutedUsers.contains(user.uid) && !restrictedUsers.contains(user.uid)) {
      await PushNotificationService.sendNotification(
        recipientToken: otherUserToken,
        title: "Incoming Call",
        body: "$myName is calling...",
        extraData: {
          'type': 'call',
          'callId': callId,
          'callerName': myName,
          'callerId': user.uid,
          'isVideo': isVideo.toString(),
        },
      );
    }
  }

  Future<void> _sendImage() async {
    if (_iBlockedOther || _otherBlockedMe) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              leading: Icon(
                Icons.camera_alt_rounded,
                color: context.textHigh,
              ),
              title: Text(
                'Camera',
                style: TextStyle(color: context.textHigh),
              ),
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
              title: Text(
                'Gallery',
                style: TextStyle(color: context.textHigh),
              ),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Send Photo?',
          style: TextStyle(color: context.textHigh),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kIsWeb
                  ? Image.network(file.path, height: 250, fit: BoxFit.cover)
                  : Image.file(
                      io.File(file.path),
                      height: 250,
                      fit: BoxFit.cover,
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
            child: Text(
              'Cancel',
              style: TextStyle(color: context.textLow),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _uploadAndSendImage(file);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
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
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .add({
              'senderId': user?.uid,
              'imageUrl': imageUrl,
              'timestamp': FieldValue.serverTimestamp(),
            });

        // Trigger Push Notification
        final otherUserDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.otherUserId)
            .get();
        final otherUserToken = otherUserDoc.data()?['fcmToken'];
        final mutedUsers = List<String>.from(otherUserDoc.data()?['mutedUsers'] ?? []);
        final restrictedUsers = List<String>.from(otherUserDoc.data()?['restrictedUsers'] ?? []);
        if (otherUserToken != null && !mutedUsers.contains(user?.uid) && !restrictedUsers.contains(user?.uid)) {
          final myName =
              (await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user?.uid)
                      .get())
                  .data()?['name'] ??
              'Someone';
          await PushNotificationService.sendNotification(
            recipientToken: otherUserToken,
            title: myName,
            body: 'ðŸ“· Sent a photo',
            extraData: {
              'type': 'chat',
              'chatId': widget.chatId,
              'otherUserId': user?.uid,
              'otherUserName': myName,
            },
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
    // Initializers are now handled lazily by getters for robustness
    _getMessagesStream = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _getOtherUserProfileFuture = _getOtherUserProfileImageUrl();
    _markAsRead();
    _checkBlockStatuses();
    
    _fetchFollowingList();
    _messageController.addListener(_onMessageChanged);
  }

  Future<void> _fetchFollowingList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    _followingList = List<String>.from(doc.data()?['followingList'] ?? []);
  }

  void _onMessageChanged() {
    final text = _messageController.text;
    final selection = _messageController.selection;
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
    
    final text = _messageController.text;
    final textBefore = text.substring(0, _mentionStartIndex);
    final textAfter = text.substring(_messageController.selection.baseOffset);
    
    final newText = '$textBefore@$username $textAfter';
    
    setState(() {
      _messageController.text = newText;
      _messageController.selection = TextSelection.collapsed(offset: _mentionStartIndex + username.length + 2);
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'unreadCount_${user.uid}': 0});
    } catch (e) {
      // Ignore
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

    try {
      // Add message to subcollection
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .add({
            'senderId': user.uid,
            'text': text,
            'timestamp': FieldValue.serverTimestamp(),
          });

      // Update chat metadata
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': text,
            'lastMessageTime': FieldValue.serverTimestamp(),
            'unreadCount_${widget.otherUserId}': FieldValue.increment(1),
          });

      // --- NEW: Trigger Push Notification ---
      final otherUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.otherUserId)
          .get();
      final otherUserToken = otherUserDoc.data()?['fcmToken'];
      final mutedUsers = List<String>.from(otherUserDoc.data()?['mutedUsers'] ?? []);
      final restrictedUsers = List<String>.from(otherUserDoc.data()?['restrictedUsers'] ?? []);
      if (otherUserToken != null && !mutedUsers.contains(user.uid) && !restrictedUsers.contains(user.uid)) {
        final myName =
            (await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get())
                .data()?['name'] ??
            'Someone';
        await PushNotificationService.sendNotification(
          recipientToken: otherUserToken,
          title: myName,
          body: text,
          extraData: {
            'type': 'chat',
            'chatId': widget.chatId,
            'otherUserId': user.uid,
            'otherUserName': myName,
          },
        );
      }

      await MentionHelper.processMentions(
        text: text,
        currentUserId: user.uid,
        currentUserName: 'Someone',
        notificationType: 'mention_chat',
        notificationMessage: 'mentioned you in a chat',
        chatId: widget.chatId,
      );

      // Scroll to bottom
      _scrollToBottom();
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
    return doc.data()?['profileImageUrl'] as String?;
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatInfoScreen(
                  userId: widget.otherUserId,
                  userName: widget.otherUserName,
                  chatId: widget.chatId,
                ),
              ),
            );
          },
          child: Row(
            children: [
              FutureBuilder<String?>(
                future: _otherUserProfileFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SkeletonAvatar(
                      style: SkeletonAvatarStyle(
                        shape: BoxShape.circle,
                        width: 40,
                        height: 40,
                      ),
                    );
                  }
                  return UserAvatar(
                    imageUrl: snapshot.data,
                    name: widget.otherUserName,
                    radius: 20,
                    gradient: LinearGradient(
                      colors: [context.primary, context.primary.withValues(alpha: 0.8)],
                    ),
                  );
                },
              ),
              SizedBox(width: 12),
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
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          _buildCallButton(
            Icons.call_rounded,
            'Audio Call',
            () => _startWebRTCCall(false),
          ),
          const SizedBox(width: 6),
          _buildCallButton(
            Icons.videocam_rounded,
            'Video Call',
            () => _startWebRTCCall(true),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _messagesStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: SkeletonListView(itemCount: 8));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 60,
                            color: context.textLow,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: TextStyle(color: context.textMed),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Say hello! 👋',
                            style: TextStyle(
                              color: context.textMed,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final docs = snapshot.data!.docs;

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    itemCount: docs.length,
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (context, index) {
                      final msgData =
                          docs[index].data() as Map<String, dynamic>;
                      final isMe = msgData['senderId'] == currentUserId;
                      final isEdited = msgData['isEdited'] ?? false;
                      final timestamp = msgData['timestamp'] as Timestamp?;

                      String timeLabel = '';
                      if (timestamp != null) {
                        final dt = timestamp.toDate();
                        timeLabel =
                            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                      }

                      // â”€â”€ Call log message â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                      if (msgData['type'] == 'call') {
                        return _buildCallBubble(
                          msgData: msgData,
                          isMe: isMe,
                          timeLabel: timeLabel,
                        );
                      }

                      final text = msgData['text'] ?? '';
                      final imageUrl = msgData['imageUrl'] as String?;

                      Widget messageContent;
                      if (imageUrl != null && imageUrl.isNotEmpty) {
                        // Show image bubble
                        messageContent = GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (_) => Dialog(
                                backgroundColor: Colors.transparent,
                                child: InteractiveViewer(
                                  child: Image.network(
                                    imageUrl,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                          if (loadingProgress == null) {
                                            return child;
                                          }
                                          return const Center(
                                            child: SkeletonAvatar(
                                              style: SkeletonAvatarStyle(
                                                width: 300,
                                                height: 300,
                                              ),
                                            ),
                                          );
                                        },
                                  ),
                                ),
                              ),
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              imageUrl,
                              width: 160,
                              height: 160,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) {
                                      return child;
                                    }
                                    return const SkeletonAvatar(
                                      style: SkeletonAvatarStyle(
                                        width: 160,
                                        height: 160,
                                      ),
                                    );
                                  },
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    width: 160,
                                    height: 160,
                                    color: context.surfaceLightColor,
                                    child: Icon(
                                      Icons.broken_image,
                                      color: context.textLow,
                                    ),
                                  ),
                            ),
                          ),
                        );
                      } else {
                        // Show text bubble
                        messageContent = Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                color: isMe ? Colors.white : context.textHigh,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            if (isEdited)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Edited',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16.0),
                        child: Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: GestureDetector(
                            onLongPress: () => _showMessageOptions(
                              docs[index].id,
                              msgData,
                              isMe,
                            ),
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.75,
                              ),
                              padding: imageUrl != null && imageUrl.isNotEmpty
                                  ? EdgeInsets.all(4)
                                  : EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: isMe
                                      ? LinearGradient(
                                          colors: [
                                            context.primary,
                                            context.primary.withValues(alpha: 0.8),
                                          ],
                                        )
                                      : null,
                                  color: isMe
                                      ? null
                                      : context.surfaceLightColor.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(20),
                                  topRight: const Radius.circular(20),
                                  bottomLeft: isMe
                                      ? Radius.circular(20)
                                      : Radius.zero,
                                  bottomRight: isMe
                                      ? Radius.zero
                                      : Radius.circular(20),
                                ),
                                  border: isMe
                                      ? null
                                      : Border.all(
                                          color: context.border,
                                          width: 1,
                                        ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isMe
                                                  ? context.primary
                                                  : Colors.black)
                                              .withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                              ),
                              child: Column(
                                crossAxisAlignment: isMe
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  messageContent,
                                  const SizedBox(height: 6),
                                  Text(
                                    timeLabel,
                                    style: TextStyle(
                                      color:
                                          (isMe
                                                  ? Colors.white
                                                  : context.textMed)
                                              .withValues(alpha: 0.7),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            if (_iBlockedOther || _otherBlockedMe)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 24,
                ),
                color: Colors.redAccent.withValues(alpha: 0.1),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _iBlockedOther
                          ? 'You have blocked this user'
                          : 'This user is unavailable',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_iBlockedOther) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatInfoScreen(
                                userId: widget.otherUserId,
                                userName: widget.otherUserName,
                                chatId: widget.chatId,
                              ),
                            ),
                          ).then((_) => _checkBlockStatuses());
                        },
                        child: const Text('Unblock'),
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
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border(
                    top: BorderSide(color: context.border.withValues(alpha: 0.5)),
                  ),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))
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
                    final avatar = user['profileImageUrl'] ?? user['photoUrl'] ?? '';
                    
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

            // Message Input Area
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: context.bg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: context.surfaceLightColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.border.withValues(alpha: 0.3)),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.add_rounded,
                          color: context.primary,
                          size: 24,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: (_iBlockedOther || _otherBlockedMe)
                            ? null
                            : _sendImage,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: context.surfaceLightColor.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: TextField(
                          controller: _messageController,
                          enabled: !_iBlockedOther && !_otherBlockedMe,
                          style: TextStyle(
                            color: context.textHigh,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: InputDecoration(
                            hintText: (_iBlockedOther || _otherBlockedMe)
                                ? 'Communication blocked'
                                : 'Type a message...',
                            hintStyle: TextStyle(
                              color: context.textLow,
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: (_iBlockedOther || _otherBlockedMe)
                          ? null
                          : _sendMessage,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: context.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: context.primary.withValues(alpha: 0.3),
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
          ],
        ),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                leading: Icon(
                  Icons.copy_rounded,
                  color: context.textHigh,
                ),
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
                leading: Icon(
                  Icons.edit_rounded,
                  color: context.textHigh,
                ),
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
        title: Text(
          'Edit Message',
          style: TextStyle(color: context.textHigh),
        ),
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
            child: Text(
              'Cancel',
              style: TextStyle(color: context.textLow),
            ),
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

  // â”€â”€ Call log bubble â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Widget _buildCallButton(IconData icon, String tooltip, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: context.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: context.primary, size: 20),
      ),
    );
  }

  Widget _buildCallBubble({
    required Map<String, dynamic> msgData,
    required bool isMe,
    required String timeLabel,
  }) {
    final callStatus = msgData['callStatus'] as String? ?? 'missed';
    final duration = msgData['callDuration'] as int? ?? 0;

    final isAnswered = callStatus == 'answered';
    final isMissed = callStatus == 'missed';
    final isVideo = msgData['isVideo'] ?? false;

    // Icon & colour
    final IconData icon;
    final Color iconColor;
    final String label;
    final typeStr = isVideo ? 'Video call' : 'Audio call';

    if (isAnswered) {
      icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
      iconColor = Colors.greenAccent;
      final m = (duration ~/ 60).toString().padLeft(2, '0');
      final s = (duration % 60).toString().padLeft(2, '0');
      label = '$typeStr Â· $m:$s';
    } else if (isMissed) {
      icon = isVideo ? Icons.videocam_off_rounded : Icons.call_missed_rounded;
      iconColor = Colors.redAccent;
      label = isMe ? 'No answer' : 'Missed $typeStr';
    } else {
      // rejected
      icon = Icons.call_end_rounded;
      iconColor = Colors.orangeAccent;
      label = isMe ? 'Call declined' : 'Declined $typeStr';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: context.surfaceLightColor.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: context.textHigh,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: context.textLow,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
