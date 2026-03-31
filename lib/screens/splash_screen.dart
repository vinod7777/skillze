import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'onboarding_screen.dart';
import 'welcome_screen.dart';
import '../theme/app_theme.dart';
import 'main/main_navigation.dart';
import 'onboarding/skill_selection_screen.dart';
import 'onboarding/location_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _iconsController;
  late AnimationController _textController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _iconsOpacity;
  late Animation<double> _textSlide;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _iconsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _iconsOpacity = CurvedAnimation(
      parent: _iconsController,
      curve: Curves.easeIn,
    );

    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _textSlide = Tween<double>(begin: 20, end: 0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeOutCubic),
    );
    _textOpacity = CurvedAnimation(
      parent: _textController,
      curve: Curves.easeIn,
    );

    _startAnimations();
  }

  Future<void> _startAnimations() async {
    final prefsFuture = SharedPreferences.getInstance();

    await Future.delayed(const Duration(milliseconds: 300));
    _iconsController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 600));
    _textController.forward();

    final prefs = await prefsFuture;
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final onboardingDone = prefs.getBool('onboarding_completed') ?? false;
    final user = FirebaseAuth.instance.currentUser;

    Widget destination = const WelcomeScreen();

    if (!onboardingDone) {
      destination = const OnboardingScreen();
    } else if (user != null) {
      try {
        // Quick check for profile setup
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          final data = userDoc.data()!;
          final bool onboardingCompleted = data['onboardingCompleted'] ?? false;
          final List skills = data['skills'] ?? [];

          if (skills.isEmpty) {
            destination = const SkillSelectionScreen();
          } else if (!onboardingCompleted) {
            destination = const LocationSelectionScreen();
          } else {
            destination = const MainNavigation();
          }
        } else {
          // No user doc, but authenticated? Maybe signup failed mid-way.
          destination = const SkillSelectionScreen();
        }
      } catch (e) {
        // Fallback to MainNavigation and let it handle errors if needed
        destination = const MainNavigation();
      }
    } else {
      destination = const WelcomeScreen();
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _logoController.dispose();
    _iconsController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          // Background Illustration Icons
          FadeTransition(
            opacity: _iconsOpacity,
            child: _buildScatteredIcons(context),
          ),
          // Center Content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _logoController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _logoOpacity.value,
                      child: Transform.scale(
                        scale: _logoScale.value,
                        child: child,
                      ),
                    );
                  },
                  child: _buildLogo(),
                ),
                const SizedBox(height: 24),
                AnimatedBuilder(
                  animation: _textController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textOpacity.value,
                      child: Transform.translate(
                        offset: Offset(0, _textSlide.value),
                        child: child,
                      ),
                    );
                  },
                child: Text(
                  'Skillze',
                  style: GoogleFonts.pacifico(
                    fontSize: 56,
                    fontWeight: FontWeight.w800, // Extra bold
                    color: context.primary,
                  ),
                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/logo.png',
      width: 220,
      height: 220,
      fit: BoxFit.contain,
    );
  }

  Widget _buildScatteredIcons(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final icons = [
      _ScatterIcon(Icons.code, 0.1, 0.12, 45, 0.2),
      _ScatterIcon(Icons.palette_outlined, 0.85, 0.08, 52, -0.15),
      _ScatterIcon(Icons.language, 0.05, 0.35, 42, 0.1),
      _ScatterIcon(Icons.music_video, 0.9, 0.3, 48, -0.1),
      _ScatterIcon(Icons.terminal, 0.15, 0.88, 44, 0.05),
      _ScatterIcon(Icons.brush, 0.82, 0.85, 50, -0.1),
      _ScatterIcon(Icons.lightbulb_outline, 0.5, 0.02, 40, 0.0),
      _ScatterIcon(Icons.school, 0.08, 0.65, 45, 0.1),
      _ScatterIcon(Icons.edit_note, 0.78, 0.62, 48, -0.05),
      _ScatterIcon(Icons.laptop_mac, 0.25, 0.05, 38, -0.2),
      _ScatterIcon(Icons.smartphone, 0.7, 0.15, 40, 0.25),
      _ScatterIcon(Icons.analytics_outlined, 0.02, 0.5, 42, -0.1),
      _ScatterIcon(Icons.science_outlined, 0.92, 0.55, 46, 0.15),
      _ScatterIcon(Icons.design_services_outlined, 0.45, 0.92, 45, -0.05),
      _ScatterIcon(Icons.psychology_outlined, 0.88, 0.72, 40, 0.1),
      _ScatterIcon(Icons.auto_awesome, 0.65, 0.88, 35, -0.2),
      // New Musical Icons near center
      _ScatterIcon(Icons.music_note, 0.3, 0.35, 42, 0.15),
      _ScatterIcon(Icons.piano, 0.7, 0.35, 45, -0.1),
      _ScatterIcon(Icons.headphones, 0.35, 0.55, 40, -0.05),
      _ScatterIcon(Icons.mic_external_on, 0.65, 0.55, 38, 0.1),
    ];

    return Stack(
      children: icons.map((icon) {
        // Calculate distance from center (0.5, 0.5)
        final double dx = icon.x - 0.5;
        final double dy = icon.y - 0.5;
        final double dist = math.sqrt(dx * dx + dy * dy);

        // Max distance from center to corner is ~0.707
        final double t = (dist / 0.707).clamp(0.0, 1.0);

        // Theme-aware icon color
        final Color baseColor = context.primary;
        final double minOpacity = context.isDark ? 0.12 : 0.12; // Increased visibility in dark mode
        final double maxOpacity = context.isDark ? 0.45 : 0.55; // Sharp definition even in dark mode

        // Gradient effect: 
        // Icons near center = LIGHT (more transparent/faded)
        // Icons far from center = DARK (higher opacity)
        final Color iconColor = Color.lerp(
          baseColor.withOpacity(minOpacity), 
          baseColor.withOpacity(maxOpacity), 
          t,
        )!;

        return Positioned(
          left: size.width * icon.x,
          top: size.height * icon.y,
          child: Transform.rotate(
            angle: icon.rotation,
            child: Icon(icon.iconData, size: icon.size, color: iconColor),
          ),
        );
      }).toList(),
    );
  }
}

class _ScatterIcon {
  final IconData iconData;
  final double x;
  final double y;
  final double size;
  final double rotation;

  _ScatterIcon(this.iconData, this.x, this.y, this.size, this.rotation);
}
