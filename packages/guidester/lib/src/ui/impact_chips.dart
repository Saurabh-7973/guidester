import 'package:flutter/material.dart';

import '../impact.dart';
import '../theme/tokens.dart';

/// One row, three chips: Blocked / Annoying / Cosmetic.
///
/// Always exactly one selected — [Impact.fallback] until the tester says
/// otherwise. Tapping the selected chip does nothing, unlike the type chips it
/// replaces: with a default there is no "none" to return to, and a row that can
/// empty itself would put a null back on the wire for no gain.
class GuidesterImpactChips extends StatelessWidget {
  const GuidesterImpactChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final Impact selected;
  final ValueChanged<Impact> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Could you keep using the app?',
      child: Row(
        children: [
          for (final impact in Impact.values) ...[
            _Chip(
              impact: impact,
              isSelected: impact == selected,
              onTap: enabled ? () => onChanged(impact) : null,
            ),
            if (impact != Impact.values.last) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.impact,
    required this.isSelected,
    required this.onTap,
  });

  final Impact impact;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Selected is a filled accent chip with a white label; at rest it is
    // --surface-2 with a --chrome-border edge, because the row floats over an
    // unknown host background and cannot rely on contrast for its shape.
    final background = isSelected ? GT.accent : GT.surface2;
    final foreground = isSelected ? GT.text1 : GT.text3;

    return Semantics(
      button: true,
      selected: isSelected,
      label: impact.label,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(GT.rPill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GT.rPill),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(GT.rPill),
              border: Border.all(
                color: isSelected ? GT.accent : GT.chromeBorder,
              ),
            ),
            child: Text(
              impact.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
