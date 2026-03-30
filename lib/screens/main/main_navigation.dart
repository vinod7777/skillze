import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import '../../theme/app_theme.dart';
import '../../services/localization_service.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'create_post_screen.dart';
import 'messages_screen.dart';
import 'profile_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => MainNavigationState();
}

class MainNavigationState extends State<MainNavigation> with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _presenceTimer;
  PageController? _pageController;
  bool _swipeEnabled = true;

  void toggleSwipe(bool enabled) {
    if (_swipeEnabled != enabled) {
      setState(() => _swipeEnabled = enabled);
    }
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    WidgetsBinding.instance.addObserver(this);
    _startLocationTracking();
    _updatePresence(true);
    // Refresh presence every 2 minutes
    _presenceTimer = Timer.periodic(const Duration(minutes: 2), (_) => _updatePresence(true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController?.dispose();
    _positionStreamSubscription?.cancel();
    _presenceTimer?.cancel();
    _updatePresence(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updatePresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _updatePresence(false);
    }
  }

  Future<void> _updatePresence(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'isOnline': isOnline,
          'lastActive': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Presence update error: $e');
      }
    }
  }

  Future<void> _startLocationTracking() async {
    try {
      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        // Options for high accuracy and frequent updates
        const LocationSettings locationSettings = LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter:
              5, // Filter by 5 meters to prevent jitter but keep frequency high
        );

        _positionStreamSubscription =
            Geolocator.getPositionStream(
              locationSettings: locationSettings,
            ).listen((Position position) {
              _updateFirestoreLocation(position);
            });
      }
    } catch (e) {
      debugPrint('Location tracking error: $e');
    }
  }

  Future<void> _updateFirestoreLocation(Position position) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'locationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore update error: $e');
      }
    }
  }

  void setIndex(int index) {
    if (mounted) {
      _pageController?.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  final List<Widget> _screens = [
    const HomeScreen(),
    SearchScreen(key: SearchScreen.searchKey),
    const MessagesScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentIndex != 0) {
          setIndex(0);
        }
      },
      child: Scaffold(
        backgroundColor: context.bg,
        body: PageView(
          controller: _pageController ??= PageController(initialPage: _currentIndex),
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          physics: const BouncingScrollPhysics(),
          children: _screens,
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: context.surfaceColor.withOpacity(0.95),
            border: Border(top: BorderSide(color: context.border.withOpacity(0.08), width: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 15,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                children: [
                  _buildNavIcon(0, Icons.home_rounded, Icons.home_outlined, context.t('home')),
                  _buildNavIcon(1, Icons.search_rounded, Icons.search_outlined, context.t('search')),
                  _buildNavCenterIcon(),
                  _buildNavIcon(2, Icons.chat_bubble_rounded, Icons.chat_bubble_outline_rounded, context.t('messages')),
                  _buildNavIcon(3, Icons.person_rounded, Icons.person_outline_rounded, context.t('profile')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon(int index, IconData selectedIcon, IconData unselectedIcon, String label) {
    final bool isSelected = _currentIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setIndex(index),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSelected ? selectedIcon : unselectedIcon,
              color: isSelected ? context.primary : context.textLow.withOpacity(0.7),
              size: 26,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? context.primary : context.textLow.withOpacity(0.7),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavCenterIcon() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (context) => const CreatePostScreen()),
        );
      },
      child: Container(
        height: 48,
        width: 48,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: context.primary,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: context.primary.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(Icons.add_rounded, color: context.isDark ? Colors.black : Colors.white, size: 28),
      ),
    );
  }
}
