import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../utils/mention_helper.dart';

class CreateStoryScreen extends StatefulWidget {
  const CreateStoryScreen({super.key});

  @override
  State<CreateStoryScreen> createState() => _CreateStoryScreenState();
}

class _CreateStoryScreenState extends State<CreateStoryScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _captionController = TextEditingController();
  XFile? _selectedMedia;
  bool _isUploading = false;
  static const String _imgbbApiKey = '9b144936080b6683b78410f3898f743d';

  List<String> _followingList = [];
  List<Map<String, dynamic>> _mentionSuggestions = [];
  String? _currentMentionQuery;
  int _mentionStartIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchFollowingList();
    _captionController.addListener(_onCaptionChanged);
  }

  Future<void> _fetchFollowingList() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    _followingList = List<String>.from(doc.data()?['followingList'] ?? []);
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

  Future<void> _pickMedia() async {
    final XFile? media = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (media != null) {
      setState(() {
        _selectedMedia = media;
      });
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
      debugPrint('Story ImgBB upload error: $e');
      return null;
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedMedia == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};

      final url = await _uploadToImgBB(_selectedMedia!);
      if (url == null) throw Exception('Upload failed');

      final caption = _captionController.text.trim();
      
      if (ProfanityFilterService.hasProfanity(caption)) {
        showProfanityWarning(context);
        return;
      }

      await FirebaseFirestore.instance.collection('stories').add({
        'userId': user.uid,
        'userName': userData['displayName'] ?? userData['name'] ?? 'User',
        'userAvatar': userData['photoUrl'] ?? userData['profileImageUrl'] ?? '',
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
      resizeToAvoidBottomInset: false, // Prevent the background image from squishing
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_selectedMedia != null)
            Image.file(io.File(_selectedMedia!.path), fit: BoxFit.cover)
          else
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                   const Icon(Icons.add_a_photo_outlined, size: 64, color: Colors.white),
                   const SizedBox(height: 16),
                   ElevatedButton(
                     onPressed: _pickMedia,
                     child: const Text('Select Photo'),
                   ),
                ],
              ),
            ),
          
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 32),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          
          if (_mentionSuggestions.isNotEmpty && _currentMentionQuery != null) ...[
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: 20,
              right: 20,
              bottom: (MediaQuery.of(context).viewInsets.bottom > 0 
                  ? MediaQuery.of(context).viewInsets.bottom + 20 
                  : 120) + 140, // sit above the text field
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _mentionSuggestions.length,
                  itemBuilder: (context, index) {
                    final user = _mentionSuggestions[index];
                    final username = user['username'] ?? '';
                    final name = user['name'] ?? '';
                    final avatar = user['profileImageUrl'] ?? user['authorProfileImageUrl'] ?? user['photoUrl'] ?? '';
                    
                    return ListTile(
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundImage: avatar.isNotEmpty ? NetworkImage(avatar) : null,
                        child: avatar.isEmpty ? const Icon(Icons.person, size: 16) : null,
                      ),
                      title: Text(username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(name, style: const TextStyle(color: Colors.white70)),
                      onTap: () => _insertMention(username),
                    );
                  },
                ),
              ),
            ),
          ],
          
          if (_selectedMedia != null)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: 20,
              right: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0 
                  ? MediaQuery.of(context).viewInsets.bottom + 20 
                  : 120,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65), // Stronger glass effect
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    )
                  ],
                ),
                child: TextField(
                  controller: _captionController,
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    hintText: 'Add a caption... (@username)',
                    hintStyle: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.normal,
                    ),
                    border: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
                  ),
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
            ),
          
          if (_selectedMedia != null)
            Positioned(
              bottom: 40,
              right: 20,
              child: FloatingActionButton.extended(
                backgroundColor: const Color(0xFF0F2F6A),
                onPressed: _isUploading ? null : _handleUpload,
                label: _isUploading 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Add to Story', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                icon: const Icon(Icons.send_rounded, color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}
