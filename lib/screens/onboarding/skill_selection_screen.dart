import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/profanity_filter_service.dart';
import '../../utils/profanity_helper.dart';
import '../../theme/app_theme.dart';
import '../../widgets/clean_text_field.dart';

class SkillSelectionScreen extends StatefulWidget {
  final bool isEditMode;
  final List<String> initialSelectedSkills;

  const SkillSelectionScreen({
    super.key,
    this.isEditMode = false,
    this.initialSelectedSkills = const [],
  });

  @override
  State<SkillSelectionScreen> createState() => _SkillSelectionScreenState();
}

class _SkillSelectionScreenState extends State<SkillSelectionScreen> {
  late final List<String> _selectedSkills;
  final List<String> _customSkills = [];
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  bool _isSaving = false;
  String _searchQuery = "";
  String? _roleError;

  @override
  void initState() {
    super.initState();
    _selectedSkills = List<String>.from(widget.initialSelectedSkills);
    
    // Identify custom skills that are not in the predefined categories
    final allPredefined = <String>{};
    for (var list in _categories.values) {
      for (var s in list) {
        allPredefined.add(s['name'] as String);
      }
    }

    for (var skill in _selectedSkills) {
      if (!allPredefined.contains(skill)) {
        _customSkills.add(skill);
      }
    }
    
    _loadInitialRole();
  }

  Future<void> _loadInitialRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _roleController.text = doc.data()?['role'] ?? '';
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  final Map<String, List<Map<String, dynamic>>> _categories = {
    'Technology': [
      {'name': 'Programming', 'icon': Icons.code_rounded},
      {'name': 'Web Development', 'icon': Icons.language_rounded},
      {'name': 'Mobile Dev', 'icon': Icons.phone_android_rounded},
      {'name': 'UI/UX Design', 'icon': Icons.brush_rounded},
      {'name': 'Data Science', 'icon': Icons.bar_chart_rounded},
      {'name': 'Cybersecurity', 'icon': Icons.security_rounded},
      {'name': 'Cloud Computing', 'icon': Icons.cloud_queue_rounded},
    ],
    'Creative': [
      {'name': 'Photography', 'icon': Icons.camera_alt_rounded},
      {'name': 'Video Editing', 'icon': Icons.movie_creation_rounded},
      {'name': 'Graphic Design', 'icon': Icons.palette_rounded},
      {'name': 'Music Production', 'icon': Icons.music_note_rounded},
      {'name': 'Animation', 'icon': Icons.animation_rounded},
      {'name': 'Painting', 'icon': Icons.edit_rounded},
      {'name': 'Fashion Design', 'icon': Icons.style_rounded},
    ],
    'Business': [
      {'name': 'Marketing', 'icon': Icons.trending_up_rounded},
      {'name': 'Public Speaking', 'icon': Icons.record_voice_over_rounded},
      {'name': 'Management', 'icon': Icons.groups_rounded},
      {'name': 'Finance', 'icon': Icons.account_balance_wallet_rounded},
      {'name': 'Sales', 'icon': Icons.shopping_cart_rounded},
      {'name': 'Entrepreneurship', 'icon': Icons.lightbulb_rounded},
    ],
    'Lifestyle': [
      {'name': 'Cooking', 'icon': Icons.restaurant_rounded},
      {'name': 'Fitness', 'icon': Icons.fitness_center_rounded},
      {'name': 'Yoga', 'icon': Icons.self_improvement_rounded},
      {'name': 'Baking', 'icon': Icons.bakery_dining_rounded},
      {'name': 'Cycling', 'icon': Icons.directions_bike_rounded},
      {'name': 'Gardening', 'icon': Icons.eco_rounded},
      {'name': 'Nutrition', 'icon': Icons.apple_rounded},
      {'name': 'Mental Health', 'icon': Icons.psychology_rounded},
    ],
    'Creative & Arts': [
      {'name': 'Painting', 'icon': Icons.format_paint_rounded},
      {'name': 'Sketching', 'icon': Icons.gesture_rounded},
      {'name': 'Photography', 'icon': Icons.camera_alt_rounded},
      {'name': 'Fashion Design', 'icon': Icons.style_rounded},
      {'name': 'Interior Design', 'icon': Icons.home_rounded},
      {'name': 'Animation', 'icon': Icons.animation_rounded},
      {'name': 'Acting', 'icon': Icons.theater_comedy_rounded},
    ],
    'Professional': [
      {'name': 'Public Speaking', 'icon': Icons.record_voice_over_rounded},
      {'name': 'Negotiation', 'icon': Icons.handshake_rounded},
      {'name': 'Leadership', 'icon': Icons.star_rounded},
      {'name': 'Strategy', 'icon': Icons.insights_rounded},
      {'name': 'Accounting', 'icon': Icons.calculate_rounded},
    ],
  };

  final List<String> _suggestedRoles = [
    'Software Engineer', 'Full Stack Developer', 'Flutter Developer', 'React Developer',
    'Backend Developer', 'Frontend Developer', 'Mobile Developer',
    'Product Designer', 'UI/UX Designer', 'Graphic Designer', 'Illustrator',
    'Data Scientist', 'Data Analyst', 'Machine Learning Engineer',
    'Marketing Manager', 'Content Creator', 'SEO Specialist', 'Social Media Manager',
    'Project Manager', 'Product Manager', 'Scrum Master',
    'Photographer', 'Videographer', 'Video Editor',
    'Chef', 'Baker', 'Cook',
    'Fitness Coach', 'Yoga Instructor', 'Personal Trainer',
    'Sales Representative', 'Business Development Manager',
    'Accountant', 'Financial Advisor',
    'Student', 'Researcher', 'Professor',
    'Entrepreneur', 'Founder', 'CEO',
    'Customer Support', 'Virtual Assistant',
  ];


  void _toggleSkill(String skill) {
    setState(() {
      if (_selectedSkills.contains(skill)) {
        _selectedSkills.remove(skill);
      } else {
        _selectedSkills.add(skill);
      }
    });
  }

  void _addCustomSkill() {
    final skill = _searchController.text.trim();
    if (skill.isNotEmpty) {
      if (ProfanityFilterService.hasProfanity(skill)) {
        showProfanityWarning(context);
        return;
      }
      if (!_selectedSkills.contains(skill)) {
        setState(() {
          _customSkills.add(skill);
          _selectedSkills.add(skill);
          _searchController.clear();
          _searchQuery = "";
        });
      } else {
        _searchController.clear();
        _searchQuery = "";
      }
    }
  }

  Future<void> _saveAndContinue() async {
    if (_selectedSkills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one skill')),
      );
      return;
    }

    if (_roleController.text.trim().isEmpty) {
      setState(() => _roleError = 'Please tell us your role');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final doc = await docRef.get();
        final currentSkillsWithLevels = List<Map<String, dynamic>>.from(doc.data()?['skills_with_levels'] ?? []);
        
        // Construct new skills_with_levels list based on selections
        final updatedSkillsWithLevels = _selectedSkills.map((name) {
          try {
            return currentSkillsWithLevels.firstWhere(
              (s) => s['name'] == name,
            );
          } catch (_) {
            return {'name': name, 'level': 'Intermediate'};
          }
        }).toList();

        final Map<String, dynamic> updateData = {
          'role': _roleController.text.trim(),
          'skills': _selectedSkills,
          'skills_with_levels': updatedSkillsWithLevels,
        };
        
        if (!widget.isEditMode) {
          updateData['onboardingStep'] = 1;
        }

        await docRef.update(updateData);
      }
      if (mounted) {
        if (widget.isEditMode) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacementNamed(context, '/interests');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving skills: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                   Text(
                    'What are you good at?',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: context.textHigh,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select the skills you want to share or learn in Skillze.',
                    style: TextStyle(
                      fontSize: 16,
                      color: context.textMed,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Role Section with Autocomplete
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return _suggestedRoles.where((role) {
                        return role.toLowerCase().contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      _roleController.text = selection;
                      if (_roleError != null) setState(() => _roleError = null);
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      // Sync external controller with autocomplete controller
                      if (_roleController.text != controller.text && _roleController.text.isNotEmpty && controller.text.isEmpty) {
                        controller.text = _roleController.text;
                      }
                      
                      return CleanTextField(
                        label: 'WHAT IS YOUR ROLE?',
                        hintText: 'e.g. Flutter Developer, Product Designer',
                        controller: controller, // Use the autocomplete controller
                        focusNode: focusNode,
                        prefixIcon: Icons.work_outline,
                        errorText: _roleError,
                        onChanged: (val) {
                          _roleController.text = val;
                          if (_roleError != null) setState(() => _roleError = null);
                        },
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 8,
                          borderRadius: BorderRadius.circular(10),
                          color: context.surfaceColor,
                          child: Container(
                            width: MediaQuery.of(context).size.width - 48,
                            constraints: const BoxConstraints(maxHeight: 250),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (context, index) => Divider(height: 1, color: context.border.withOpacity(0.5)),
                              itemBuilder: (BuildContext context, int index) {
                                final String option = options.elementAt(index);
                                return ListTile(
                                  onTap: () => onSelected(option),
                                  title: Text(
                                    option,
                                    style: TextStyle(color: context.textHigh, fontSize: 14),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),
                  
                  // Skill Search Header
                  Text(
                    'SELECT YOUR SKILLS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: context.textLow,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Search and Add Bar
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(10),
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
                      onChanged: (value) => setState(() => _searchQuery = value),
                      onSubmitted: (_) => _addCustomSkill(),
                      style: TextStyle(color: context.textHigh),
                      decoration: InputDecoration(
                        hintText: 'Search or add your own skill...',
                        hintStyle: TextStyle(color: context.textLow),
                        prefixIcon: Icon(Icons.search_rounded, color: context.primary),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.add_circle_rounded, color: context.primary),
                                onPressed: _addCustomSkill,
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
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                physics: const BouncingScrollPhysics(),
                children: [
                  // Show Custom Skills section if any exist
                  if (_customSkills.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'YOUR ADDED SKILLS',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: context.textLow,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _customSkills.map((skill) {
                            final isSelected = _selectedSkills.contains(skill);
                            return GestureDetector(
                              onTap: () => _toggleSkill(skill),
                              child: _buildSkillChip(skill, Icons.stars_rounded, isSelected),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Show filtered categories
                  ..._categories.entries.map((category) {
                    final filteredSkills = category.value.where((skill) {
                      return skill['name']
                          .toString()
                          .toLowerCase()
                          .contains(_searchQuery.toLowerCase());
                    }).toList();

                    if (filteredSkills.isEmpty) return const SizedBox.shrink();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            category.key.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: context.textLow,
                            ),
                          ),
                        ),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: filteredSkills.map((skill) {
                            final isSelected = _selectedSkills.contains(skill['name']);
                            return GestureDetector(
                              onTap: () => _toggleSkill(skill['name']),
                              child: _buildSkillChip(
                                skill['name'],
                                skill['icon'],
                                isSelected,
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  }),
                ],
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

  Widget _buildSkillChip(String name, IconData icon, bool isSelected) {
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
          color: isSelected ? context.primary : context.border,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: context.primary.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
            color: isSelected ? context.onPrimary : context.primary,
          ),
          const SizedBox(width: 8),
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
