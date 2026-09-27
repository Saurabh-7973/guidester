import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec §3 gives the shell exact geometry. These assert the numbers, not just
/// that something rendered — a shell that draws in the right place but 40px
/// low is the failure this catches.
void main() {
  Widget host({
    ShellTab tab = ShellTab.projects,
    ValueChanged<ShellTab>? onTab,
    VoidCallback? onLogOut,
    Widget? trailing,
    String name = 'sampledeveloper1',
  }) {
    return MaterialApp(
      home: AppShell(
        tab: tab,
        onTabSelected: onTab ?? (_) {},
        userName: name,
        onLogOut: onLogOut ?? () {},
        trailing: trailing,
        child: const SizedBox.shrink(),
      ),
    );
  }

  /// The frames are 1440 x 752; the geometry in §3 is measured against that.
  Future<void> pumpAt1440(WidgetTester tester, Widget app) async {
    tester.view.physicalSize = const Size(1440, 752);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app);
  }

  testWidgets('the page is pure black', (tester) async {
    await pumpAt1440(tester, host());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, T.page);
  });

  testWidgets('the content column is 624 wide and centred', (tester) async {
    await pumpAt1440(tester, host());
    final column = find.ancestor(
      of: find.text('Projects'),
      matching: find.byType(SizedBox),
    );
    final box = tester.getRect(column.last);
    expect(box.width, T.columnWidth);
    // 1440 - 624 = 816, half either side: the frames' x=408.
    expect(box.left, 408);
  });

  testWidgets('the nav tabs sit at y=61', (tester) async {
    await pumpAt1440(tester, host());
    expect(tester.getTopLeft(find.text('Projects')).dy, T.navTop);
  });

  testWidgets('the tabs are one gap apart', (tester) async {
    await pumpAt1440(tester, host());
    final projects = tester.getRect(find.text('Projects'));
    final status = tester.getRect(find.text('Status'));
    final settings = tester.getRect(find.text('Settings'));
    expect(status.left - projects.right, T.navGap);
    expect(settings.left - status.right, T.navGap);
  });

  testWidgets('the active tab carries accent, weight and an underline', (
    tester,
  ) async {
    await pumpAt1440(tester, host());

    final active = tester.widget<Text>(find.text('Projects'));
    expect(active.style!.color, T.accentText);
    expect(active.style!.fontWeight, FontWeight.w600);
    expect(active.style!.fontSize, 14);

    final inactive = tester.widget<Text>(find.text('Settings'));
    expect(inactive.style!.color, T.text3);
    expect(inactive.style!.fontWeight, FontWeight.w400);

    // One 2px accent bar, under the active tab only.
    final bars = tester.widgetList<Container>(find.byType(Container)).where((
      c,
    ) {
      final constraints = c.constraints;
      return constraints?.maxHeight == T.navUnderline &&
          c.color == T.accentText;
    });
    expect(bars, hasLength(1));
  });

  testWidgets('the underline spans its label and nothing more', (tester) async {
    await pumpAt1440(tester, host());
    final label = tester.getRect(find.text('Projects'));
    final bar = tester.getRect(
      find
          .descendant(
            of: find.byType(AppShell),
            matching: find.byWidgetPredicate(
              (w) => w is Container && w.color == T.accentText,
            ),
          )
          .first,
    );
    // A zero-width bar is in the tree and invisible on screen. Assert the
    // painted geometry, not the widget's existence.
    expect(bar.width, label.width);
    expect(bar.height, T.navUnderline);
    expect(bar.left, label.left);
    expect(bar.top, greaterThan(label.bottom));
  });

  testWidgets('selecting a tab reports it', (tester) async {
    ShellTab? picked;
    await pumpAt1440(tester, host(onTab: (t) => picked = t));
    await tester.tap(find.text('Settings'));
    expect(picked, ShellTab.settings);
  });

  testWidgets('the settings tab renders as the active one', (tester) async {
    await pumpAt1440(tester, host(tab: ShellTab.settings));
    expect(
      tester.widget<Text>(find.text('Settings')).style!.color,
      T.accentText,
    );
    expect(tester.widget<Text>(find.text('Projects')).style!.color, T.text3);
  });

  testWidgets('the user chip sits bottom-left at 24,696', (tester) async {
    await pumpAt1440(tester, host());
    final avatar = tester.getRect(find.text('S'));
    expect(avatar.center.dx, T.userChip.dx + T.avatarSize / 2);
    expect(
      tester.getTopLeft(find.text('sampledeveloper1')).dy,
      greaterThanOrEqualTo(T.userChip.dy),
    );
  });

  testWidgets('the chip shows the name and logs out', (tester) async {
    var out = 0;
    await pumpAt1440(tester, host(onLogOut: () => out++));
    expect(find.text('sampledeveloper1'), findsOneWidget);
    await tester.tap(find.text('Log Out'));
    expect(out, 1);
  });

  testWidgets('an empty name still renders a chip', (tester) async {
    await pumpAt1440(tester, host(name: '   '));
    expect(find.text('?'), findsOneWidget);
  });

  testWidgets('the trailing slot ends at the column edge', (tester) async {
    await pumpAt1440(
      tester,
      host(trailing: const SizedBox(width: 100, height: 28, child: Text('x'))),
    );
    // 408 + 624 = 1032, where §3 puts the right edge of `New project`.
    expect(tester.getRect(find.text('x')).right, 408 + T.columnWidth);
  });

  testWidgets('every glyph in the shell is Inter', (tester) async {
    await pumpAt1440(tester, host());
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontFamily, T.family, reason: '"${text.data}"');
    }
  });
}
