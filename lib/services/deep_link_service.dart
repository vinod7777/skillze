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
    // Handle web links: https://skillze.app/post/abc_123
    if ((uri.scheme == 'http' || uri.scheme == 'https') && uri.host == 'skillze.app') {
      if (uri.path.startsWith('/post/')) {
        final postId = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
        if (postId != null && postId != 'post') {
          _navigateToPost(navigatorKey, postId);
        }
      }
    } 
    // Handle custom scheme: skillze://post?id=abc_123
    else if (uri.scheme == 'skillze' && uri.host == 'post') {
      final postId = uri.queryParameters['id'];
      if (postId != null) {
        _navigateToPost(navigatorKey, postId);
      }
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
    // Return a dual-link message: a clickable HTTPS one for apps like WhatsApp,
    // and a direct Skillze scheme link that forces the app to open.
    return 'Check out this post on Skillze: https://skillze.app/post/$postId\n\nDirect App Open: skillze://post?id=$postId';
  }

  static void dispose() {
    _linkSubscription?.cancel();
  }
}
