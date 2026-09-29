import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The screenshot exactly as it will be sent, full screen.
///
/// Opened from the composer's thumbnail. It shows the redacted image — the
/// same bytes the payload carries — so a tester, and a developer trying the
/// build, can see that a hidden area really is covered before anything leaves
/// the device.
class GuidesterScreenshotPreview extends StatelessWidget {
  const GuidesterScreenshotPreview({
    super.key,
    required this.screenshot,
    required this.onClose,
  });

  final Uint8List screenshot;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Material(
      color: GT.page,
      child: Padding(
        padding: EdgeInsets.only(
          top: media.padding.top + 8,
          bottom: media.padding.bottom + 8,
        ),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'This is what will be sent',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: GT.text1,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Close the screenshot',
                  child: IconButton(
                    key: const ValueKey('guidester-preview-close'),
                    icon: const Icon(Icons.close, color: GT.text1),
                    onPressed: onClose,
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  image: true,
                  label: 'Screenshot that will be sent with this comment',
                  child: Image.memory(
                    screenshot,
                    key: const ValueKey('guidester-preview-image'),
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
