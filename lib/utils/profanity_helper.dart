import 'package:flutter/material.dart';

void showProfanityWarning(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Unparliamentary language detected. Please modify your text.'),
      backgroundColor: Colors.redAccent,
      duration: Duration(seconds: 3),
    ),
  );
}
