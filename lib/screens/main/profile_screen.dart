import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'skills_screen.dart';
import 'user_list_screen.dart';
import 'settings_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/user_avatar.dart';
import '../../widgets/post_card.dart';
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
  late Stream<QuerySnapshot> _postsStream;

  @override
  void initState() {
    super.initState();
    _initStream();
    _fetchProfile();
  }

  void _initStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _postsStream = FirebaseFirestore.instance
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        _userData = doc.data();
        _nameController.text = _userData?['name'] ?? '';
        _bioController.text = _userData?['bio'] ?? '';

        _followersCount = (_userData?['followersList'] as List?)?.length ?? 0;
        _followingCount = (_userData?['followingList'] as List?)?.length ?? 0;
      }

      final postsSnapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('authorId', isEqualTo: user.uid)
          .get();
      _postsCount = postsSnapshot.docs.length;
    } catch (e) {
      debugPrint("Error fetching profile: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }


  Future<void> _pickProfileImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );

      if (pickedFile != null) {
        setState(() => _isUploading = true);
        final bytes = await pickedFile.readAsBytes();
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
                _fetchProfile();
              }
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
    final bio = _userData?['bio'] ?? '';

    return Scaffold(
      backgroundColor: context.bg,
      body: DefaultTabController(
        length: 2,
        child: NestedScrollView(
          physics: const BouncingScrollPhysics(),
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
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
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    // Avatar
                    Center(
                      child: GestureDetector(
                        onTap: _isUploading ? null : _pickProfileImage,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              width: 110,
                              height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.surfaceColor,
                                border: Border.all(color: context.primary.withValues(alpha: 0.1), width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: context.primary.withValues(alpha: 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(3),
                              child: UserAvatar(
                                imageUrl: _userData?['profileImageUrl'] ?? 
                                          _userData?['authorProfileImageUrl'] ?? 
                                          _userData?['photoUrl'] ?? 
                                          _userData?['authorAvatar'] ?? 
                                          FirebaseAuth.instance.currentUser?.photoURL,
                                name: name,
                                radius: 52,
                                fontSize: 44,
                              ),
                            ),
                            if (_isUploading)
                              Positioned.fill(
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.black26,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Center(
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: context.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: context.bg, width: 2),
                              ),
                              child: const Icon(Icons.add_a_photo_outlined, color: Colors.white, size: 14),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      name,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: context.textHigh),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _userData?['status'] ?? 'Product Designer',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          bio,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: context.textMed, height: 1.4),
                        ),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Stats in a sleeker row
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: context.border),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildStatItem('$_postsCount', 'Posts'),
                            _buildStatDivider(),
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
                            _buildStatDivider(),
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
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),

              // Sticky TabBar
              SliverPersistentHeader(
                pinned: true,
                delegate: _StickyTabBarDelegate(
                  TabBar(
                    indicator: UnderlineTabIndicator(
                      borderSide: BorderSide(width: 3.5, color: context.primary),
                      insets: const EdgeInsets.symmetric(horizontal: 60),
                    ),
                    labelColor: context.primary,
                    unselectedLabelColor: context.textLow,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    dividerColor: Colors.transparent,
                    tabs: const [Tab(text: 'Posts'), Tab(text: 'Skills')],
                  ),
                ),
              ),
            ];
          },
          body: TabBarView(
            physics: const BouncingScrollPhysics(),
            children: [
              _buildPostsGrid(),
              _buildSkillsTab(),
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
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: context.textHigh,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: context.textLow,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(width: 1, height: 24, color: context.border);
  }

  Widget _buildPostsGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: _postsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(child: Text('No posts yet', style: TextStyle(color: context.textLow)));
        }
        final posts = snapshot.data!.docs;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: posts.length,
          itemBuilder: (context, index) {
            final doc = posts[index];
            final data = doc.data() as Map<String, dynamic>;
            final mediaUrl = data['mediaUrl'] as String?;
            return GestureDetector(
              onTap: () => _openPostDetail(doc),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.zero,
                  image: (mediaUrl != null && mediaUrl.isNotEmpty) 
                      ? DecorationImage(image: NetworkImage(mediaUrl), fit: BoxFit.cover) 
                      : null,
                  color: context.surfaceLightColor,
                ),
                child: mediaUrl == null
                    ? Center(child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(data['content'] ?? '', 
                        maxLines: 2, 
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textHigh)),
                      ))
                    : null,
              ),
            );
          },
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
                          Navigator.pop(context);
                        },
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

  Widget _buildSkillsTab() {
    final List<dynamic> skillsData = _userData?['skills_with_levels'] ?? [];
    List<Map<String, dynamic>> skillsList = [];

    if (skillsData.isNotEmpty) {
      skillsList = List<Map<String, dynamic>>.from(skillsData);
    } else {
      final List<dynamic> legacySkills = _userData?['skills'] ?? [];
      skillsList = legacySkills.map((s) => {'name': s.toString(), 'level': 'Intermediate'}).toList();
    }

    if (skillsList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lightbulb_outline_rounded, size: 48, color: context.textLow),
            const SizedBox(height: 16),
            Text(
              'No skills added yet',
              style: TextStyle(color: context.textMed, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SkillsScreen()))
                    .then((_) => _fetchProfile());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Add Skills', style: TextStyle(color: context.onPrimary)),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
      physics: const BouncingScrollPhysics(),
      itemCount: skillsList.length + 1,
      itemBuilder: (context, index) {
        if (index == skillsList.length) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: ElevatedButton(
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
            ),
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
                        side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
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
