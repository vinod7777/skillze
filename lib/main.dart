import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main/main_navigation.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'services/push_notification_service.dart';
import 'services/call_service.dart';
import 'services/notification_service.dart';
import 'screens/onboarding/skill_selection_screen.dart';
import 'screens/onboarding/interest_selection_screen.dart';
import 'screens/onboarding/location_selection_screen.dart';
import 'services/deep_link_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Analytics to stop warnings
    FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

    // Set background handler
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }
  } catch (e) {
    debugPrint("Firebase init error: $e");
  }

  // Initialize service & collect token
  try {
    await PushNotificationService.initialize();
    await PushNotificationService.setupCallKit();
    DeepLinkService.initialize(PushNotificationService.navigatorKey);
  } catch (e) {
    debugPrint("Push notification initialization error: $e");
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const FeedApp(),
    ),
  );
}

class FeedApp extends StatefulWidget {
  const FeedApp({super.key});

  @override
  State<FeedApp> createState() => _FeedAppState();
}

class _FeedAppState extends State<FeedApp> with WidgetsBindingObserver {
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        // App is authenticated
        final callService = CallService();
        callService.initialize();
        callService.onIncomingCall = (callId, callerName, callerAvatar, isVideo) {
          PushNotificationService.setupCallKit(); // make sure it's active
          // Note: we'd show the call kit UI via a static method if we exposed it.
        };
        callService.listenForIncomingCalls();
        // App is authenticated, ensure push token is synced & cache actor info
        PushNotificationService.updateToken();
        NotificationService.preCacheActor();
      } else {
        NotificationService.clearCache();
      }
    });
  }

  Timer? _statusTimer;

  void _startStatusHeartbeat() {
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'isOnline': true,
          'lastActive': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  void _stopStatusHeartbeat() {
    _statusTimer?.cancel();
    _statusTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (state == AppLifecycleState.resumed) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': true,
        'lastActive': FieldValue.serverTimestamp(),
      });
      _startStatusHeartbeat();
    } else {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastActive': FieldValue.serverTimestamp(),
      });
      _stopStatusHeartbeat();
    }
  }

  @override
  void dispose() {
    _stopStatusHeartbeat();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'isOnline': false,
        'lastActive': FieldValue.serverTimestamp(),
      });
    }
    _authSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      title: 'Feed Native',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(themeProvider.fontScale),
            highContrast: themeProvider.highContrast,
            disableAnimations: themeProvider.reduceMotion,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/signup': (context) => const SignupScreen(),
        '/main': (context) => const MainNavigation(),
        '/skills': (context) => const SkillSelectionScreen(),
        '/interests': (context) => const InterestSelectionScreen(),
        '/location': (context) => const LocationSelectionScreen(),
      },
    );
  }
}
