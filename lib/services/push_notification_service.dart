import 'dart:async';
import 'package:flutter/material.dart';
import 'package:skillze/screens/main/conversation_screen.dart';
import '../screens/main/user_profile_screen.dart';
import '../screens/main/post_detail_screen.dart';

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

import 'package:shared_preferences/shared_preferences.dart';

class PushNotificationService {
  static const String _notificationsEnabledKey = 'notifications_enabled';
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  static String? activeChatId;

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
          AndroidInitializationSettings('@mipmap/launcher_icon');
      
      const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationClick(response.payload);
        },
      );

      // Create required notification channels for Android
      const List<AndroidNotificationChannel> channels = [
        AndroidNotificationChannel(
          'skillze_high_priority',
          'High Priority',
          description: 'Notifications for urgent updates',
          importance: Importance.max,
          playSound: true,
          showBadge: true,
          enableVibration: true,
        ),
        AndroidNotificationChannel(
          'skillze_messages',
          'Messages',
          description: 'Direct message notifications',
          importance: Importance.max,
          playSound: true,
          showBadge: true,
          enableVibration: true,
        ),
        AndroidNotificationChannel(
          'skillze_notifications',
          'Activity',
          description: 'Notifications for likes, follows, etc.',
          importance: Importance.high,
          playSound: true,
          showBadge: true,
          enableVibration: true,
        ),
      ];

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      for (final channel in channels) {
        await androidPlugin?.createNotificationChannel(channel);
      }
    }

    // 3. Handle Notification Clicks (Background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(jsonEncode(message.data));
    });

    // 4. Handle Notification Clicks (Terminated)
    if (!kIsWeb) {
      FirebaseMessaging.instance.getInitialMessage().then((message) {
        if (message != null) {
          _handleNotificationClick(jsonEncode(message.data));
        }
      });
    }

    // 5. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      if (!(await areNotificationsEnabled())) return;

      // Always show local notification in foreground for better UX consistency
      _showLocalNotification(message);
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
    try {
      // For iOS, the FCM token requires the APNs token to be populated first.
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        String? apnsToken = await _messaging.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('Waiting for APNs token...');
          await Future.delayed(const Duration(seconds: 3));
          apnsToken = await _messaging.getAPNSToken();
        }
      }

      final fcmToken = token ?? await _messaging.getToken();
      if (fcmToken != null) {
        debugPrint('\n======================================================');
        debugPrint('FCM TOKEN FOR TESTING:');
        debugPrint(fcmToken);
        debugPrint('======================================================\n');
        await _saveToken(fcmToken);
      } else {
        debugPrint('FCM TOKEN: getToken() returned null.');
      }
    } catch (e) {
      debugPrint('\n======================================================');
      debugPrint('FCM TOKEN FETCH FAILED:');
      debugPrint(e.toString());
      debugPrint('Please check if Google Play Services are available and updated on this device/emulator.');
      debugPrint('======================================================\n');
    }
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
      final type = data['type'];
      
      if (type == 'chat' || type == 'message') {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ConversationScreen(
              chatId: data['chatId'],
              otherUserId: data['senderId'] ?? data['otherUserId'],
              otherUserName: data['senderName'] ?? data['otherUserName'] ?? 'User',
            ),
          ),
        );
      } else if (type == 'follow') {
        final userId = data['senderId'] as String?;
        if (userId != null) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)),
          );
        }
      } else if (data['postId'] != null && data['postId'].toString().isNotEmpty) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(postId: data['postId'].toString()),
          ),
        );
      }
    } catch (e) {
      debugPrint('Notification handle error: $e');
    }
  }

  static AutoRefreshingAuthClient? _authClient;

  static Future<String> _getAccessToken() async {
    if (kIsWeb) return "";
    try {
      if (_authClient != null && _authClient!.credentials.accessToken.expiry.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
        return _authClient!.credentials.accessToken.data;
      }

      final serviceAccountJson = await rootBundle.loadString(
        'assets/service-account.json',
      );
      final accountCredentials = ServiceAccountCredentials.fromJson(
        serviceAccountJson,
      );
      final scopes = ['https://www.googleapis.com/auth/cloud-platform'];
      _authClient = await clientViaServiceAccount(accountCredentials, scopes);
      return _authClient!.credentials.accessToken.data;
    } catch (e) {
      debugPrint("Error getting access token: $e");
      return "";
    }
  }

  static Future<void> sendNotification({
    required String recipientToken,
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? extraData,
  }) async {
    try {
      final accessToken = await _getAccessToken();
      const projectID = 'feed-609dd';
      
      // Determine correct channel for Android system handling
      String channelId = 'skillze_notifications';
      final type = extraData?['type'];
      if (type == 'chat' || type == 'message' || type == 'mention_chat') {
        channelId = 'skillze_messages';
      }

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
            'notification': {
              'title': title,
              'body': body,
              if (imageUrl != null && imageUrl.isNotEmpty) 'image': imageUrl,
            },
            'data': extraData?.map((key, value) => MapEntry(key, value.toString())) ?? {},
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': channelId,
                'sound': 'default',
                'notification_priority': 'PRIORITY_MAX',
                'icon': 'launcher_icon',
                'color': '#2196F3',
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              },
            },
            'apns': {
              'payload': {
                'aps': {
                  'alert': {
                    'title': title,
                    'body': body,
                  },
                  'sound': 'default',
                  'badge': 1,
                  'mutable-content': 1,
                  'category': 'SKILLZE_NOTIFICATION',
                },
              },
              'fcm_options': {
                if (imageUrl != null && imageUrl.isNotEmpty) 'image': imageUrl,
              },
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
      // 1. Ask for standard OS permission (Android 13+)
      await [Permission.notification].request();

      // 2. Explicit Firebase permission request (Required for iOS APNs)
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      // 3. Configure foreground presentation options (for Apple platforms)
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'fcmToken': token, // Last known token for single-send cases
        'fcmTokens': FieldValue.arrayUnion([token]), // All devices
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  static Future<Uint8List?> _downloadFile(String url) async {
    try {
      final http.Response response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      debugPrint('Error downloading file: $e');
      return null;
    }
  }

  // Memory cache to collect recent messages from the same person for a merged notification view.
  static final Map<String, List<Message>> _chatMessageCache = {};

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (kIsWeb) return;

    final data = message.data;
    final chatId = data['chatId'];
    
    // Don't show redundant notifications if we're already in the chat
    if (chatId != null && chatId.isNotEmpty && chatId == activeChatId) {
      debugPrint('Skipping local notification for active chat: $chatId');
      return;
    }

    final type = data['type'];
    final senderName = data['senderName'] ?? message.notification?.title ?? 'Skillze';
    final senderPhoto = data['senderPhoto'] ?? data['image'] ?? message.notification?.android?.imageUrl;
    final text = message.notification?.body ?? data['message'] ?? '';


    AndroidNotificationDetails? androidDetails;
    DarwinNotificationDetails? iosDetails;

    // 1. Download images for rich display
    Uint8List? largeIconBytes;
    if (senderPhoto != null && senderPhoto.isNotEmpty) {
      largeIconBytes = await _downloadFile(senderPhoto);
    }

    int notificationId = message.hashCode;

    // 2. Build Android Details
    if (type == 'chat' || type == 'message') {
      final String safeChatId = chatId ?? 'unknown_chat';
      notificationId = safeChatId.hashCode;

      final person = Person(
        name: senderName,
        key: data['senderId'] ?? 'sender',
        icon: largeIconBytes != null ? ByteArrayAndroidIcon(largeIconBytes) : null,
      );

      // Add message to cache to merge notifications visually
      _chatMessageCache.putIfAbsent(safeChatId, () => []);
      _chatMessageCache[safeChatId]!.add(Message(text, DateTime.now(), person));
      if (_chatMessageCache[safeChatId]!.length > 5) {
        _chatMessageCache[safeChatId]!.removeAt(0);
      }

      androidDetails = AndroidNotificationDetails(
        'skillze_messages',
        'Direct Messages',
        channelDescription: 'Real-time chat notifications',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.message,
        groupKey: safeChatId,
        setAsGroupSummary: true,
        styleInformation: MessagingStyleInformation(
          person,
          messages: _chatMessageCache[safeChatId]!,
          groupConversation: false,
        ),
      );
    } else {
      // General notification or rich image notification
      Uint8List? bigPictureBytes;
      final String? postImageUrl = data['postImage'] ?? data['imageUrl'];
      if (postImageUrl != null && postImageUrl.isNotEmpty) {
        bigPictureBytes = await _downloadFile(postImageUrl);
      }

      androidDetails = AndroidNotificationDetails(
        'skillze_notifications',
        'App Notifications',
        channelDescription: 'Updates for likes, mentions, and activity',
        importance: Importance.high,
        priority: Priority.high,
        largeIcon: largeIconBytes != null ? ByteArrayAndroidBitmap(largeIconBytes) : null,
        groupKey: 'activity',
        styleInformation: bigPictureBytes != null 
          ? BigPictureStyleInformation(
              ByteArrayAndroidBitmap(bigPictureBytes),
              largeIcon: largeIconBytes != null ? ByteArrayAndroidBitmap(largeIconBytes) : null,
              contentTitle: senderName,
              summaryText: text,
            )
          : null,
      );
    }

    // 3. Build iOS Details
    iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'SKILLZE_NOTIFICATION',
      threadIdentifier: chatId, // Apples grouping mechanism
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      id: notificationId,
      title: senderName,
      body: text,
      notificationDetails: details,
      payload: jsonEncode(data),
    );
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // For data-only messages in background, we must show a local notification
  // For messages with 'notification' block, the OS shows it automatically, 
  // but if we want rich style, we handles it here too.
  // Note: On some Android versions, this might show double if not handled, 
  // but for 'data' only it's the only way.
  if (message.data.isNotEmpty) {
     await PushNotificationService._showLocalNotification(message);
  }
}
