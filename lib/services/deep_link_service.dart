import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import '../screens/main/post_detail_screen.dart';

class DeepLinkService {
  static final AppLinks _appLinks = AppLinks();
  static StreamSubscription<Uri>? _linkSubscription;

  static void initialize(GlobalKey<NavigatorState> navigatorKey) {
    // 1. Handle deep link when the app is already open (or in background)
    _linkSubscription = _appLinks.uriLinkStream.listen((Uri uri) {
      _handleLink(navigatorKey, uri);
    }, onError: (err) {
      debugPrint('Deep Link Error: $err');
    });

    // 2. Handle deep link when the app is initially launched
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleLink(navigatorKey, uri);
      }
    });
  }

  static void _handleLink(GlobalKey<NavigatorState> navigatorKey, Uri uri) {
    debugPrint('Received Deep Link: $uri');
    
    // Example Link: skillze://post?id=abc_123 or https://skillze.app/post/abc_123
    if (uri.scheme == 'skillze' && uri.host == 'post') {
      final postId = uri.queryParameters['id'];
      if (postId != null) {
        _navigateToPost(navigatorKey, postId);
      }
    } else if (uri.path.startsWith('/post/')) {
      final postId = uri.pathSegments.last;
      _navigateToPost(navigatorKey, postId);
    }
  }

  static void _navigateToPost(GlobalKey<NavigatorState> navigatorKey, String postId) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(postId: postId),
      ),
    );
  }

  static String generatePostLink(String postId) {
    // For simplicity, we use the custom scheme skillze://post?id=POST_ID
    return 'skillze://post?id=$postId';
  }

  static void dispose() {
    _linkSubscription?.cancel();
  }
}
