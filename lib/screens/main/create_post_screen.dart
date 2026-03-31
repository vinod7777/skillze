import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:io' as io;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'custom_camera_screen.dart';
import 'location_picker_screen.dart';
import 'package:latlong2/latlong.dart';
import '../../theme/app_theme.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../utils/mention_helper.dart';
import '../../widgets/image_viewer_dialog.dart';
import '../../services/notification_service.dart';
import '../../widgets/clean_multiline_input.dart';
import '../../widgets/clean_text_field.dart';

class CreatePostScreen extends StatefulWidget {
  final DocumentSnapshot? postDoc;
  const CreatePostScreen({super.key, this.postDoc});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _postController = TextEditingController();
  final _skillSearchController = TextEditingController();
  final _roleSearchController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  final List<XFile> _selectedImages = [];
  bool _isPosting = false;
  final bool _isLoadingLocation = false;
  final String _selectedVisibility = 'Public';
  bool _shareToFollowingOnly = false;
  String _location = 'Add Location';
  double? _postLat;
  double? _postLng;
  final List<String> _selectedSkills = [];
  final List<String> _selectedRoles = [];

  final List<String> _suggestedSkills = [
    'Flutter', 'React Native', 'UI/UX', 'Python', 'Node.js',
    'Graphic Design', 'Web Development', 'Mobile Development',
    'Project Management', 'Branding', 'Copywriting'
  ];

  // ImgBB API Key â€” user should replace with their own
  static const String _imgbbApiKey = '9b144936080b6683b78410f3898f743d';

  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    _postController.addListener(_onPostChanged);
    _skillSearchController.addListener(() => setState(() {}));
    _roleSearchController.addListener(() => setState(() {}));

    if (widget.postDoc != null) {
      final data = widget.postDoc!.data() as Map<String, dynamic>;
      _postController.text = data['content'] ?? '';
      _location = data['location'] ?? 'Add Location';
      _postLat = data['latitude'] != null ? (data['latitude'] as num).toDouble() : null;
      _postLng = data['longitude'] != null ? (data['longitude'] as num).toDouble() : null;
      _selectedSkills.addAll(List<String>.from(data['skills'] ?? []));
      _selectedRoles.addAll(List<String>.from(data['roles'] ?? []));
      _shareToFollowingOnly = data['visibility'] == 'network';
      
      // Note: We don't populate _selectedImages with URLs directly since _selectedImages is List<XFile>.
      // For simplicity in this implementation, editing will allow updating text/tags but keep existing media if unchanged.
      // A more complex implementation would handle media replacement too.
    }
  }



  void _onPostChanged() {
    setState(() {}); // Original listener logic

    final text = _postController.text;
    final selection = _postController.selection;
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
      // Just fetch some general users if query is empty
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .limit(20)
          .get();

      if (mounted && (_currentMentionQuery == null || _currentMentionQuery!.isEmpty)) {
        setState(() {
          _mentionSuggestions = snapshot.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
        });
      }
      return;
    }

    // Give suggestions according to what the user types
    final queryLower = query.toLowerCase();
    
    // First query by username
    final usernameSnapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isGreaterThanOrEqualTo: queryLower)
        .where('username', isLessThan: '${queryLower}z')
        .limit(20)
        .get();

    if (mounted && _currentMentionQuery == query) {
      final results = usernameSnapshot.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
      
      // If we don't have enough results, maybe try name search or role search in some cases
      // For now, username is the primary mention handle.
      
      setState(() {
        _mentionSuggestions = results;
      });
    }
  }

  void _insertMention(String username) {
    if (_mentionStartIndex == -1) return;
    
    final text = _postController.text;
    final textBefore = text.substring(0, _mentionStartIndex);
    final textAfter = text.substring(_postController.selection.baseOffset);
    
    final newText = '$textBefore@$username $textAfter';
    
    setState(() {
      _postController.text = newText;
      _postController.selection = TextSelection.collapsed(offset: _mentionStartIndex + username.length + 2);
      _currentMentionQuery = null;
      _mentionSuggestions = [];
    });
  }

  @override
  void dispose() {
    _postController.dispose();
    _skillSearchController.dispose();
    _roleSearchController.dispose();
    super.dispose();
  }

  Future<void> _navigateLocationPicker() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLocation: (_postLat != null && _postLng != null)
              ? LatLng(_postLat!, _postLng!)
              : null,
        ),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      setState(() {
        _location = result['name'];
        _postLat = result['lat'];
        _postLng = result['lng'];
      });
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_selectedImages.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('You can add up to 5 images'),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ),
      );
      return;
    }

    try {
      if (source == ImageSource.gallery) {
        final List<XFile> pickedFiles = await _picker.pickMultiImage(
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 85,
        );

        if (pickedFiles.isNotEmpty) {
          setState(() {
            final remainingSpace = 5 - _selectedImages.length;
            final filesToAdd = pickedFiles.take(remainingSpace);
            _selectedImages.addAll(filesToAdd);
          });
        }
      } else {
        final XFile? pickedFile = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomCameraScreen()),
        );
        if (pickedFile != null) {
          setState(() {
            _selectedImages.add(pickedFile);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(
          content: Text('Error picking image: $e'),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ));
      }
    }
  }

  Future<String?> _uploadToImgBB(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      final response = await http.post(
        Uri.parse('https://api.imgbb.com/1/upload'),
        body: {'key': _imgbbApiKey, 'image': base64Image},
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        if (jsonResponse['success'] == true) {
          return jsonResponse['data']['url'];
        }
      }
      return null;
    } catch (e) {
      debugPrint('ImgBB upload error: $e');
      return null;
    }
  }

  Future<void> _handlePost() async {
    // Normalize content one final time before submission
    final textContent = CleanMultilineInput.normalize(_postController.text);
    
    if (textContent.isEmpty && _selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please write something or add an image'),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ),
      );
      return;
    }

    bool hasBadWords = ProfanityFilterService.hasProfanity(textContent) || 
                      _selectedSkills.any((s) => ProfanityFilterService.hasProfanity(s)) ||
                      _selectedRoles.any((r) => ProfanityFilterService.hasProfanity(r));

    if (hasBadWords) {
      showProfanityWarning(context);
      return;
    }

    setState(() => _isPosting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please log in to post'),
              backgroundColor: Colors.white,
              action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
            ),
          );
        }
        setState(() => _isPosting = false);
        return;
      }

      // Get user data from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? {};
      final authorName = userData['name'] ?? 'Unknown User';
      final authorRole = userData['bio'] ?? 'Developer';

      // Upload images if selected
      List<String> mediaUrls = [];
      if (_selectedImages.isNotEmpty) {
        for (var image in _selectedImages) {
          String? url = await _uploadToImgBB(image);
          if (url != null) {
            mediaUrls.add(url);
          }
        }

        if (mediaUrls.length < _selectedImages.length && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Some images failed to upload.'),
              backgroundColor: Colors.white,
              action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
            ),
          );
        }
      }

      // Create or Update post document in Firestore
      final Map<String, dynamic> postData = {
        'content': textContent,
        'visibility': _shareToFollowingOnly ? 'network' : _selectedVisibility.toLowerCase(),
        'skills': _selectedSkills,
        'roles': _selectedRoles,
        'location': _location,
        'latitude': _postLat,
        'longitude': _postLng,
        'timestamp': FieldValue.serverTimestamp(),
      };

      DocumentReference? newPostRef;
      if (widget.postDoc == null) {
        // NEW POST
        postData.addAll({
          'authorId': user.uid,
          'authorName': authorName,
          'authorRole': authorRole,
          'authorProfileImageUrl': userData['profileImageUrl'],
          'mediaUrls': mediaUrls,
          'mediaUrl': mediaUrls.isNotEmpty ? mediaUrls.first : '',
          'likesCount': 0,
          'commentsCount': 0,
        });
        newPostRef = await FirebaseFirestore.instance.collection('posts').add(postData);
      } else {
        // EDIT EXISTING
        postData['isEdited'] = true;
        debugPrint('Updating post ${widget.postDoc!.id} with isEdited=true');
        if (mediaUrls.isNotEmpty) {
          postData['mediaUrls'] = mediaUrls;
          postData['mediaUrl'] = mediaUrls.first;
        }
        await widget.postDoc!.reference.update(postData);
      }

      // --- NEW: Notify Followers ---
      if (widget.postDoc == null) {
        final currentUserId = user.uid;
        final currentUserDoc = await FirebaseFirestore.instance.collection('users').doc(currentUserId).get();
        final followersList = List<String>.from(currentUserDoc.data()?['followersList'] ?? []);
        final myName = currentUserDoc.data()?['name'] ?? 'Someone';
        final myPhoto = currentUserDoc.data()?['profileImageUrl'];
        
        final postContent = postData['content']?.toString() ?? '';
        final truncatedContent = postContent.length > 30 
            ? '${postContent.substring(0, 30)}...' 
            : postContent;

        // Notify up to first 20 followers in parallel
        final notificationTasks = followersList.take(20).where((id) => id != currentUserId).map((followerId) {
          return NotificationService.sendNotification(
            targetUserId: followerId,
            type: 'new_post',
            message: 'published a new post: $truncatedContent',
            postId: newPostRef?.id,
            actorName: myName, // Pass cached name
            actorPhoto: myPhoto, // Pass cached photo
          );
        });
        
        // Fire and forget, or wait if needed. We'll wait to ensure stability but in parallel it's fast.
        Future.wait(notificationTasks);
      }

      // Process mentions
      if (textContent.isNotEmpty) {
        await MentionHelper.processMentions(
          text: textContent,
          currentUserId: user.uid,
          currentUserName: authorName,
          notificationType: 'mention_post',
          notificationMessage: 'mentioned you in a post',
          postId: newPostRef?.id ?? widget.postDoc!.id,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.postDoc == null ? 'Post published successfully! 🎉' : 'Post updated successfully! 🎉'),
            backgroundColor: Colors.white,
            action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
          ),
        );
        
        // Land on home screen and refresh
        Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error posting: $e'),
          backgroundColor: Colors.white,
          action: SnackBarAction(label: 'Close', textColor: Colors.black, onPressed: () {}),
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.postDoc == null ? 'Create Post' : 'Edit Post',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0, top: 8, bottom: 8),
            child: ElevatedButton(
              onPressed: _isPosting ? null : _handlePost,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.primary,
                foregroundColor: context.onPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isPosting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(color: context.onPrimary, strokeWidth: 2),
                    )
                  : const Text('Post', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: context.border.withOpacity(0.5), height: 1),
        ),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Media Upload Area
            GestureDetector(
              onTap: () => _pickImage(ImageSource.gallery),
              child: CustomPaint(
                painter: DashedBorderPainter(color: context.textLow.withOpacity(0.3)),
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: context.surfaceLightColor,
                  ),
                  child: _selectedImages.isEmpty
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 44,
                              color: context.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Add photos',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: context.textHigh,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Share your latest work with the world',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textLow,
                              ),
                            ),
                          ],
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CarouselSlider(
                                options: CarouselOptions(
                                  height: 180,
                                  viewportFraction: 1.0,
                                  enableInfiniteScroll: false,
                                  onPageChanged: (index, reason) {
                                    // Could add page indicator here if needed
                                  },
                                ),
                                items: _selectedImages.map((image) {
                                  return Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          ImageViewerDialog.show(
                                            context, 
                                            null, 
                                            'Preview',
                                            filePath: image.path,
                                            isCircular: false,
                                          );
                                        },
                                        child: kIsWeb
                                            ? Image.network(image.path, fit: BoxFit.cover)
                                            : Image.file(io.File(image.path), fit: BoxFit.cover),
                                      ),
                                      Container(color: Colors.black12),
                                      Positioned(
                                        top: 12,
                                        right: 12,
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _selectedImages.remove(image);
                                            });
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(6),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.5),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.close_rounded,
                                                size: 16, color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                              ),
                              if (_selectedImages.length > 1)
                                Positioned(
                                  bottom: 12,
                                  left: 0,
                                  right: 0,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.6),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'Swipe to see all ${_selectedImages.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Content Input - Using the new premium CleanMultilineInput
            CleanMultilineInput(
              controller: _postController,
              hintText: 'What are you sharing today? (use @ to mention)',
              onChanged: (val) {
                _onPostChanged(); // Maintain the original mention searching logic
              },
            ),
            
            if (_mentionSuggestions.isNotEmpty && _currentMentionQuery != null) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: context.surfaceLightColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.border.withOpacity(0.2)),
                  boxShadow: [
                    BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2))
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
                    
                    final role = user['role'] ?? user['userType'] ?? user['bio'] ?? 'Member';
                    
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty ? const Icon(Icons.person, size: 14) : null,
                      ),
                      title: Text(username, style: TextStyle(color: context.textHigh, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('$name • $role', style: TextStyle(color: context.textMed, fontSize: 11)),
                      onTap: () => _insertMention(username),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            const SizedBox(height: 40),

            // TAG SKILLS
            Text(
              'TAG SKILLS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.textMed,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            CleanTextField(
              controller: _skillSearchController,
              hintText: 'Search skills (e.g. UI Design, Python...)',
              prefixIcon: Icons.search_rounded,
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedSkills.map((skill) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.secondary, context.secondary.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: context.secondary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        skill,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _selectedSkills.remove(skill)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            if (_skillSearchController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    // If current search not in list, allow adding it
                    if (!_suggestedSkills.any((s) => s.toLowerCase() == _skillSearchController.text.toLowerCase()) &&
                        !_selectedSkills.contains(_skillSearchController.text))
                      ListTile(
                        leading: Icon(Icons.add_circle_outline, color: context.primary),
                        title: Text('Add "${_skillSearchController.text}"', style: TextStyle(color: context.textHigh)),
                        onTap: () {
                          setState(() {
                            _selectedSkills.add(_skillSearchController.text);
                            _skillSearchController.clear();
                          });
                        },
                      ),
                    ..._suggestedSkills
                        .where((s) => s.toLowerCase().contains(_skillSearchController.text.toLowerCase().trim().replaceAll('_', ' ')) && !_selectedSkills.contains(s))
                        .map((skill) => ListTile(
                              title: Text(skill, style: TextStyle(color: context.textHigh)),
                              onTap: () {
                                setState(() {
                                  _selectedSkills.add(skill);
                                  _skillSearchController.clear();
                                });
                              },
                            )),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 40),

            // TAG ROLES
            Text(
              'TAG ROLES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: context.textMed,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            CleanTextField(
              controller: _roleSearchController,
              hintText: 'Type your role (e.g. Lead Dev, Designer...)',
              prefixIcon: Icons.work_outline_rounded,
              onChanged: (val) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                'Frontend', 'Backend', 'Fullstack', 'UI/UX', 'Mobile', 'DevOps', 'AI/ML'
              ].map((role) {
                final isSelected = _selectedRoles.contains(role);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedRoles.remove(role);
                      } else {
                        _selectedRoles.add(role);
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: isSelected 
                          ? LinearGradient(colors: [context.secondary, context.secondary.withOpacity(0.8)])
                          : null,
                      color: isSelected ? null : context.surfaceLightColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? context.secondary : context.border,
                        width: 1.5,
                      ),
                      boxShadow: isSelected ? [
                        BoxShadow(
                          color: context.secondary.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        )
                      ] : null,
                    ),
                    child: Text(
                      role,
                      style: TextStyle(
                        color: isSelected ? Colors.white : context.textMed,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            if (_roleSearchController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 100),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.border),
                ),
                child: ListTile(
                  leading: Icon(Icons.add_circle_outline, color: context.primary),
                  title: Text('Add "${_roleSearchController.text}"', style: TextStyle(color: context.textHigh)),
                  onTap: () {
                    setState(() {
                      _selectedRoles.add(_roleSearchController.text);
                      _roleSearchController.clear();
                    });
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedRoles
                  .where((r) => !['Frontend', 'Backend', 'Fullstack', 'UI/UX', 'Mobile', 'DevOps', 'AI/ML'].contains(r))
                  .map((role) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [context.secondary, context.secondary.withOpacity(0.8)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: context.secondary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        role,
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _selectedRoles.remove(role)),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),

            // Visibility Toggle
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.border.withOpacity(0.6)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share to following only',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textHigh),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Only your followers can see this post',
                          style: TextStyle(fontSize: 13, color: context.textMed),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _shareToFollowingOnly,
                    onChanged: (val) => setState(() => _shareToFollowingOnly = val),
                    activeThumbColor: context.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Location
            GestureDetector(
              onTap: _isLoadingLocation ? null : _navigateLocationPicker,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: context.border.withOpacity(0.6)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Location',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.textHigh),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _location,
                            style: TextStyle(
                              fontSize: 13,
                              color: _location == 'Add Location' ? context.textLow : context.primary,
                              fontWeight: _location == 'Add Location' ? FontWeight.normal : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoadingLocation)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      Icon(Icons.my_location_rounded, color: context.primary, size: 20),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

}

class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double gap;

  DashedBorderPainter({
    this.color = const Color(0xFFA1A1AA),
    this.strokeWidth = 1.0,
    this.gap = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final ui.Path path = ui.Path();
    path.addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(20),
      ));

    final List<double> dashArray = [gap, gap];
    double distance = 0.0;
    for (final ui.PathMetric measure in path.computeMetrics()) {
      while (distance < measure.length) {
        final double length = dashArray[0];
        canvas.drawPath(
          measure.extractPath(distance, distance + length),
          paint,
        );
        distance += length + dashArray[1];
      }
      distance = 0.0;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
