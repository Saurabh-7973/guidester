@Tags(['golden'])
library;

import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the shell at the frames' own 1440 x 752 and pins it to a golden.
///
/// Regenerate deliberately, never to make a red test go green:
///   flutter test --update-goldens test/app_shell_golden_test.dart
void main() {
  testWidgets('the shell at 1440', (tester) async {
    tester.view.physicalSize = const Size(1440, 752);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: AppShell(
          tab: ShellTab.projects,
          onTabSelected: (_) {},
          userName: 'sampledeveloper1',
          onLogOut: () {},
          // §3 puts `New project` here. The button itself is Block C; this is
          // the slot, drawn with the spec's control geometry so the golden
          // shows the shell holding real content rather than a gap.
          trailing: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: T.accent,
              borderRadius: BorderRadius.circular(T.rControl),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 14, color: T.text1),
                SizedBox(width: 6),
                Text('New project', style: T.supporting),
              ],
            ),
          ),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AppShell),
      matchesGoldenFile('goldens/app_shell_1440.png'),
    );
  });
}
