import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../widgets/user_avatar.dart';
import 'user_profile_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/avatar_helper.dart';

class ChatInfoScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String chatId;

  const ChatInfoScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.chatId,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isBlocked = false;
  bool _isRestricted = false;
  bool _isMuted = false;
  bool _isLoadingUser = true;
  Map<String, dynamic>? _userData;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkUserStatus();
    _fetchFullUserData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkUserStatus() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (doc.exists) {
      final data = doc.data();
      final blockedUsers = List<String>.from(data?['blockedUsers'] ?? []);
      final restrictedUsers = List<String>.from(data?['restrictedUsers'] ?? []);
      final mutedUsers = List<String>.from(data?['mutedUsers'] ?? []);
      if (mounted) {
        setState(() {
          _isBlocked = blockedUsers.contains(widget.userId);
          _isRestricted = restrictedUsers.contains(widget.userId);
          _isMuted = mutedUsers.contains(widget.userId);
        });
      }
    }
  }

  Future<void> _fetchFullUserData() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      
      if (userDoc.exists) {
        _userData = userDoc.data();
      }

      if (mounted) setState(() => _isLoadingUser = false);
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  Future<void> _toggleStatus(String field, bool currentValue, String actionName) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid);

    setState(() {
      _isLoadingUser = true;
    });

    try {
      if (currentValue) {
        await userRef.update({
          field: FieldValue.arrayRemove([widget.userId]),
        });
      } else {
        await userRef.update({
          field: FieldValue.arrayUnion([widget.userId]),
        });
      }

      await _checkUserStatus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${currentValue ? 'un' : ''}$actionName.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update $actionName status.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingUser = false;
        });
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Contact Info',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Profile Header Section
                Center(
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.textHigh.withValues(alpha: 0.2),
                            width: 2,
                          ),
                        ),
                        child: UserAvatar(
                          imageUrl: AvatarHelper.getAvatarUrl(_userData),
                          name: widget.userName,
                          radius: 56,
                          gradient: LinearGradient(
                            colors: [context.textHigh.withValues(alpha: 0.8), context.textHigh],
                          ),
                          fontSize: 48,
                        ),
                      ),
                      if (!_isLoadingUser && _userData?['isVerified'] == true)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.textHigh,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.bg, width: 2),
                          ),
                          child: Icon(Icons.check, color: context.bg, size: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(userId: widget.userId),
                      ),
                    );
                  },
                  child: Text(
                    widget.userName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: context.textHigh,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                if (!_isLoadingUser && _userData?['username'] != null)
                  Text(
                    '@${_userData!['username']}',
                    style: TextStyle(
                      color: context.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 16),
                
                // Bio
                if (!_isLoadingUser && _userData?['bio'] != null && (_userData!['bio'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      _userData!['bio'],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.textMed,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                const SizedBox(height: 24),

                // Quick Action Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildQuickAction(
                        icon: Icons.person_outline_rounded,
                        label: 'Profile',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(userId: widget.userId),
                            ),
                          );
                        },
                      ),
                      _buildQuickAction(
                        icon: _isMuted ? Icons.notifications_off_rounded : Icons.notifications_none_rounded,
                        label: _isMuted ? 'Unmute' : 'Mute',
                        color: _isMuted ? context.primary : null,
                        onTap: () => _toggleStatus('mutedUsers', _isMuted, 'muted'),
                      ),
                      _buildQuickAction(
                        icon: Icons.search_rounded,
                        label: 'Search',
                        onTap: () {
                          // Search functionality will be handled by parent
                          Navigator.pop(context, 'triggerSearch');
                        },
                      ),
                      _buildQuickAction(
                        icon: _isBlocked ? Icons.security_rounded : Icons.block_flipped,
                        label: _isBlocked ? 'Unblock' : 'Block',
                        color: _isBlocked ? Colors.white : Colors.white,
                        onTap: () => _toggleStatus('blockedUsers', _isBlocked, 'blocked'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),


                const SizedBox(height: 32),

                // Settings List Section
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: context.surfaceLightColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.border.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    children: [
                      _buildSettingTile(
                        icon: Icons.do_not_disturb_on_outlined,
                        title: 'Restrict User',
                        subtitle: 'Limit interactions without blocking',
                        trailing: Switch.adaptive(
                          value: _isRestricted,
                          activeColor: context.primary,
                          onChanged: (_) => _toggleStatus('restrictedUsers', _isRestricted, 'restricted'),
                        ),
                      ),
                      Divider(height: 1, color: context.border.withValues(alpha: 0.1), indent: 56),
                      _buildSettingTile(
                        icon: _isBlocked ? Icons.security_rounded : Icons.block_flipped,
                        title: '${_isBlocked ? 'Unblock' : 'Block'} ${_userData?['name'] ?? widget.userName}',
                        titleColor: context.textHigh,
                        subtitle: _isBlocked
                            ? 'They will be able to message you again'
                            : 'They won\'t be able to message you',
                        onTap: () => _toggleStatus('blockedUsers', _isBlocked, 'blocked'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: context.primary,
                indicatorWeight: 3,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: context.textHigh,
                unselectedLabelColor: context.textLow,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Media'),
                  Tab(text: 'Links'),
                ],
              ),
              context.bg,
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _SharedMediaGrid(chatId: widget.chatId),
                _SharedLinksList(chatId: widget.chatId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: (color ?? context.textHigh).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color ?? context.textHigh, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: context.textMed,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (titleColor ?? context.textMed).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: titleColor ?? context.textMed, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? context.textHigh,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: context.textLow, fontSize: 12),
            )
          : null,
      trailing: trailing,
    );
  }
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  _SliverAppBarDelegate(this._tabBar, this.backgroundColor);

  final TabBar _tabBar;
  final Color backgroundColor;

  @override
  double get minExtent => _tabBar.preferredSize.height;
  @override
  double get maxExtent => _tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: _tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

class _SharedMediaGrid extends StatelessWidget {
  final String chatId;
  const _SharedMediaGrid({required this.chatId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .where('imageUrl', isGreaterThan: '')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(context, Icons.photo_library_outlined, 'No media shared yet');
        }
        final docs = snapshot.data!.docs;
        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final imageUrl = data['imageUrl'] as String?;
            if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();

            return GestureDetector(
              onTap: () => _openFullscreen(context, imageUrl),
              child: Hero(
                tag: imageUrl,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.surfaceLightColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.border.withValues(alpha: 0.5)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: context.surfaceLightColor,
                        child: Icon(Icons.broken_image_rounded, color: context.textLow),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openFullscreen(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Center(
              child: Hero(
                tag: imageUrl,
                child: InteractiveViewer(
                  child: Image.network(imageUrl, fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.5),
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, IconData icon, String message) {
    return Center(
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Icon(icon, size: 48, color: context.textLow.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            message, 
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textMed, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _SharedLinksList extends StatelessWidget {
  final String chatId;
  const _SharedLinksList({required this.chatId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<String> links = [];
        if (snapshot.hasData) {
          final urlRegex = RegExp(r'(http|https)://[\w-]+(\.[\w-]+)+([\w.,@?^=%&:/~+#-]*[\w@?^=%&/~+#-])?');
          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final text = data['text'] as String?;
            if (text != null) {
              final matches = urlRegex.allMatches(text);
              for (var match in matches) {
                final link = match.group(0);
                if (link != null && !links.contains(link)) {
                  links.add(link);
                }
              }
            }
          }
        }

        if (links.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off_rounded, size: 48, color: context.textLow.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text('No links shared yet', style: TextStyle(color: context.textMed, fontSize: 14)),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: links.length,
          itemBuilder: (context, index) {
            return LinkPreviewCard(url: links[index]);
          },
        );
      },
    );
  }
}

class LinkPreviewCard extends StatelessWidget {
  final String url;
  const LinkPreviewCard({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceLightColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border.withValues(alpha: 0.5)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _launchUrl(url),
          onLongPress: () => _showLinkOptions(context, url),
          child: AnyLinkPreview(
            link: url,
            displayDirection: UIDirection.uiDirectionHorizontal,
            bodyMaxLines: 2,
            placeholderWidget: _buildPlaceholder(context),
            errorWidget: _buildError(context),
            backgroundColor: Colors.transparent,
            titleStyle: TextStyle(
              color: context.textHigh,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            bodyStyle: TextStyle(
              color: context.textMed,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Container(
      height: 100,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: context.border.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.link_rounded, color: context.textLow),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(width: 120, height: 12, decoration: BoxDecoration(color: context.border.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 8),
                Container(width: 180, height: 10, decoration: BoxDecoration(color: context.border.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.link_rounded, color: context.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              url,
              style: TextStyle(color: context.textHigh, fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Icon(Icons.open_in_new_rounded, size: 14, color: context.textLow),
        ],
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showLinkOptions(BuildContext context, String url) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('Copy Link'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied to clipboard')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Share Link'),
            onTap: () {
              Share.share(url);
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
