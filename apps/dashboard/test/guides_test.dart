import 'package:dashboard/src/models/comment_status.dart';
import 'package:dashboard/src/theme/app_theme.dart';
import 'package:dashboard/src/widgets/project_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The frames' learn links pointed at videos that do not exist. Each now
/// opens a short guide with steps that are true of the SDK today.
Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ProjectHeader(
          projectName: 'Snapdrop',
          createdBy: 'You',
          collaborators: 0,
          commentCount: 0,
          status: CommentStatus.open,
          counts: const {},
          onStatusSelected: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('How to leave a comment opens its steps; Esc closes', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.text('How to leave a comment'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-sheet')), findsOneWidget);
    expect(
      find.textContaining('Blocked, Annoying or Cosmetic'),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('guide-sheet')), findsNothing);
  });

  testWidgets('sharing is about testers, and says they need no account', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('How to share with clients'), findsNothing);
    await tester.tap(find.text('How to invite testers'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GUIDESTER_KEY'), findsOneWidget);
    expect(find.textContaining('no account'), findsOneWidget);
  });
}
