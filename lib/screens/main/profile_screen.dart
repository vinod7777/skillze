import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'skills_screen.dart';
import 'user_list_screen.dart';
import 'settings_screen.dart';
import 'edit_personal_details_screen.dart';
import 'main_navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/image_viewer_dialog.dart';
import '../../widgets/post_card.dart';
import '../../widgets/modern_image_editor.dart';
import 'dart:typed_data';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  int _postsCount = 0;
  int _followersCount = 0;
  int _followingCount = 0;
  bool _isUploading = false;
  final ImagePicker _picker = ImagePicker();
  static const String _imgbbApiKey = '9b144936080b6683b78410f3898f743d';

  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  StreamSubscription? _userSubscription;
  late Stream<QuerySnapshot> _postsStream;
  int _selectedTab = 0; // 0 for Posts, 1 for Skills

  @override
  void initState() {
    super.initState();
    _initStream();
    _setupUserListener();
  }

  void _initStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  void _setupUserListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _userSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) async {
      if (doc.exists && mounted) {
        final data = doc.data();
        
        // Fetch posts count separately as it's a different collection
        final postsSnapshot = await FirebaseFirestore.instance
            .collection('posts')
            .where('authorId', isEqualTo: user.uid)
            .get();

        setState(() {
          _userData = data;
          _nameController.text = _userData?['name'] ?? '';
          _bioController.text = _userData?['bio'] ?? '';
          _followersCount = (_userData?['followersList'] as List?)?.length ?? 0;
          _followingCount = (_userData?['followingList'] as List?)?.length ?? 0;
          _postsCount = postsSnapshot.docs.length;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    // This is now handled by _setupUserListener
    // Keeping the method signature if needed for manual refresh, 
    // but the listener is more efficient.
  }


  void _showProfilePhotoOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: context.textHigh,
              ),
            ),
            const SizedBox(height: 24),
            _buildOptionItem(
              icon: Icons.photo_library_outlined,
              title: 'Choose from Gallery',
              onTap: () {
                Navigator.pop(context);
                _pickAndEditImage(ImageSource.gallery);
              },
            ),
            _buildOptionItem(
              icon: Icons.camera_alt_outlined,
              title: 'Take Photo',
              onTap: () {
                Navigator.pop(context);
                _pickAndEditImage(ImageSource.camera);
              },
            ),
            if (_userData?['profileImageUrl'] != null && _userData?['profileImageUrl'] != '')
              _buildOptionItem(
                icon: Icons.delete_outline_rounded,
                title: 'Remove Photo',
                color: Colors.redAccent,
                onTap: () async {
                  Navigator.pop(context);
                  await _removeProfilePhoto();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? context.textMed),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? context.textHigh,
          fontWeight: FontWeight.w500,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 32),
    );
  }

  Future<void> _pickAndEditImage(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(source: source);
      if (file == null) return;

      ModernImageEditor.open(
        context,
        imagePath: file.path,
        mode: EditorMode.profile,
        onComplete: (Uint8List croppedBytes) async {
          await _uploadProfilePhoto(croppedBytes);
        },
      );
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> _uploadProfilePhoto(Uint8List bytes) async {
    setState(() => _isUploading = true);
    try {
      final base64Image = base64Encode(bytes);
      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {'key': _imgbbApiKey, 'image': base64Image},
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true) {
          String url = jsonResponse['data']['url'];
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .update({'profileImageUrl': url});
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile photo updated!')),
              );
            }
          }
        }
      } else {
        throw Exception('Failed to upload to ImgBB');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _removeProfilePhoto() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'profileImageUrl': ''});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: Center(child: CircularProgressIndicator(color: context.primary)),
      );
    }

    final name = _userData?['name'] ?? 'User';
    final username = _userData?['username'] ?? '';
    final bio = _userData?['bio'] ?? '';

    return Scaffold(
      backgroundColor: context.bg,
      body: DefaultTabController(
        length: 2,
        child: RefreshIndicator(
          onRefresh: _fetchProfile,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            // Custom AppBar
            SliverAppBar(
              backgroundColor: context.bg,
              elevation: 0,
              pinned: true,
              centerTitle: true,
              title: Text(
                'Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: context.textHigh,
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: context.textHigh),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const SettingsScreen()),
                    );
                  },
                ),
                const SizedBox(width: 8),
              ],
            ),

            // Profile Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // Avatar and Stats Row
                    Row(
                      children: [
                        // Avatar
                        GestureDetector(
                          onTap: () {
                            if (_isUploading) return;
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.touch_app_rounded, color: context.primary, size: 20),
                                      const SizedBox(width: 12),
                                      const Text(
                                        'Hold to view full profile',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                duration: const Duration(seconds: 2),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
                              ),
                            );
                            _showProfilePhotoOptions();
                          },
                          onLongPress: () {
                            final url = _userData?['profileImageUrl'] ?? 
                                        FirebaseAuth.instance.currentUser?.photoURL;
                            ImageViewerDialog.show(context, url, name);
                          },
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: context.primary.withOpacity(0.2),
                                    width: 2,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: UserAvatar(
                                    imageUrl: _userData?['profileImageUrl'] ?? 
                                              FirebaseAuth.instance.currentUser?.photoURL,
                                    name: name,
                                    radius: 42,
                                    fontSize: 32,
                                  ),
                                ),
                              ),
                              if (_isUploading)
                                Positioned.fill(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black45,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(
                                      child: SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (!_isUploading)
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: context.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: context.bg, width: 2),
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 12),
                                ),
                            ],
                          ),
                        ),
                        // Stats
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatItem('$_postsCount', 'Posts'),
                              _buildStatItem('$_followersCount', 'Followers', onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserListScreen(
                                      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                                      title: 'Followers',
                                      type: UserListType.followers,
                                    ),
                                  ),
                                );
                              }),
                              _buildStatItem('$_followingCount', 'Following', onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => UserListScreen(
                                      userId: FirebaseAuth.instance.currentUser?.uid ?? '',
                                      title: 'Following',
                                      type: UserListType.following,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // User Info
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: context.textHigh,
                      ),
                    ),
                    if (username.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '@$username',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    if (_userData?['status'] != null && _userData!['status'].toString().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _userData!['status'],
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textMed.withOpacity(0.8),
                          ),
                        ),
                      ),
                    if (bio.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          bio,
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textHigh,
                            height: 1.3,
                          ),
                        ),
                      ),
                    
                    const SizedBox(height: 20),
                    
                    // Action Buttons Row (Instagram Style)
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            'Edit Profile',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const EditPersonalDetailsScreen()),
                              ).then((_) => _fetchProfile());
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildActionButton(
                            'Manage Skills',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const SkillsScreen()),
                              ).then((_) => _fetchProfile());
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),

            // Sticky TabBar
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyTabBarDelegate(
                TabBar(
                  onTap: (index) => setState(() => _selectedTab = index),
                  indicator: UnderlineTabIndicator(
                    borderSide: BorderSide(width: 3.5, color: context.primary),
                    insets: const EdgeInsets.symmetric(horizontal: 60),
                  ),
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(icon: Icon(Icons.grid_on_sharp, size: 22)),
                    Tab(icon: Icon(Icons.psychology_alt_outlined, size: 24)),
                  ],
                ),
              ),
            ),

            // Tab Content
            if (_selectedTab == 0)
              _buildPostsSliverGrid()
            else
              _buildSkillsSliverTab(),

            // Bottom space
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildStatItem(String count, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textHigh,
              letterSpacing: -0.2,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.textHigh,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, {required VoidCallback onTap}) {
    return SizedBox(
      height: 32,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: context.isDark ? context.surfaceLightColor : Colors.grey[200],
          foregroundColor: context.textHigh,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      ),
    );
  }



  Widget _buildPostsSliverGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return SliverToBoxAdapter(
            child: Container(
              height: 200,
              alignment: Alignment.center,
              child: Text('No posts yet', style: TextStyle(color: context.textLow)),
            ),
          );
        }
        final posts = snapshot.data!.docs;
        return SliverPadding(
          padding: const EdgeInsets.all(1),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
              childAspectRatio: 1.0,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final doc = posts[index];
                final data = doc.data() as Map<String, dynamic>;
                final mediaUrl = data['mediaUrl'] as String?;
                return GestureDetector(
                  onTap: () => _openPostDetail(doc),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.surfaceLightColor,
                      image: (mediaUrl != null && mediaUrl.isNotEmpty) 
                          ? DecorationImage(image: NetworkImage(mediaUrl), fit: BoxFit.cover) 
                          : null,
                    ),
                    child: (mediaUrl == null || mediaUrl.isEmpty)
                        ? Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  context.surfaceLightColor,
                                  context.surfaceLightColor.withOpacity(0.8),
                                  context.primary.withOpacity(0.15),
                                ],
                              ),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  child: Icon(
                                    Icons.format_quote_rounded,
                                    color: context.primary.withOpacity(0.2),
                                    size: 20,
                                  ),
                                ),
                                Center(
                                  child: Text(
                                    data['content'] ?? '',
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: context.textHigh,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : null,
                  ),
                );
              },
              childCount: posts.length,
            ),
          ),
        );
      },
    );
  }

  void _openPostDetail(DocumentSnapshot postDoc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: PostCard(
                        doc: postDoc,
                        onDeleted: () {
                          // Crucially use the context from outside the PostCard 
                          // ensuring we pop the actual modal we're in
                          Navigator.of(context, rootNavigator: true).pop();
                          
                          // Switch to Home screen
                          final navState = context.findAncestorStateOfType<MainNavigationState>();
                          if (navState != null) {
                            navState.setIndex(0);
                          }
                        },
                        isClickable: false,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSkillsSliverTab() {
    final List<dynamic> skillsData = _userData?['skills_with_levels'] ?? [];
    List<Map<String, dynamic>> skillsList = [];

    if (skillsData.isNotEmpty) {
      skillsList = List<Map<String, dynamic>>.from(skillsData);
    } else {
      final List<dynamic> legacySkills = _userData?['skills'] ?? [];
      skillsList = legacySkills.map((s) => {'name': s.toString(), 'level': 'Intermediate'}).toList();
    }

    if (skillsList.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 0),
          child: Column(
            children: [
              Icon(Icons.lightbulb_outline_rounded, size: 48, color: context.textLow),
              const SizedBox(height: 16),
              Text(
                'No skills added yet',
                style: TextStyle(color: context.textMed, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              _buildManageSkillsButton(),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index == skillsList.length) {
              return Padding(
                padding: const EdgeInsets.only(top: 24),
                child: _buildManageSkillsButton(),
              );
            }

            final skill = skillsList[index];
            final String name = skill['name'] ?? 'Unknown';
            final String level = skill['level'] ?? 'Intermediate';
            
            IconData icon = Icons.code_rounded;
            if (name.toLowerCase().contains('photo')) icon = Icons.camera_alt_rounded;
            if (name.toLowerCase().contains('design')) icon = Icons.brush_rounded;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: () => _showEditSkillDialog(skill),
                child: _buildSkillItemFigma(name, level, icon),
              ),
            );
          },
          childCount: skillsList.length + 1,
        ),
      ),
    );
  }

  Widget _buildManageSkillsButton() {
    return ElevatedButton(
      onPressed: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SkillsScreen()))
            .then((_) => _fetchProfile());
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: context.primary,
        padding: const EdgeInsets.symmetric(vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 0,
      ),
      child: Text(
        'Manage Skills',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.onPrimary),
      ),
    );
  }

  Widget _buildSkillItemFigma(String title, String level, IconData leadingIcon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.surfaceLightColor, 
              borderRadius: BorderRadius.circular(14)
            ),
            child: Icon(leadingIcon, size: 20, color: context.textHigh),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textHigh)),
                Text(level, style: TextStyle(fontSize: 12, color: context.textLow)),
              ],
            ),
          ),
          Icon(Icons.edit_outlined, size: 18, color: context.textLow),
        ],
      ),
    );
  }

  void _showEditSkillDialog(Map<String, dynamic> skill) {
    String selectedLevel = skill['level'] ?? 'Intermediate';
    String currentName = skill['name'] ?? 'Unknown';
    final String originalName = skill['name'] ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Edit Skill',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: context.textHigh),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: context.textLow),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Skill Name',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textLow, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: TextEditingController(text: currentName),
                onChanged: (v) => currentName = v,
                style: TextStyle(color: context.textHigh, fontSize: 16, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.surfaceLightColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Skill Level',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textLow, letterSpacing: 1.2),
              ),
              const SizedBox(height: 12),
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: context.surfaceLightColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: ['Beginner', 'Intermediate', 'Expert'].map((level) {
                    final isSelected = selectedLevel == level;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => selectedLevel = level),
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected ? context.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            level,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected ? context.onPrimary : context.textLow,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                   Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _updateSkill(originalName, originalName, null); // Remove skill
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: Colors.red.withOpacity(0.5)),
                      ),
                      child: const Text('Remove', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _updateSkill(originalName, currentName, selectedLevel);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: Text('Update Level', style: TextStyle(color: context.onPrimary, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateSkill(String originalName, String newName, String? newLevel) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isLoading = true);

    try {
      if (newLevel != null && ProfanityFilterService.hasProfanity(newName)) {
        showProfanityWarning(context);
        setState(() => _isLoading = false);
        return;
      }
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await userRef.get();
      if (!doc.exists) return;

      final List<dynamic> currentSkills = List.from(doc.data()?['skills_with_levels'] ?? []);
      
      if (newLevel == null) {
        // Remove skill
        currentSkills.removeWhere((s) => s['name'] == originalName);
      } else {
        // Update name and level
        final index = currentSkills.indexWhere((s) => s['name'] == originalName);
        if (index != -1) {
          currentSkills[index]['name'] = newName;
          currentSkills[index]['level'] = newLevel;
        }
      }

      await userRef.update({
        'skills_with_levels': currentSkills,
        'skills': currentSkills.map((s) => s['name']).toList(),
      });

      await _fetchProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(newLevel == null ? 'Skill removed' : 'Skill level updated')),
        );
      }
    } catch (e) {
      debugPrint('Error updating skill: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _StickyTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: context.bg,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
