import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../theme/app_theme.dart';
import '../onboarding/skill_selection_screen.dart';
class SkillsScreen extends StatefulWidget {
  const SkillsScreen({super.key});

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  List<Map<String, dynamic>> _skills = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _currentStatus = "";

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
        _currentStatus = doc.data()?['status'] ?? "";
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
        backgroundColor: context.bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.textHigh),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Manage Skills',
          style: TextStyle(
            color: context.textHigh,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton(
              onPressed: _saveSkills,
              style: TextButton.styleFrom(
                foregroundColor: context.primary,
                textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Standardized Search Input
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.border, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() {}),
                      onSubmitted: _addNewSkill,
                      style: TextStyle(color: context.textHigh),
                      decoration: InputDecoration(
                        hintText: 'Search or add your own skill...',
                        hintStyle: TextStyle(color: context.textLow),
                        prefixIcon: Icon(Icons.search_rounded, color: context.primary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.add_circle_rounded, color: context.primary),
                                onPressed: () => _addNewSkill(_searchController.text),
                                tooltip: 'Add custom skill',
                              )
                            : null,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 28),
                  
                  // Status Input Card
                  GestureDetector(
                    onTap: _showEditStatusDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: context.surfaceColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.border, width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.business_center_rounded, color: context.primary, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentStatus.isEmpty ? 'Set Professional Status' : _currentStatus,
                                  style: TextStyle(
                                    color: _currentStatus.isEmpty ? context.textLow : context.textHigh,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.edit_note_rounded, color: context.textLow, size: 20),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Your Skills',
                        style: TextStyle(
                          color: context.textHigh,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_skills.length} Total',
                        style: TextStyle(
                          color: context.textLow,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
          
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final skill = _skills[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildSkillCard(index, skill['name'], skill['level']),
                  );
                },
                childCount: _skills.length,
              ),
            ),
          ),
          
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              child: Opacity(
                opacity: 0.8,
                child: TextButton.icon(
                  onPressed: _navigateToSkillSelection,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Skills'),
                  style: TextButton.styleFrom(
                    foregroundColor: context.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: context.textHigh,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _removeSkill(index),
                child: Icon(Icons.close_rounded, color: context.textLow, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: context.bg,
              borderRadius: BorderRadius.circular(10),
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isSelected ? context.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? Colors.white : context.textMed.withOpacity(0.7),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToSkillSelection() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SkillSelectionScreen(
          isEditMode: true,
          initialSelectedSkills: _skills.map((s) => s['name'] as String).toList(),
        ),
      ),
    ).then((_) => _fetchSkills());
  }

  void _showEditStatusDialog() {
    final controller = TextEditingController(text: _currentStatus);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Professional Status',
                style: TextStyle(
                  color: context.textHigh,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Define your role or current focus briefly.',
                style: TextStyle(color: context.textMed.withOpacity(0.7), fontSize: 14),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: context.textHigh, fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.surfaceLightColor,
                  hintText: 'e.g. Fullstack Developer, Product Designer',
                  hintStyle: TextStyle(color: context.textMed.withOpacity(0.4)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: context.primary, width: 2),
                  ),
                  contentPadding: const EdgeInsets.all(20),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() => _currentStatus = controller.text);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
