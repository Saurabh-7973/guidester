import 'package:flutter/semantics.dart';

/// Builds the semantics tree from the first frame instead of on demand.
///
/// Flutter web leaves it off until something asks, and what the browser
/// shows meanwhile is one "Enable accessibility" button: a screen reader user
/// has to find that before anything else on the page exists for them
/// (field test Stage D 5). The cost is a little layout work per frame; the
/// dashboard is not animation-heavy.
SemanticsHandle enableAccessibility() =>
    SemanticsBinding.instance.ensureSemantics();
