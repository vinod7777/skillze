import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import 'clean_text_field.dart';

class InterestsBottomSheet extends StatefulWidget {
  final List<String> initialSkills;
  final Function(List<String>) onSave;

  const InterestsBottomSheet({
    super.key,
    required this.initialSkills,
    required this.onSave,
  });

  static Future<void> show(BuildContext context, {required List<String> initialSkills, required Function(List<String>) onSave}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => InterestsBottomSheet(initialSkills: initialSkills, onSave: onSave),
    );
  }

  @override
  State<InterestsBottomSheet> createState() => _InterestsBottomSheetState();
}

class _InterestsBottomSheetState extends State<InterestsBottomSheet> {
  late List<String> _selectedSkills;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _allSkills = [
    'Flutter', 'React Native', 'Swift', 'Kotlin', 'Mobile Development',
    'Python', 'Java', 'JavaScript', 'TypeScript', 'Node.js', 'Go', 'Rust',
    'AI', 'Machine Learning', 'Data Science', 'Deep Learning', 'NLP',
    'UI/UX', 'Product Design', 'Figma', 'Graphic Design', 'Motion Design',
    'Web Development', 'React', 'Vue', 'Angular', 'Next.js',
    'Backend', 'Frontend', 'Full Stack', 'Cloud', 'DevOps', 'AWS', 'Firebase',
    'Cybersecurity', 'Blockchain', 'Web3', 'Game Development', 'Unity',
    'Photography', 'Videography', 'Video Editing', 'Cinematography',
    'Fitness', 'Yoga', 'Meditation', 'Wellness', 'Personal Training',
    'Cooking', 'Baking', 'Pastry Arts', 'Culinary Arts',
    'Marketing', 'Copywriting', 'SEO', 'Social Media', 'Content Creation',
    'Public Speaking', 'Debate', 'Storytelling', 'Comedy',
    'Sales', 'Negotiation', 'Business', 'Entrepreneurship', 'Financial Planning',
    'Painting', 'Sketching', 'Digital Art', 'Sculpture',
    'Music', 'Singing', 'Guitar', 'Piano', 'Drums',
    'Gardening', 'Landscaping', 'Urban Farming', 'Sustainability',
    'Carpentry', 'Woodworking', 'DIY', 'Interior Design',
    'Fashion Design', 'Tailoring', 'Styling', 'Makeup Artistry',
    'Travel Planning', 'Languages', 'Translation', 'Linguistics',
  ];


  @override
  void initState() {
    super.initState();
    _selectedSkills = List.from(widget.initialSkills);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        if (_selectedSkills.length >= 30) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maximum 30 interests allowed')),
          );
          return;
        }
        _selectedSkills.add(skill);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final queryLine = _searchQuery.trim();
    final normalizedQuery = queryLine.toLowerCase().replaceAll('_', ' ');
    final filteredSkills = _allSkills
        .where((s) => s.toLowerCase().replaceAll('_', ' ').contains(normalizedQuery))
        .toList();

    // If query is not empty and not in filtered skills AND not already selected, add it as a possible option
    final bool showCustomAdd = queryLine.isNotEmpty && 
        !filteredSkills.any((s) => s.toLowerCase().replaceAll('_', ' ') == normalizedQuery) &&
        !_selectedSkills.any((s) => s.toLowerCase().replaceAll('_', ' ') == normalizedQuery);


    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.surfaceColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header Indicator
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Title and Reset
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personalize Feed',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: context.textHigh,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select skills you want to explore',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textLow,
                          ),
                        ),
                      ],
                    ),
                    if (_selectedSkills.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selectedSkills.clear()),
                        child: Text(
                          'Reset',
                          style: TextStyle(
                            color: context.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: CleanTextField(
                  controller: _searchController,
                  hintText: 'Search skills...',
                  prefixIcon: Icons.search_rounded,
                ),
              ),

              const SizedBox(height: 20),

              // Selected Count Chip
              if (_selectedSkills.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${_selectedSkills.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: context.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Skills Grid
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Wrap(
                      spacing: 10,
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
                              
                              if (_selectedSkills.length >= 30) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('You can select up to 30 interests')),
                                );
                                return;
                              }
                              
                              _toggleSkill(normalized);
                              _searchController.clear();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: context.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: context.primary.withOpacity(0.5),
                                  width: 1.5,
                                  style: BorderStyle.solid,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_rounded, size: 18, color: context.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Add "$queryLine"',
                                    style: TextStyle(
                                      color: context.primary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Combine predefined skills and currently selected ones (including custom)
                        ...{
                          if (queryLine.isNotEmpty)
                            ..._selectedSkills.where((s) => s.toLowerCase().contains(queryLine.toLowerCase())),
                          if (queryLine.isNotEmpty)
                            ...filteredSkills
                          else ...[
                            ..._selectedSkills,
                            ..._allSkills,
                          ]
                        }.map((skill) {
                          final isSelected = _selectedSkills.contains(skill);
                          final isCustom = !_allSkills.contains(skill);
                          return GestureDetector(
                            onTap: () => _toggleSkill(skill),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? context.primary : context.surfaceLightColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? context.primary : (isCustom ? context.primary.withOpacity(0.3) : context.border),
                                  width: 1.5,
                                ),
                                boxShadow: isSelected ? [
                                  BoxShadow(
                                    color: context.primary.withOpacity(0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  )
                                ] : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCustom) ...[
                                    Icon(
                                      Icons.stars_rounded,
                                      size: 16,
                                      color: isSelected ? Colors.white : context.primary,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Text(
                                    skill,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : context.textMed,
                                      fontSize: 14,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),

                    const SizedBox(height: 100), // Bottom space for button
                  ],
                ),
              ),

              // Save Button
              Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: () async {
                      final user = FirebaseAuth.instance.currentUser;
                      if (user != null) {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .update({'interested_skills': _selectedSkills});
                        widget.onSave(_selectedSkills);
                        if (mounted) {
                          Navigator.pop(context);
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Apply Interests',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
