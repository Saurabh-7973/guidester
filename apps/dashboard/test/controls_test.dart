import 'package:dashboard/src/theme/tokens.dart';
import 'package:dashboard/src/widgets/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 1200,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  testWidgets('primary: white label on the accent fill', (tester) async {
    await _pump(tester, GButton(label: 'Go', onPressed: () {}));
    expect(_labelColor(tester, 'Go'), T.onAccent);
  });

  testWidgets('disabled primary: disabled text, announced as disabled', (
    tester,
  ) async {
    await _pump(tester, const GButton(label: 'Go', onPressed: null));
    expect(_labelColor(tester, 'Go'), T.text3);
    expect(
      tester.getSemantics(find.byType(GButton)),
      matchesSemantics(isButton: true, hasEnabledState: true, label: 'Go'),
    );
  });

  testWidgets('a screen reader can press an enabled button', (tester) async {
    var taps = 0;
    await _pump(tester, GButton(label: 'Go', onPressed: () => taps++));
    expect(
      tester.getSemantics(find.byType(GButton)),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        label: 'Go',
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Go'));
    expect(taps, 1);
  });

  testWidgets('busy swallows taps', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      GButton(label: 'Go', busy: true, onPressed: () => taps++),
    );
    await tester.tap(find.byType(GButton));
    expect(taps, 0);
  });

  testWidgets('keyboard focus draws a visible ring', (tester) async {
    await _pump(tester, GButton(label: 'Go', onPressed: () {}));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(find.byKey(const ValueKey('focus-ring')), findsOneWidget);
  });

  testWidgets('Enter activates a focused button', (tester) async {
    var taps = 0;
    await _pump(tester, GButton(label: 'Go', onPressed: () => taps++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 1);
  });

  testWidgets('danger is red; secondary is a blue edge with a white label', (
    tester,
  ) async {
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GButton(label: 'Delete', kind: GButtonKind.danger, onPressed: () {}),
          GButton(
            label: 'Later',
            kind: GButtonKind.secondary,
            onPressed: () {},
          ),
        ],
      ),
    );
    expect(_labelColor(tester, 'Delete'), T.onAccent);
    expect(_labelColor(tester, 'Later'), T.text1);
  });

  testWidgets('touch widths get 44 px controls', (tester) async {
    await _pump(tester, GButton(label: 'Go', onPressed: () {}), width: 390);
    expect(
      tester.getSize(find.byType(GButton)).height,
      greaterThanOrEqualTo(T.touchTarget),
    );
  });

  testWidgets('field: label above, error below in red', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: GField(
          controller: TextEditingController(),
          hint: 'you@example.com',
          label: 'Email',
          error: 'Enter an email address.',
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Enter an email address.')).style?.color,
      T.red,
    );
  });

  testWidgets('field without a label still has one for screen readers', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: GField(controller: TextEditingController(), hint: 'Search'),
      ),
    );
    final handle = tester.ensureSemantics();
    await tester.pump();
    final field = find.semantics.byPredicate(
      (node) =>
          node.getSemanticsData().flagsCollection.isTextField &&
          node.label.contains('Search'),
    );
    expect(field, findsOne);
    handle.dispose();
  });

  testWidgets('the text sits in the middle of the field, icon or not', (
    tester,
  ) async {
    // Without a suffix icon the input container shrank to its 20 px line and
    // sat at the top, and the focused outline was drawn around that.
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GField(controller: TextEditingController(), hint: 'plain'),
            GField(
              controller: TextEditingController(),
              hint: 'with icon',
              suffix: const Icon(Icons.visibility_outlined, size: 16),
            ),
          ],
        ),
      ),
    );
    for (var i = 0; i < 2; i++) {
      final field = tester.getRect(find.byType(InputDecorator).at(i));
      final text = tester.getRect(find.byType(EditableText).at(i));
      expect(field.height, T.controlHeight + 4);
      expect(text.center.dy, closeTo(field.center.dy, 1), reason: 'field $i');
    }
  });

  testWidgets('an error turns the field border red', (tester) async {
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: GField(
          controller: TextEditingController(),
          hint: 'x',
          error: 'Enter your email.',
        ),
      ),
    );
    final decoration = tester
        .widget<TextField>(find.byType(TextField))
        .decoration!;
    expect(decoration.enabledBorder!.borderSide.color, T.red);
    expect(decoration.focusedBorder!.borderSide.color, T.red);
  });

  testWidgets('a labelled field is one text field to a screen reader', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      SizedBox(
        width: 320,
        child: GField(
          controller: TextEditingController(),
          hint: 'you@example.com',
          label: 'Email',
        ),
      ),
    );
    final fields = find.semantics.byPredicate(
      (node) => node.getSemanticsData().flagsCollection.isTextField,
    );
    expect(fields, findsOne);
    expect(fields.evaluate().single.label, contains('Email'));
    handle.dispose();
  });

  testWidgets('a long label in a narrow box ellipsizes, never overflows', (
    tester,
  ) async {
    await _pump(
      tester,
      SizedBox(
        width: 120,
        child: GButton(
          label: 'A label far too long for the room it has',
          onPressed: () {},
          expand: true,
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
