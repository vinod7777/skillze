import 'package:flutter/services.dart';

/// A [TextInputFormatter] that prevents excessive consecutive newlines and
/// handles dynamic normalization of whitespace.
class CleanFormattingFormatter extends TextInputFormatter {
  final int maxConsecutiveNewlines;
  final VoidCallback? onLimitReached;
  final bool preventLeadingWhitespace;

  CleanFormattingFormatter({
    this.maxConsecutiveNewlines = 2,
    this.onLimitReached,
    this.preventLeadingWhitespace = true,
  });

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;
    int offset = newValue.selection.baseOffset;

    // 1. Prevent leading whitespace/newlines if configured
    if (preventLeadingWhitespace && text.isNotEmpty) {
      // If the change added a leading whitespace
      if (text.startsWith(RegExp(r'[\s\n]'))) {
        // Find how many leading whitespace chars there are
        final leadingMatch = RegExp(r'^[\s\n]+').firstMatch(text);
        if (leadingMatch != null) {
          int leadingLength = leadingMatch.end;
          text = text.substring(leadingLength);
          offset = (offset - leadingLength).clamp(0, text.length);
          
          if (onLimitReached != null) {
            onLimitReached!();
          }
        }
      }
    }

    // 2. Limit consecutive newlines
    final String pattern = '\n' * (maxConsecutiveNewlines + 1);
    final regExp = RegExp('\n{${maxConsecutiveNewlines + 1},}');
    
    if (text.contains(pattern)) {
      onLimitReached?.call();
      
      String formattedText = text.replaceAll(regExp, '\n' * maxConsecutiveNewlines);
      
      // Accurate cursor adjustment
      int removedBeforeCursor = 0;
      Iterable<Match> matches = regExp.allMatches(text);
      for (var match in matches) {
        if (match.start < offset) {
          int matchLength = match.end - match.start;
          int extra = matchLength - maxConsecutiveNewlines;
          
          // If the cursor was inside the match
          if (match.end > offset) {
            removedBeforeCursor += (offset - match.start - maxConsecutiveNewlines).clamp(0, extra);
          } else {
            removedBeforeCursor += extra;
          }
        }
      }
      
      text = formattedText;
      offset = (offset - removedBeforeCursor).clamp(0, text.length);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
