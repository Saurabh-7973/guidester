import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The persistent entry point. Fixed bottom-right for v0.
///
/// Sits outside the RepaintBoundary, so it never lands in a screenshot.
class GuidesterBubble extends StatelessWidget {
  const GuidesterBubble({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Send feedback',
      hint: 'Opens comment mode so you can tap anywhere to leave a comment',
      child: Material(
        color: GT.accent,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 52,
            height: 52,
            child: Icon(Icons.chat_bubble_outline, color: GT.text1, size: 24),
          ),
        ),
      ),
    );
  }
}
