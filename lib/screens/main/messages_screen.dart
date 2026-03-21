import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'conversation_screen.dart';
import '../../widgets/user_avatar.dart';
import '../../theme/app_theme.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedChatIds = {};
  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_isSelectionMode)
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: context.textHigh),
                          onPressed: () => setState(() => _selectedChatIds.clear()),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedChatIds.length} selected',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: context.textHigh,
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      'Messages',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: context.textHigh,
                      ),
                    ),
                  if (_isSelectionMode)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                      onPressed: () => _confirmDeleteChats(_selectedChatIds.toList()),
                    )
                  else
                    GestureDetector(
                      onTap: _showNewChatDialog,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: context.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: context.primary,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: context.surfaceLightColor,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, color: context.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                        style: TextStyle(color: context.textHigh, fontSize: 15, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          hintText: 'Search messages...',
                          hintStyle: TextStyle(color: context.textLow, fontSize: 15, fontWeight: FontWeight.w400),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,

                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.textLow.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded, size: 14, color: context.textMed),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Active Now List
            _buildActiveNowSection(),
            const SizedBox(height: 0),

            // Chat list
            Expanded(
              child: currentUser == null
                  ? const Center(child: Text('Please log in'))
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .where('participants', arrayContains: currentUser.uid)
                          .orderBy('lastMessageTime', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                          return Center(child: CircularProgressIndicator(color: context.primary));
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return _buildEmptyState();
                        }

                        final chats = snapshot.data!.docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (_searchQuery.isEmpty) return true;
                          final otherName = _getOtherUserName(data, currentUser.uid).toLowerCase();
                          return otherName.contains(_searchQuery);
                        }).toList();

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
                          itemCount: chats.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1, 
                            thickness: 1, 
                            color: context.border.withValues(alpha: 0.05),
                            indent: 80, // Align with text, not avatar
                          ),
                          itemBuilder: (context, index) {
                            final chatData = chats[index].data() as Map<String, dynamic>;
                            final chatId = chats[index].id;
                            final otherUserId = _getOtherUserId(chatData, currentUser.uid);
                            final otherUserName = _getOtherUserName(chatData, currentUser.uid);
                            final lastMessage = chatData['lastMessage'] ?? 'No messages yet';
                            final lastTime = chatData['lastMessageTime'] as Timestamp?;
                            final unreadCount = (chatData['unreadCount_${currentUser.uid}'] ?? 0) as int;
                            
                            final isSelected = _selectedChatIds.contains(chatId);

                            return Dismissible(
                              key: Key(chatId),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                ),
                                child: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              ),
                              confirmDismiss: (direction) => _confirmDeleteChats([chatId]),
                              child: _buildChatItem(
                                chatId,
                                otherUserId,
                                otherUserName,
                                lastMessage,
                                lastTime,
                                unreadCount,
                                chatData,
                                isSelected,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatItem(
    String chatId,
    String otherUserId,
    String otherUserName,
    String lastMessage,
    Timestamp? lastTime,
    int unreadCount,
    Map<String, dynamic> chatData,
    bool isSelected,
  ) {
    String timeStr = '';
    if (lastTime != null) {
      final diff = DateTime.now().difference(lastTime.toDate());
      if (diff.inDays > 0) {
        timeStr = '${diff.inDays}d';
      } else if (diff.inHours > 0) {
        timeStr = '${diff.inHours}h';
      } else if (diff.inMinutes > 0) {
        timeStr = '${diff.inMinutes}m';
      } else {
        timeStr = 'Now';
      }
    }

    final hasUnread = unreadCount > 0;

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedChatIds.remove(chatId);
            } else {
              _selectedChatIds.add(chatId);
            }
          });
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ConversationScreen(
                chatId: chatId,
                otherUserId: otherUserId,
                otherUserName: otherUserName,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        setState(() {
          if (isSelected) {
            _selectedChatIds.remove(chatId);
          } else {
            _selectedChatIds.add(chatId);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? context.primary.withValues(alpha: 0.05) : context.surfaceColor,
          border: isSelected 
            ? Border(
                left: BorderSide(color: context.primary, width: 4),
              )
            : null,
        ),
        child: Row(
          children: [
            UserChatAvatar(
              userId: otherUserId,
              name: otherUserName,
              chatData: chatData,
              showStatus: true,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        otherUserName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: hasUnread ? FontWeight.bold : FontWeight.w600,
                          color: context.textHigh,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnread ? context.primary : context.textLow,
                          fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: hasUnread ? context.textHigh : context.textMed,
                            fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: context.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveNowSection() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) return const SizedBox.shrink();
        final userData = userSnap.data?.data() as Map<String, dynamic>?;
        final followingList = List<String>.from(userData?['followingList'] ?? []);

        if (followingList.isEmpty) return const SizedBox.shrink();

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .where(FieldPath.documentId, whereIn: followingList.take(10).toList())
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            
            final activeUsers = snapshot.data!.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final bool isOnline = data['isOnline'] ?? false;
              final Timestamp? lastActive = data['lastActive'] as Timestamp?;
              
              if (isOnline) return true;
              if (lastActive != null) {
                final diff = DateTime.now().difference(lastActive.toDate());
                return diff.inMinutes < 5;
              }
              return false;
            }).toList();

            if (activeUsers.isEmpty) return const SizedBox.shrink();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    'Active Now',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textMed,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    scrollDirection: Axis.horizontal,
                    itemCount: activeUsers.length,
                    itemBuilder: (context, index) {
                      final doc = activeUsers[index];
                      final userData = doc.data() as Map<String, dynamic>;
                      final otherUserId = doc.id;
                      final otherUserName = userData['name'] ?? 'User';
                      final otherAvatar = userData['profileImageUrl'];

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: GestureDetector(
                          onTap: () => _startConversation(otherUserId, otherUserName, otherAvatar),
                          child: Column(
                            children: [
                              UserAvatar(
                                imageUrl: otherAvatar,
                                name: otherUserName,
                                radius: 26,
                                showOnlineStatus: true,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: 56,
                                child: Text(
                                  otherUserName.split(' ')[0],
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: context.textMed,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.surfaceLightColor,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.chat_bubble_outline_rounded, size: 48, color: context.textLow),
          ),
          const SizedBox(height: 16),
          Text('No messages yet', style: TextStyle(color: context.textMed, fontSize: 16)),
        ],
      ),
    );
  }

  String _getOtherUserId(Map<String, dynamic> chatData, String currentUid) {
    final participants = List<String>.from(chatData['participants'] ?? []);
    return participants.firstWhere((id) => id != currentUid, orElse: () => '');
  }

  String _getOtherUserName(Map<String, dynamic> chatData, String currentUid) {
    final names = chatData['participantNames'] as Map<String, dynamic>?;
    final otherUserId = _getOtherUserId(chatData, currentUid);
    return names?[otherUserId] ?? 'Unknown';
  }

  Future<bool> _confirmDeleteChats(List<String> chatIds) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          chatIds.length == 1 ? 'Delete Chat?' : 'Delete ${chatIds.length} Chats?',
          style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will permanently remove the chat history. This action cannot be undone.',
          style: TextStyle(color: context.textMed),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textLow)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in chatIds) {
        await FirebaseFirestore.instance.collection('chats').doc(id).delete();
      }
      setState(() {
        _selectedChatIds.removeAll(chatIds);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(chatIds.length == 1 ? 'Chat deleted' : '${chatIds.length} chats deleted')),
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _startConversation(String otherUserId, String otherUserName, String? otherAvatar) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // 1. Check if chat already exists
      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      String? chatId;
      for (var doc in chatQuery.docs) {
        final participants = List<String>.from(doc['participants']);
        if (participants.contains(otherUserId)) {
          chatId = doc.id;
          break;
        }
      }

      // 2. If no existing chat, create one
      if (chatId == null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
        final currentUserName = userDoc.data()?['name'] ?? 'User';
        final currentUserAvatar = userDoc.data()?['profileImageUrl'] ?? '';

        final newChat = await FirebaseFirestore.instance.collection('chats').add({
          'participants': [currentUser.uid, otherUserId],
          'participantNames': {
            currentUser.uid: currentUserName,
            otherUserId: otherUserName,
          },
          'participantProfileImages': {
            currentUser.uid: currentUserAvatar,
            otherUserId: otherAvatar ?? '',
          },
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount_${currentUser.uid}': 0,
          'unreadCount_$otherUserId': 0,
          'typing_${currentUser.uid}': false,
          'typing_$otherUserId': false,
        });
        chatId = newChat.id;
      }

      // 3. Navigate to conversation
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              chatId: chatId!,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting conversation: $e');
    }
  }

  void _showNewChatDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NewChatModal(),
    );
  }
}

class NewChatModal extends StatefulWidget {
  const NewChatModal({super.key});

  @override
  State<NewChatModal> createState() => _NewChatModalState();
}

class _NewChatModalState extends State<NewChatModal> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startChat(String otherUserId, String otherUserName, String? otherAvatar) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
      final currentUserName = userDoc.data()?['name'] ?? 'User';
      final currentUserAvatar = userDoc.data()?['profileImageUrl'] ?? '';

      final chatQuery = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: currentUser.uid)
          .get();

      String? chatId;
      for (var doc in chatQuery.docs) {
        final participants = List<String>.from(doc['participants']);
        if (participants.contains(otherUserId)) {
          chatId = doc.id;
          break;
        }
      }

      if (chatId == null) {
        final newChat = await FirebaseFirestore.instance.collection('chats').add({
          'participants': [currentUser.uid, otherUserId],
          'participantNames': {
            currentUser.uid: currentUserName,
            otherUserId: otherUserName,
          },
          'participantProfileImages': {
            currentUser.uid: currentUserAvatar,
            otherUserId: otherAvatar ?? '',
          },
          'lastMessage': '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'unreadCount_${currentUser.uid}': 0,
          'unreadCount_$otherUserId': 0,
        });
        chatId = newChat.id;
      }

      if (mounted) {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ConversationScreen(
              chatId: chatId!,
              otherUserId: otherUserId,
              otherUserName: otherUserName,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error starting chat: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: context.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text('New Message', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textHigh)),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: context.surfaceLightColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: context.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
                      style: TextStyle(color: context.textHigh, fontSize: 15, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Search followers...',
                        hintStyle: TextStyle(color: context.textLow, fontSize: 15, fontWeight: FontWeight.w400),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: context.textLow.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 14, color: context.textMed),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: currentUser == null
                ? const SizedBox.shrink()
                : StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
                    builder: (context, userSnap) {
                      if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
                      final userData = userSnap.data?.data() as Map<String, dynamic>?;
                      final followers = List<String>.from(userData?['followersList'] ?? []);

                      if (followers.isEmpty) return Center(child: Text('No followers yet', style: TextStyle(color: context.textMed)));

                      return StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('users')
                            .where(FieldPath.documentId, whereIn: followers.take(10).toList())
                            .snapshots(),
                        builder: (context, followersSnap) {
                          if (!followersSnap.hasData) return const Center(child: CircularProgressIndicator());
                          final users = followersSnap.data!.docs.where((doc) {
                            final name = (doc.data() as Map<String, dynamic>)['name']?.toString().toLowerCase() ?? '';
                            return name.contains(_searchQuery);
                          }).toList();

                          if (users.isEmpty) return Center(child: Text('No matching followers', style: TextStyle(color: context.textMed)));

                          return ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: users.length,
                            itemBuilder: (context, index) {
                              final uData = users[index].data() as Map<String, dynamic>;
                              final uId = users[index].id;
                              return ListTile(
                                leading: UserAvatar(imageUrl: uData['profileImageUrl'], name: uData['name'] ?? 'User', radius: 24),
                                title: Text(uData['name'] ?? 'User', style: TextStyle(fontWeight: FontWeight.w600, color: context.textHigh)),
                                subtitle: Text(uData['authorRole'] ?? uData['bio'] ?? 'Developer', style: TextStyle(color: context.textMed)),
                                onTap: _isLoading ? null : () => _startChat(uId, uData['name'], uData['profileImageUrl']),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class UserChatAvatar extends StatelessWidget {
  final String userId;
  final String name;
  final Map<String, dynamic> chatData;
  final bool showStatus;

  const UserChatAvatar({
    super.key,
    required this.userId,
    required this.name,
    required this.chatData,
    this.showStatus = false,
  });

  @override
  Widget build(BuildContext context) {
    final images = chatData['participantProfileImages'] as Map<String, dynamic>?;
    final url = images?[userId];

    return UserAvatar(
      imageUrl: url,
      name: name,
      radius: 26,
      showOnlineStatus: showStatus,
    );
  }
}
