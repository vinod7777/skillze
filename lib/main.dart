import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/main/main_navigation.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_notification_service.dart';
import 'services/callkit_service.dart';
import 'screens/onboarding/skill_selection_screen.dart';
import 'screens/onboarding/location_selection_screen.dart';
import 'services/deep_link_service.dart';

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
      DeepLinkService.initialize(PushNotificationService.navigatorKey);
      if (!kIsWeb) {
        await CallKitService.init();
      }
    } catch (e) {
      debugPrint("Push/CallKit initialization error: $e");
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // Check for active calls as soon as the app starts, after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!kIsWeb) {
        CallKitService.checkActiveCalls();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !kIsWeb) {
      CallKitService.checkActiveCalls();
    }
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
        '/location': (context) => const LocationSelectionScreen(),
      },
    );
  }
}
