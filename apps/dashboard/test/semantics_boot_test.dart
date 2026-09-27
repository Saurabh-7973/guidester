import 'package:dashboard/src/config/accessibility.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stage D 5 (25 Sep): the browser showed no accessibility tree, only an
/// "Enable accessibility" button, because Flutter web builds semantics on
/// demand. A screen reader user should not have to find that button first.
void main() {
  testWidgets('semantics are on from the first frame', (tester) async {
    final handle = enableAccessibility();
    expect(SemanticsBinding.instance.semanticsEnabled, isTrue);
    handle.dispose();
  });
}
