import 'package:flutter/material.dart';

void showProfanityWarning(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Unparliamentary language detected. Please modify your text.'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(label: 'Close', onPressed: () {}),
    ),
  );
}
