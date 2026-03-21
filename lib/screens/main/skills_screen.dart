import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../theme/app_theme.dart';

class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  List<Map<String, dynamic>> _skills = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _currentStatus = "Software Developer";

  @override
  void initState() {
    super.initState();
    _fetchSkills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSkills() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final List<dynamic> skillsData = doc.data()?['skills_with_levels'] ?? [];
        if (skillsData.isNotEmpty) {
          _skills = List<Map<String, dynamic>>.from(skillsData);
        } else {
          // Fallback if only legacy list exists
          final List<dynamic> legacySkills = doc.data()?['skills'] ?? [];
          _skills = legacySkills.map((s) => {'name': s.toString(), 'level': 'Intermediate'}).toList();
        }
        _currentStatus = doc.data()?['status'] ?? "Software Developer";
      }
    } catch (e) {
      debugPrint("Error fetching skills: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSkills() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (ProfanityFilterService.hasProfanity(_currentStatus)) {
      showProfanityWarning(context);
      return;
    }
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'skills_with_levels': _skills,
        'skills': _skills.map((s) => s['name']).toList(), // Keep legacy list synced
        'status': _currentStatus,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Skills updated successfully!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _removeSkill(int index) {
    setState(() {
      _skills.removeAt(index);
    });
  }

  void _updateLevel(int index, String level) {
    setState(() {
      _skills[index]['level'] = level;
    });
  }

  void _addNewSkill(String name) {
    if (name.isEmpty) return;
    if (ProfanityFilterService.hasProfanity(name)) {
      showProfanityWarning(context);
      return;
    }
    if (_skills.any((s) => s['name'].toString().toLowerCase() == name.toLowerCase())) {
      return;
    }
    setState(() {
      _skills.add({'name': name, 'level': 'Beginner'});
    });
    _searchController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: Center(child: CircularProgressIndicator(color: context.primary)),
      );
    }

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
          'Manage Your Skills',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                // Search Bar
                Container(
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: context.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    onSubmitted: _addNewSkill,
                    decoration: InputDecoration(
                      hintText: 'Search for skills (e.g. Design, Coding)',
                      hintStyle: TextStyle(color: context.textLow, fontSize: 16),
                      prefixIcon: Icon(Icons.search_rounded, color: context.textLow),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Current Status section
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.work_outline_rounded, size: 16, color: context.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'CURRENT STATUS',
                                  style: TextStyle(
                                    color: context.primary.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _currentStatus,
                              style: TextStyle(
                                color: context.textHigh,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          // Show edit status dialog
                          _showEditStatusDialog();
                        },
                        icon: Icon(Icons.edit_note_rounded, color: context.textHigh),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Selected Skills Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Selected Skills',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.primary,
                      ),
                    ),
                    Text(
                      '${_skills.length} SKILLS',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textLow,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Skills List
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _skills.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final skill = _skills[index];
                    return _buildSkillCard(index, skill['name'], skill['level']);
                  },
                ),

                const SizedBox(height: 16),
                // Add Another Skill Dashed Button
                GestureDetector(
                  onTap: () => _focusSearch(),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: context.surfaceColor.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: context.border,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_circle_outline_rounded, color: context.textLow),
                        const SizedBox(width: 10),
                        Text(
                          'Add another skill',
                          style: TextStyle(
                            color: context.textLow,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 120), // Spacing for sticky button
              ],
            ),
          ),

          // Sticky Save Button
          Positioned(
            left: 24,
            right: 24,
            bottom: 30,
            child: SizedBox(
              height: 60,
              child: ElevatedButton(
                onPressed: _saveSkills,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.primary,
                  foregroundColor: context.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  elevation: 8,
                  shadowColor: context.primary.withValues(alpha: 0.3),
                ),
                child: const Text(
                  'Save Skills',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillCard(int index, String name, String level) {
    IconData skillIcon = Icons.code_rounded;
    if (name.toLowerCase().contains('photo')) skillIcon = Icons.camera_alt_rounded;
    if (name.toLowerCase().contains('design')) skillIcon = Icons.brush_rounded;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: context.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceLightColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(skillIcon, size: 20, color: context.primary),
              ),
              const SizedBox(width: 16),
              Text(
                name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: context.textHigh,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _removeSkill(index),
                icon: Icon(Icons.close_rounded, color: context.textLow),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Level Switcher
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: context.surfaceLightColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildLevelTab(index, 'Beginner', level == 'Beginner'),
                _buildLevelTab(index, 'Intermediate', level == 'Intermediate'),
                _buildLevelTab(index, 'Expert', level == 'Expert'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelTab(int skillIndex, String label, bool isSelected) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateLevel(skillIndex, label),
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isSelected ? context.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? context.onPrimary : context.textLow,
            ),
          ),
        ),
      ),
    );
  }

  void _focusSearch() {
    FocusScope.of(context).requestFocus(FocusNode()); // Just for example, ideally focus search bar
  }

  void _showEditStatusDialog() {
    final controller = TextEditingController(text: _currentStatus);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Main Skill/Status'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Fullstack Developer'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: context.textLow))),
          TextButton(
            onPressed: () {
              setState(() => _currentStatus = controller.text);
              Navigator.pop(context);
            },
            child: Text('Update', style: TextStyle(color: context.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
