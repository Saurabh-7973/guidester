import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Shown while comment mode is armed, before a pin is placed.
class GuidesterModeBar extends StatelessWidget {
  const GuidesterModeBar({super.key, required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          'Comment mode active. Tap anywhere on the screen to place a comment.',
      child: Material(
        // The pill IS the mode signal, so it carries the accent rather than a
        // neutral surface: nothing else on screen says comment mode is armed.
        color: GT.accent,
        elevation: 4,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Flexible(
                child: Text(
                  'Tap anywhere to comment',
                  style: TextStyle(color: GT.text1, fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Exit comment mode',
                child: IconButton(
                  icon: const Icon(Icons.close, color: GT.text2, size: 20),
                  onPressed: onCancel,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The accent at a third alpha — the pin's glow, so it reads against both a
/// light and a dark host screen. Derived from the token, never a second hex.
final Color _pinGlow = GT.accent.withValues(alpha: 0.33);

/// The marker drawn where the tester tapped.
class GuidesterPin extends StatelessWidget {
  const GuidesterPin({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Comment location marker',
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: GT.accent,
          shape: BoxShape.circle,
          border: Border.all(color: GT.text1, width: 3),
          boxShadow: [
            BoxShadow(color: _pinGlow, blurRadius: 8, spreadRadius: 2),
          ],
        ),
      ),
    );
  }
}
