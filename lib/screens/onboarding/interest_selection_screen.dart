import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clean_text_field.dart';

class InterestSelectionScreen extends StatefulWidget {
  final bool isEditMode;
  final List<String> initialSelectedInterests;

  const InterestSelectionScreen({
    super.key,
    this.isEditMode = false,
    this.initialSelectedInterests = const [],
  });

  @override
  State<InterestSelectionScreen> createState() => _InterestSelectionScreenState();
}

class _InterestSelectionScreenState extends State<InterestSelectionScreen> {
  late final List<String> _selectedInterests;
  final TextEditingController _searchController = TextEditingController();
  bool _isSaving = false;
  String _searchQuery = "";

  final List<String> _popularSkills = [
    'Flutter', 'React Native', 'Swift', 'Kotlin', 'Mobile Dev',
    'Python', 'Java', 'JavaScript', 'TypeScript', 'Node.js', 'Go', 'Rust',
    'AI', 'Machine Learning', 'Data Science', 'Deep Learning', 'NLP',
    'UI/UX Design', 'Product Design', 'Figma', 'Graphic Design',
    'Web Dev', 'React', 'Vue', 'Angular', 'Next.js',
    'Backend', 'Frontend', 'Full Stack', 'Cloud', 'DevOps', 'AWS', 'Firebase',
    'Cybersecurity', 'Blockchain', 'Web3', 'Game Dev', 'Unity',
    'Marketing', 'Copywriting', 'SEO', 'Business', 'Project Management'
  ];

  @override
  void initState() {
    super.initState();
    _selectedInterests = List<String>.from(widget.initialSelectedInterests);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleInterest(String skill) {
    setState(() {
      if (_selectedInterests.contains(skill)) {
        _selectedInterests.remove(skill);
      } else {
        if (_selectedInterests.length >= 30) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 30 interests allowed')),
          );
          return;
        }
        _selectedInterests.add(skill);
      }
    });
  }

  Future<void> _saveAndContinue() async {
    if (_selectedInterests.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one interest')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'interested_skills': _selectedInterests,
        });
      }
      if (mounted) {
        if (widget.isEditMode) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/location');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save interests: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queryLine = _searchQuery.trim();
    final normalizedQuery = queryLine.toLowerCase().replaceAll('_', ' ');
    final filteredSkills = _popularSkills
        .where((s) => s.toLowerCase().replaceAll('_', ' ').contains(normalizedQuery))
        .toList();

    final bool showCustomAdd = queryLine.isNotEmpty && 
        !filteredSkills.any((s) => s.toLowerCase().replaceAll('_', ' ') == normalizedQuery) &&
        !_selectedInterests.any((s) => s.toLowerCase().replaceAll('_', ' ') == normalizedQuery);


    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'What do you\nwant to learn?',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: context.textHigh,
                      height: 1.1,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Help us personalize your feed by selecting your interests.',
                    style: TextStyle(
                      fontSize: 15,
                      color: context.textMed,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 24),
                  CleanTextField(
                    controller: _searchController,
                    hintText: 'Search skills (e.g. Python, UI/UX)',
                    onChanged: (val) => setState(() => _searchQuery = val),
                    prefixIcon: Icons.search_rounded,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (showCustomAdd) ...[
                          GestureDetector(
                            onTap: () {
                              final parts = queryLine.split(' ');
                              final normalized = parts
                                  .where((p) => p.isNotEmpty)
                                  .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
                                  .join(' ');
                                  
                              if (_selectedInterests.length >= 30) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('You can select up to 30 interests')),
                                );
                                return;
                              }
                              
                              _toggleInterest(normalized);
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: context.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: context.primary.withValues(alpha: 0.5),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 20, color: context.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add "$queryLine"',
                                    style: TextStyle(
                                      color: context.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Combine popular skills and currently selected interests (including custom ones)
                        ...{
                          if (queryLine.isNotEmpty)
                            ..._selectedInterests
                                .where((s) => s.toLowerCase().contains(queryLine.toLowerCase())),
                          if (queryLine.isNotEmpty)
                            ...filteredSkills
                          else ...[
                            ..._selectedInterests,
                            ..._popularSkills,
                          ]
                        }.map((skill) {
                          final isSelected = _selectedInterests.contains(skill);
                          final isCustom = !_popularSkills.contains(skill);
                          return GestureDetector(
                            onTap: () => _toggleInterest(skill),
                            child: _buildSkillChip(
                              skill,
                              isSelected,
                              isCustom: isCustom,
                            ),
                          );
                        }),
                      ],
                    ),
              ),

            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    foregroundColor: context.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: context.onPrimary, strokeWidth: 2),
                        )
                      : Text(
                          'Continue',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.onPrimary),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkillChip(String name, bool isSelected, {bool isCustom = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: isSelected ? context.primary : context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? context.primary : (isCustom ? context.primary.withValues(alpha: 0.3) : context.border),
          width: 1.5,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: context.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCustom) ...[
            Icon(
              Icons.stars_rounded,
              size: 16,
              color: isSelected ? context.onPrimary : context.primary,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            name,
            style: TextStyle(
              color: isSelected ? context.onPrimary : context.textHigh,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
