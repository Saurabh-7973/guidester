import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/context_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// 27 Sep audit: the panel read "text_scale_factor 2.00" and
/// "screen_w 330.00". It still shows every key; it now reads like a sentence.
void main() {
  Future<void> pump(WidgetTester tester, Map<String, dynamic> context) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ContextPanel(
                comment: testComment(id: '1', body: 'b', context: context),
              ),
            ),
          ),
        ),
      );

  testWidgets('known keys read as words, numbers without padding', (
    tester,
  ) async {
    await pump(tester, {
      'text_scale_factor': 2.0,
      'screen_w': 330.0,
      'device_pixel_ratio': 2.625,
      'is_physical_device': false,
    });

    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('2×'), findsOneWidget);
    expect(find.text('Screen width'), findsOneWidget);
    expect(find.text('330'), findsOneWidget);
    expect(find.text('2.63×'), findsOneWidget);
    expect(find.text('Physical device'), findsOneWidget);
    expect(find.text('no (emulator or simulator)'), findsOneWidget);
    expect(find.textContaining('_'), findsNothing);
    expect(find.textContaining('.00'), findsNothing);
  });

  testWidgets('a key added later still shows, spaced', (tester) async {
    await pump(tester, {'battery_level': 0.5});

    expect(find.text('Battery level'), findsOneWidget);
    expect(find.text('0.5'), findsOneWidget);
  });
}
