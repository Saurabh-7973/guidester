import 'package:dashboard/src/screens/comments_screen.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/project_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/board_fakes.dart';

/// Spec §5.6 row 9. A project with a key and no comments must say whether
/// the SDK has ever reached it: that is the difference between "nobody has
/// commented yet" and "the install is not working".
Future<void> _pump(
  WidgetTester tester, {
  required Future<LastLaunch?> Function() lastLaunch,
  VoidCallback? onSetup,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: CommentsScreen(
          repository: FakeRepository(const {}),
          projectTotal: 0,
          lastLaunch: lastLaunch,
          onSetup: onSetup,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a launch was seen: when, and on what', (tester) async {
    await _pump(
      tester,
      lastLaunch: () async => LastLaunch(
        at: DateTime.now().subtract(const Duration(minutes: 3)),
        device: 'A015, Android 16',
      ),
    );
    expect(find.text('No comments left yet'), findsOneWidget);
    expect(
      find.text('Last launch 3 minutes ago on A015, Android 16'),
      findsOneWidget,
    );
  });

  testWidgets('no launch yet: says so, and offers the setup', (tester) async {
    var setups = 0;
    await _pump(tester, lastLaunch: () async => null, onSetup: () => setups++);
    expect(find.textContaining('No launch seen yet'), findsOneWidget);
    await tester.tap(find.text('Open setup'));
    expect(setups, 1);
  });
}
