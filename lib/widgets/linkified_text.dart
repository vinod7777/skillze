import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../screens/main/search_screen.dart';
import '../../theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final Function(String)? onMentionTap;
  final TextStyle? linkStyle;
  final String? highlightText;
  final TextStyle? highlightStyle;

  const LinkifiedText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow,
    this.onMentionTap,
    this.linkStyle,
    this.highlightText,
    this.highlightStyle,
  });

  static List<InlineSpan> parse(
    String text,
    BuildContext context, {
    TextStyle? linkStyle,
    Function(String)? onMentionTap,
    String? highlightText,
    TextStyle? highlightStyle,
  }) {
    if (text.isEmpty) return [];

    // Group 1: Highlight (always present as a group, even if it never matches)
    String highlightPattern = highlightText != null && highlightText.isNotEmpty
        ? "(${RegExp.escape(highlightText)})"
        : r"($^)"; // $^ never matches anything, r"" prevents interpolation of $
    
    final RegExp exp = RegExp(
      "$highlightPattern|([@#][\\w\\d_]+)|((?:https?://|www\\.)[^\\s]+)",
      caseSensitive: false,
    );
    final Iterable<RegExpMatch> matches = exp.allMatches(text);

    final List<InlineSpan> spans = [];
    int lastIndex = 0;

    for (final match in matches) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }

      final String matchText = match.group(0)!;
      
      // Check which group matched
      final bool isHighlight = highlightText != null && 
          highlightText.isNotEmpty && 
          match.group(1) != null;
      
      if (isHighlight) {
        spans.add(
          TextSpan(
            text: matchText,
            style: highlightStyle ??
                TextStyle(
                  backgroundColor: Colors.yellow.withOpacity(0.3),
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
          ),
        );
      } else {
        final bool isMention = match.group(2)?.startsWith('@') ?? false;
        final bool isHashtag = match.group(2)?.startsWith('#') ?? false;
        final bool isUrl = match.group(3) != null;

        spans.add(
          TextSpan(
            text: matchText,
            style: linkStyle ??
                TextStyle(
                  color: context.primary,
                  fontWeight: isUrl ? FontWeight.normal : FontWeight.bold,
                  decoration:
                      isUrl ? TextDecoration.underline : TextDecoration.none,
                ),
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (isUrl) {
                  String urlStr = matchText;
                  if (urlStr.toLowerCase().startsWith('www.')) {
                    urlStr = 'https://$urlStr';
                  }
                  final uri = Uri.tryParse(urlStr);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  }
                } else if (isHashtag) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          SearchScreen(initialSearchQuery: matchText.substring(1)),
                    ),
                  );
                } else if (isMention) {
                  if (onMentionTap != null) {
                    onMentionTap(matchText.substring(1));
                  }
                }
              },
          ),
        );
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
      text: TextSpan(
        style: style ?? TextStyle(color: context.textHigh, fontSize: 14),
        children: parse(
          text,
          context,
          linkStyle: linkStyle,
          onMentionTap: onMentionTap,
          highlightText: highlightText,
          highlightStyle: highlightStyle,
        ),
      ),
    );
  }
}
