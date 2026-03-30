import 'package:flutter/material.dart';

class PostSuccessScreen extends StatefulWidget {
  const PostSuccessScreen({super.key});

  @override
  State<PostSuccessScreen> createState() => _PostSuccessScreenState();
}

class _PostSuccessScreenState extends State<PostSuccessScreen>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _ringController;
  late Animation<double> _scaleAnim;
  late Animation<double> _ring1Anim;
  late Animation<double> _ring2Anim;
  late Animation<double> _ring3Anim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnim = CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    );

    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _ring1Anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _ring2Anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringController,
        curve: const Interval(0.15, 0.75, curve: Curves.easeOut),
      ),
    );
    _ring3Anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringController,
        curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
      ),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    _ringController.forward();
    Future.delayed(const Duration(milliseconds: 300), () {
      _scaleController.forward();
    });
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _ringController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF18181B),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Center content
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Animated rings + checkmark
                    AnimatedBuilder(
                      animation: Listenable.merge([
                        _scaleController,
                        _ringController,
                      ]),
                      builder: (context, child) {
                        return SizedBox(
                          width: 200,
                          height: 200,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Outer ring
                              Transform.scale(
                                scale: 0.6 + 0.4 * _ring3Anim.value,
                                child: Container(
                                  width: 200,
                                  height: 200,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0F2F6A).withOpacity(
                                            0.08 * (1 - _ring3Anim.value * 0.5),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Middle ring
                              Transform.scale(
                                scale: 0.6 + 0.4 * _ring2Anim.value,
                                child: Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0F2F6A).withOpacity(
                                            0.12 * (1 - _ring2Anim.value * 0.5),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Inner ring
                              Transform.scale(
                                scale: 0.6 + 0.4 * _ring1Anim.value,
                                child: Container(
                                  width: 120,
                                  height: 120,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF0F2F6A).withOpacity(
                                            0.18 * (1 - _ring1Anim.value * 0.3),
                                      ),
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              // Checkmark circle
                              ScaleTransition(
                                scale: _scaleAnim,
                                child: Container(
                                  width: 80,
                                  height: 80,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF0F2F6A),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),
                    // Title
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: const Text(
                        'Post Shared\nSuccessfully!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF18181B),
                          height: 1.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FadeTransition(
                      opacity: _fadeAnim,
                      child: const Text(
                        'Your post is now visible to your network',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          color: Color(0xFF71717A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F2F6A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
