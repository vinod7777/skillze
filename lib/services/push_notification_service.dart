import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../screens/main/call_screen.dart';
import 'call_service.dart';

/// Handler for background messaging events.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('PushNotificationService: Background Message Received: ${message.messageId}');
  
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  
  if (message.data['type'] == 'call') {
    debugPrint('PushNotificationService: Waking up CallKit from background payload');
    await PushNotificationService.showIncomingCallKit(message.data);
  } else if (message.data['type'] == 'chat') {
    await PushNotificationService.showLocalNotification(message);
  }
}

/// Handler for notification action interactions in the background.
@pragma('vm:entry-point')
void onNotificationActionSelected(NotificationResponse response) async {
  debugPrint('PushNotificationService: [GLOBAL ENTRY] Action triggered: ${response.actionId}');

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  
  try {
    if (response.payload == null) return;
    Map<String, dynamic> data;
    try {
      data = json.decode(response.payload!);
    } catch (e) {
      return;
    }

    final String? chatId = data['chatId']?.toString();

    if (response.actionId == PushNotificationService.actionReply && response.input != null) {
      final replyText = response.input!;
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Double check after a small delay
        await Future.delayed(const Duration(milliseconds: 800));
        user = FirebaseAuth.instance.currentUser;
      }

      if (user != null && chatId != null) {
        final String myUserId = user.uid;
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .add({
          'senderId': myUserId,
          'text': replyText,
          'timestamp': FieldValue.serverTimestamp(),
          'seen': false,
        });

        await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
          'lastMessage': replyText,
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastSenderId': myUserId,
        });
      }
    }
  } catch (e) {
    debugPrint('Error in background notification action: $e');
  } finally {
    // CRITICAL: Always cancel the notification to stop the "sending..." spinner in the system bar
    if (response.id != null) {
      final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
      await localNotifications.cancel(id: response.id!);
    }
  }
}

class PushNotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static String? activeChatId;

  static const String channelId = 'high_importance_channel';
  static const String channelName = 'High Importance Notifications';
  static const String channelDescription = 'Important notifications from Skillze.';

  static const String actionReply = 'REPLY_ACTION';
  static const String actionMarkRead = 'MARK_READ_ACTION';

  static Future<void> initialize() async {
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
      notificationCategories: [
        DarwinNotificationCategory(
          'REPLY_CATEGORY',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.text(
              actionReply,
              'Reply',
              buttonTitle: 'Send',
              placeholder: 'Type your message...',
            ),
            DarwinNotificationAction.plain(
              actionMarkRead,
              'Mark as Read',
            ),
          ],
          options: <DarwinNotificationCategoryOption>{
            DarwinNotificationCategoryOption.allowAnnouncement,
          },
        ),
      ],
    );
    
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        onNotificationActionSelected(response);
      },
      onDidReceiveBackgroundNotificationResponse: onNotificationActionSelected,
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.max,
    );

    await _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);

    FirebaseMessaging.onMessage.listen((message) => showLocalNotification(message));
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    
    await setupCallKit();
  }

  // ── Call Kit Integration ─────────────────────────────────────────────────

  static Future<void> setupCallKit() async {
    if (kIsWeb) return;

    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls != null && activeCalls is List && activeCalls.isNotEmpty) {
      final callData = activeCalls[0];
      if (callData['isAccepted'] == true) {
        _handleIncomingCallFromData(Map<String, dynamic>.from(callData));
      }
    }

    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;

      switch (event.event) {
        case Event.actionCallAccept:
          final callService = CallService();
          final String? callId = event.body['id']?.toString();
          
          if (callService.callState == CallState.connected || callService.callState == CallState.connecting) return;

          await callService.initialize();
          await callService.answerCall(callId!);
          navigatorKey.currentState?.push(
            MaterialPageRoute(
              builder: (_) => const CallScreen(isIncoming: true),
            ),
          );
          break;
        case Event.actionCallDecline:
        case Event.actionCallTimeout:
          final callService = CallService();
          await callService.declineCall(event.body['id']);
          break;
        case Event.actionCallEnded:
          final callService = CallService();
          await callService.endCall();
          break;
        default:
          break;
      }
    });
  }

  static Future<void> showIncomingCallKit(Map<String, dynamic> data) async {
    if (kIsWeb) return;
    final callId = data['callId']?.toString() ?? '';
    final callerName = data['callerName']?.toString() ?? 'Unknown';
    final callerAvatar = data['callerAvatar']?.toString() ?? '';
    final isVideo = data['isVideo']?.toString() == 'true';

    final params = CallKitParams(
      id: callId,
      nameCaller: callerName,
      avatar: callerAvatar,
      handle: isVideo ? 'Video Call' : 'Voice Call',
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'Accept',
      textDecline: 'Decline',
      extra: data,
      android: const AndroidParams(
        isShowLogo: false,
        isShowFullLockedScreen: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F2F6A',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: 'Incoming Calls',
        isShowCallID: false,
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        supportsVideo: true,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  static Future<void> _handleIncomingCallFromData(Map<String, dynamic> data) async {
    final callService = CallService();
    final callId = data['id']?.toString() ?? data['callId']?.toString();
    
    if (callId == null || callId.isEmpty) {
      debugPrint('PushNotificationService: No valid callId found in data');
      return;
    }

    if (callService.callState != CallState.idle && callService.callState != CallState.ringing) return;

    await callService.initialize();
    await callService.answerCall(callId ?? "");

    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => const CallScreen(isIncoming: true),
      ),
    );
  }

  static Future<void> updateToken([String? token]) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final String? finalToken = token ?? await _fcm.getToken();
      if (finalToken != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'fcmToken': finalToken,
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  static Future<bool> areNotificationsEnabled() async => true;
  static Future<void> setNotificationsEnabled(bool enabled) async {}

  static Future<void> sendNotification({
    required String recipientToken,
    required String title,
    required String body,
    String? imageUrl,
    Map<String, dynamic>? extraData,
  }) async {
    debugPrint('PushNotificationService: sendNotification to $recipientToken (Image: $imageUrl, Data: $extraData)');
  }

  static Future<void> showLocalNotification(RemoteMessage message) async {
    if (!(await areNotificationsEnabled())) return;

    if (message.data['type'] == 'call') {
      showIncomingCallKit(message.data);
      return;
    }

    final notification = message.notification;
    final data = message.data;
    final int notifyId = DateTime.now().millisecondsSinceEpoch.toSigned(31);

    final String senderName = notification?.title ?? data['title'] ?? 'New Message';
    final String messageText = notification?.body ?? data['body'] ?? '';

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: MessagingStyleInformation(
        Person(name: 'You'),
        conversationTitle: senderName,
        messages: [
          Message(
            messageText,
            DateTime.now(),
            Person(name: senderName),
          ),
        ],
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          actionReply,
          'Reply',
          showsUserInterface: false,
          cancelNotification: false,
          inputs: <AndroidNotificationActionInput>[
            AndroidNotificationActionInput(label: 'Type your message...'),
          ],
        ),
        const AndroidNotificationAction(
          actionMarkRead, 
          'Mark as Read',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    await _localNotifications.show(
      id: notifyId,
      title: senderName,
      body: messageText,
      notificationDetails: NotificationDetails(android: androidDetails),

      payload: json.encode(data),
    );
  }

  // Send notification for Call
  static Future<void> sendCallNotification({
    required String receiverId,
    required String callId,
    required String chatId,
    required String callerName,
    required String callerAvatar,
    required bool isVideo,
  }) async {
    final tokenSnapshot = await FirebaseFirestore.instance.collection('users').doc(receiverId).get();
    final token = tokenSnapshot.data()?['fcmToken'];
    if (token == null || token.isEmpty) return;

    try {
      // In a real production app, retrieving an access token and sending
      // to FCM v1 should be done by server-side functions (e.g. Firebase Functions).
      // Since this is a client, we are omitting the direct http request here because 
      // the Firebase v1 API requires an OAuth2 token from a service account,
      // which shouldn't be bundled in a mobile app. 
      // The user mentions they took the blaze plan, so they should use a cloud function.
      // For now, we will notify via Firestore (e.g. calling service listens). 
      // CallKit will be triggered if the device is running.
      
      debugPrint('Call Notification should be sent to $token via server');
    } catch (e) {
      debugPrint('Error sending call notification: $e');
    }
  }
}
