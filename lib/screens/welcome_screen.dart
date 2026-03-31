import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'auth/login_screen.dart';
import 'auth/signup_screen.dart';
import '../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            // Scattered icons top area
            SizedBox(
              height: 120,
              child: _buildDecoratedIcons(
                [
                  _ScatterIcon(Icons.code, 0.1, 0.1, 42, 0.2),
                  _ScatterIcon(Icons.palette_outlined, 0.9, 0.2, 48, -0.15),
                  _ScatterIcon(Icons.laptop_mac, 0.4, 0.2, 38, 0.0),
                  _ScatterIcon(Icons.terminal, 0.7, 0.1, 32, 0.0),
                  _ScatterIcon(Icons.piano, 0.3, 0.6, 40, 0.1),
                  _ScatterIcon(Icons.mic_external_on, 0.7, 0.6, 36, -0.1),
                ],
                size,
                true, // top
                context,
              ),
            ),
            // Logo
            _buildLogo(),
            const SizedBox(height: 16),
            // SKILLZE text
            Text(
              'SKILLZE',
              style: GoogleFonts.outfit(
                fontSize: 52,
                fontWeight: FontWeight.w900,
                color: context.primary,
                letterSpacing: 3,
              ),
            ),
            const Spacer(flex: 1),
            // Scattered icons bottom area
            SizedBox(
              height: 100,
              child: _buildDecoratedIcons(
                [
                  _ScatterIcon(Icons.music_note, 0.15, 0.2, 44, 0.1),
                  _ScatterIcon(Icons.brush_outlined, 0.85, 0.3, 46, -0.1),
                  _ScatterIcon(Icons.school_outlined, 0.5, 0.1, 40, 0.0),
                  _ScatterIcon(Icons.headphones, 0.35, 0.05, 38, -0.15),
                  _ScatterIcon(Icons.auto_awesome, 0.65, 0.05, 35, 0.1),
                ],
                size,
                false, // bottom
                context,
              ),
            ),
            const Spacer(flex: 1),
            // Login button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.primary,
                    foregroundColor: context.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Create New Account
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupScreen()),
                );
              },
              child: Text(
                'Create New Account',
                style: TextStyle(
                  color: context.textMed,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/logo.png',
      width: 300,
      height: 300,
      fit: BoxFit.contain,
    );
  }

  Widget _buildDecoratedIcons(
    List<_ScatterIcon> icons,
    Size screenSize,
    bool isTop,
    BuildContext context,
  ) {
    return Stack(
      children: icons.map((icon) {
        final double dx = icon.x - 0.5;
        final double dist = math.sqrt(dx * dx * 1.5 + (0.5 - icon.y) * 0.5);
        final double t = (dist * 1.5).clamp(0.0, 1.0);

        // Adapt decorative colors for dark mode
        final Color nearColor = context.isDark
            ? context.surfaceLightColor
            : const Color(0xFFF1F5F9);
        final Color farColor = context.isDark
            ? context.textLow.withOpacity(0.2)
            : const Color(0xFF94A3B8);

        final Color iconColor = Color.lerp(nearColor, farColor, t)!;

        return Positioned(
          left: screenSize.width * icon.x,
          top: isTop ? 120 * icon.y : null,
          bottom: !isTop ? 100 * icon.y : null,
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
