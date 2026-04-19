import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../utils/mention_helper.dart';
import '../../widgets/modern_image_editor.dart';
import '../../theme/app_theme.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  Uint8List? _editedMediaBytes;
  bool _isUploading = false;
  static const String _imgbbApiKey = '9b144936080b6683b78410f3898f743d';

  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    _captionController.addListener(_onCaptionChanged);
  }

  void _onCaptionChanged() {
    final text = _captionController.text;
    final selection = _captionController.selection;
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
      setState(() {
        _mentionSuggestions = results;
      });
    }
  }

  void _insertMention(String username) {
    if (_mentionStartIndex == -1) return;
    
    final text = _captionController.text;
    final textBefore = text.substring(0, _mentionStartIndex);
    final textAfter = text.substring(_captionController.selection.baseOffset);
    
    final newText = '$textBefore@$username $textAfter';
    
    setState(() {
      _captionController.text = newText;
      _captionController.selection = TextSelection.collapsed(offset: _mentionStartIndex + username.length + 2);
      _currentMentionQuery = null;
      _mentionSuggestions = [];
    });
  }

  @override
  void dispose() {
    _captionController.removeListener(_onCaptionChanged);
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source) async {
    final XFile? media = await _picker.pickImage(
      source: source,
    );
    if (media != null && mounted) {
      ModernImageEditor.open(
        context,
        imagePath: media.path,
        mode: EditorMode.story,
        onComplete: (bytes) {
          setState(() {
            _editedMediaBytes = bytes;
          });
        },
      );
    }
  }

  Future<String?> _uploadToImgBB(Uint8List bytes) async {
    try {
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
      debugPrint('Story ImgBB upload error: $e');
      return null;
    }
  }

  Future<void> _handleUpload() async {
    if (_editedMediaBytes == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      final url = await _uploadToImgBB(_editedMediaBytes!);
      if (url == null) throw Exception('Upload failed');

      final caption = _captionController.text.trim();
      
      if (ProfanityFilterService.hasProfanity(caption)) {
        if (mounted) {
          showProfanityWarning(context);
        }
        return;
      }

      await FirebaseFirestore.instance.collection('stories').add({
        'userId': user.uid,
        'userName': userData['displayName'] ?? userData['name'] ?? 'User',
        'userAvatar': userData['profileImageUrl'] ?? userData['photoUrl'] ?? userData['photoURL'] ?? userData['avatar'] ?? '',
        'mediaUrl': url,
        'caption': caption,
        'type': 'image',
        'timestamp': FieldValue.serverTimestamp(),
        'expiresAt': DateTime.now().add(const Duration(hours: 24)),
      });

      if (caption.isNotEmpty) {
        await MentionHelper.processMentions(
          text: caption,
          currentUserId: user.uid,
          currentUserName: userData['displayName'] ?? userData['name'] ?? 'User',
          notificationType: 'mention_story',
          notificationMessage: 'mentioned you in a story',
        );
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background / Preview
          if (_editedMediaBytes != null)
            Image.memory(_editedMediaBytes!, fit: BoxFit.cover)
          else
            _buildEmptySelectionGrid(),
          
          // Navigation Overlay
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircularIcon(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.pop(context),
                ),
                if (_editedMediaBytes != null)
                   const Text(
                    'Your Story',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 10)],
                    ),
                  ),
                if (_editedMediaBytes != null)
                  _buildCircularIcon(
                    icon: Icons.crop_rotate_rounded,
                    onTap: () {
                      _pickMedia(ImageSource.gallery); 
                    },
                  ),
              ],
            ),
          ),
          
          // Mention Suggestions
          if (_mentionSuggestions.isNotEmpty && _currentMentionQuery != null)
            Positioned(
              left: 24,
              right: 24,
              bottom: (MediaQuery.of(context).viewInsets.bottom > 0 
                  ? MediaQuery.of(context).viewInsets.bottom + 10 
                  : 120) + 120,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _mentionSuggestions.length,
                  itemBuilder: (context, index) {
                    final user = _mentionSuggestions[index];
                    return _buildMentionTile(user);
                  },
                ),
              ),
            ),
          
          // Bottom Actions & Caption
          if (_editedMediaBytes != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                  ? MediaQuery.of(context).viewInsets.bottom + 16 
                  : 40,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Sleek Caption Input
                  ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1),
                        ),
                        child: TextField(
                          controller: _captionController,
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Add a caption...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 16),
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            filled: true,
                            fillColor: Colors.transparent,
                          ),
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.done,
                          cursorColor: Colors.white,
                          onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        ),
                      ),
                    ),
                  ),
                  
                  // Share Button (hides when typing to give more space, or we can keep it)
                  if (MediaQuery.of(context).viewInsets.bottom == 0) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildShareButton(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 16),
                      const Text(
                        'Sharing to Story...',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptySelectionGrid() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        gradient: LinearGradient(
          colors: [Colors.black, context.primary.withValues(alpha: 0.2)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_mosaic_rounded, size: 80, color: Colors.white24),
          const SizedBox(height: 32),
          const Text(
            'Create a Story',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share a moment with your connections',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
          const SizedBox(height: 48),
          _buildSelectionButton(
            icon: Icons.photo_library_outlined,
            label: 'Open Gallery',
            onTap: () => _pickMedia(ImageSource.gallery),
          ),
          const SizedBox(height: 16),
          _buildSelectionButton(
            icon: Icons.camera_alt_outlined,
            label: 'Take a Photo',
            onTap: () => _pickMedia(ImageSource.camera),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularIcon({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildMentionTile(Map<String, dynamic> user) {
    final avatar = user['profileImageUrl'] ?? '';
    final username = user['username'] ?? '';
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
        backgroundColor: Colors.grey[800],
        child: avatar.isEmpty ? const Icon(Icons.person, size: 16, color: Colors.white) : null,
      ),
      title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      onTap: () => _insertMention(username),
    );
  }

  Widget _buildShareButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 5)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _handleUpload,
          borderRadius: BorderRadius.circular(28),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Share to Story',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 16),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios_rounded, color: Colors.black, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
