import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/input_formatters.dart';
import '../theme/app_theme.dart';

class CleanMultilineInput extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxConsecutiveNewlines;
  final void Function(String)? onChanged;
  final TextStyle? style;
  final bool autofocus;
  final bool enableHapticFeedback;
  final EdgeInsetsGeometry? padding;
  final bool showBorder;
  final int minLines;

  const CleanMultilineInput({
    super.key,
    required this.controller,
    this.hintText = 'What\'s on your mind? (use @ to mention)',
    this.maxConsecutiveNewlines = 2,
    this.onChanged,
    this.style,
    this.autofocus = false,
    this.enableHapticFeedback = true,
    this.padding,
    this.showBorder = true,
    this.minLines = 4,
  });

  /// Normalizes content by trimming leading/trailing whitespace and ensuring no excessive spacing.
  /// Use this before submitting the content to the backend.
  static String normalize(String content, {int maxConsecutiveNewlines = 2}) {
    String normalized = content.trim();
    final regExp = RegExp('\n{${maxConsecutiveNewlines + 1},}');
    normalized = normalized.replaceAll(regExp, '\n' * maxConsecutiveNewlines);
    return normalized;
  }

  @override
  State<CleanMultilineInput> createState() => _CleanMultilineInputState();
}

class _CleanMultilineInputState extends State<CleanMultilineInput> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    setState(() {
      _isFocused = _focusNode.hasFocus;
    });
  }

  void _onLimitReached() {
    if (widget.enableHapticFeedback) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: widget.showBorder ? BoxDecoration(
        color: context.surfaceLightColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          if (_isFocused)
            BoxShadow(
              color: context.primary.withOpacity(0.08),
              blurRadius: 15,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
        ],
      ) : const BoxDecoration(),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        maxLines: null,
        minLines: widget.minLines,
        style: widget.style ?? TextStyle(
          fontSize: 16,
          color: context.textHigh,
          height: 1.5,
          letterSpacing: 0.2,
        ),
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [
          CleanFormattingFormatter(
            maxConsecutiveNewlines: widget.maxConsecutiveNewlines,
            preventLeadingWhitespace: true,
            onLimitReached: _onLimitReached,
          ),
        ],
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            color: context.textLow,
            fontSize: 15,
            fontWeight: FontWeight.w400,
          ),
          contentPadding: widget.padding ?? const EdgeInsets.all(20),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
        ),
      ),
    );
  }
}
