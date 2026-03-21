import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/main/conversation_screen.dart';
import '../screens/main/call_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import '../firebase_options.dart';
import 'package:googleapis_auth/auth_io.dart';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'callkit_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> initialize() async {
    // 1. Check if notifications are enabled
    final isEnabled = await areNotificationsEnabled();
    if (!isEnabled) {
      debugPrint('Notifications are disabled by user preference.');
      return;
    }

    // 2. Request Runtime Permissions
    await _requestPermissions();

    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      // 2. Initialize Local Notifications
      const AndroidInitializationSettings androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
      );
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationClick(response.payload);
        },
      );

      // Create channels
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'feed_native_high',
        'High Priority Notifications',
        description: 'Notifications with sound and heads-up display',
        importance: Importance.max,
        playSound: true,
      );

      const AndroidNotificationChannel callChannel = AndroidNotificationChannel(
        'feed_native_calls',
        'Incoming Calls',
        description: 'Used for incoming video and audio calls',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      await androidPlugin?.createNotificationChannel(channel);
      await androidPlugin?.createNotificationChannel(callChannel);
    }

    // 3. Handle Notification Clicks
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(jsonEncode(message.data));
    });

    if (!kIsWeb) {
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          _handleNotificationClick(jsonEncode(message.data));
        }
      });
    }

    // 5. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      // Check if notifications are enabled before showing anything
      if (!(await areNotificationsEnabled())) return;

      if (message.data['type'] == 'call') {
        final callerId = message.data['callerId'];
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        
        // Don't show incoming call UI if it's our own call (sometimes happens with topic sync/multi-device)
        if (callerId != null && callerId == currentUserId) return;

        CallKitService.showCallNotification(
          callerId: callerId ?? '',
          callerName: message.data['callerName'] ?? 'Unknown',
          callId: message.data['callId'] ?? '',
          isVideo: message.data['isVideo'] == 'true',
        );
      } else if (message.notification != null) {
        _showLocalNotification(message);
      }
    });

    // 6. Token handling
    _messaging.onTokenRefresh.listen((token) async {
      if (await areNotificationsEnabled()) {
        updateToken(token);
      }
    });
    
    if (await areNotificationsEnabled()) {
      updateToken();
    }
  }

  static Future<void> updateToken([String? token]) async {
    if (!(await areNotificationsEnabled())) return;
    final fcmToken = token ?? await _messaging.getToken();
    if (fcmToken != null) await _saveToken(fcmToken);
  }

  static Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsEnabledKey) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsEnabledKey, enabled);

    if (enabled) {
      await updateToken();
    } else {
      await _removeToken();
    }
  }

  static Future<void> _removeToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'fcmToken': FieldValue.delete(),
      });
    }
  }

  static void _handleNotificationClick(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload);
      if (data['type'] == 'chat') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ConversationScreen(
              chatId: data['chatId'],
              otherUserId: data['otherUserId'],
              otherUserName: data['otherUserName'],
            ),
          ),
        );
      } else if (data['type'] == 'call') {
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        final callerId = data['callerId'];
        if (callerId != null && callerId == currentUserId) {
          debugPrint('Attempted to call self via notification click. Ignoring.');
          return;
        }
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              callId: data['callId'],
              otherUserId: data['callerId'],
              otherUserName: data['callerName'] ?? 'Unknown',
              isVideo: data['isVideo'] == 'true',
              isReceiver: true,
              autoAnswer: false, // User just tapped notification, didn't press 'Accept' button
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Notification handle error: $e');
    }
  }

  static Future<String> _getAccessToken() async {
    if (kIsWeb) return "";
    try {
      final serviceAccountJson = await rootBundle.loadString(
        'assets/service-account.json',
      );
      final accountCredentials = ServiceAccountCredentials.fromJson(
        serviceAccountJson,
      );
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      return client.credentials.accessToken.data;
    } catch (e) {
      debugPrint("Error getting access token: $e");
      return "";
    }
  }

  static Future<void> sendNotification({
    required String recipientToken,
    required String title,
    required String body,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      const projectID = 'feed-609dd';

      await http.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectID/messages:send',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': {
            'token': recipientToken,
            'notification': (extraData?['type'] == 'call')
                ? null
                : {'title': title, 'body': body},
            'data': extraData ?? {},
            'android': {
              'priority': 'high',
              'notification': (extraData?['type'] == 'call')
                  ? null
                  : {'channel_id': 'feed_native_high', 'sound': 'default'},
            },
          },
        }),
      );
    } catch (e) {
      debugPrint('Error sending push: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    if (!kIsWeb) {
      await [
        Permission.notification,
        Permission.camera,
        Permission.microphone,
      ].request();
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'feed_native_high',
          'High Priority Notifications',
          importance: Importance.max,
          priority: Priority.max,
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title,
      body: message.notification?.body,
      notificationDetails: details,
      payload: jsonEncode(message.data),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Check if notifications are enabled locally for this device
  final prefs = await SharedPreferences.getInstance();
  final isEnabled = prefs.getBool('notifications_enabled') ?? true;
  if (!isEnabled) return;

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Show CallKit incoming call UI when a call arrives in background
  if (message.data['type'] == 'call') {
    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: message.data['callId'] ?? '',
        nameCaller: message.data['callerName'] ?? 'Unknown',
        appName: 'Feed Native',
        handle: message.data['isVideo'] == 'true' ? 'Video Call' : 'Audio Call',
        type: message.data['isVideo'] == 'true' ? 1 : 0,
        duration: 30000,
        textAccept: 'Accept',
        textDecline: 'Decline',
        missedCallNotification: const NotificationParams(
          showNotification: true,
          isShowCallback: true,
          subtitle: 'Missed call',
          callbackText: 'Call back',
        ),
        extra: <String, dynamic>{
          'callId': message.data['callId'] ?? '',
          'callerId': message.data['callerId'] ?? '',
          'callerName': message.data['callerName'] ?? 'Unknown',
          'isVideo': message.data['isVideo'] ?? 'false',
        },
        android: const AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          ringtonePath: 'system_ringtone_default',
          backgroundColor: '#0955fa',
          actionColor: '#4CAF50',
          textColor: '#ffffff',
          isShowFullLockedScreen: true,
        ),
        ios: const IOSParams(
          iconName: 'CallKitLogo',
          handleType: 'generic',
          supportsVideo: true,
          maximumCallGroups: 2,
          maximumCallsPerCallGroup: 1,
          audioSessionMode: 'default',
          audioSessionActive: true,
          audioSessionPreferredSampleRate: 44100.0,
          audioSessionPreferredIOBufferDuration: 0.005,
          supportsDTMF: true,
          supportsHolding: true,
          supportsGrouping: false,
          supportsUngrouping: false,
          ringtonePath: 'system_ringtone_default',
        ),
      ),
    );
  } else if (message.data['type'] == 'chat') {
    // For killed apps, if payload doesn't have 'notification', the data-only push won't show a notification
    // unless manually shown here. But typically we send both. 
    // This is a safety fallback.
    if (message.notification == null) {
      // Manual local notification if needed
    }
  }
}
