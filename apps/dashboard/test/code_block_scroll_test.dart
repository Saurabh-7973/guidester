import 'package:dashboard/src/screens/onboarding_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// First real walk of the quick start (27 Sep): a key running past the edge of
/// the snippet read as a broken box, because nothing showed it scrolls.
void main() {
  testWidgets('a snippet wider than its box shows a scrollbar', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: ValueKey('shot'),
              child: CodeBlock(
                width: 240,
                copyable: true,
                code:
                    "Guidester.init(\n  apiKey: 'gd_live_0123456789abcdef"
                    "0123456789abcdef0123456789ab4f2a',\n);",
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollbar = find.byType(RawScrollbar);
    expect(scrollbar, findsOneWidget);
    expect(tester.widget<RawScrollbar>(scrollbar).thumbVisibility, isTrue);

    final position = tester
        .state<ScrollableState>(
          find
              .descendant(of: scrollbar, matching: find.byType(Scrollable))
              .first,
        )
        .position;
    expect(
      position.maxScrollExtent,
      greaterThan(0),
      reason: 'the key runs past the box, so there is somewhere to scroll',
    );
  });
}
