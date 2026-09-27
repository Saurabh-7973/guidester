import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The two top-level destinations (spec §3, nav tabs at y=61).
enum ShellTab {
  projects('Projects'),
  status('Status'),
  settings('Settings');

  const ShellTab(this.label);

  final String label;
}

/// The app shell: black page, the centred 624px column, the nav tabs, and the
/// bottom-left user chip. Spec §3 — Block A.
///
/// It owns chrome and nothing else. Screens hand it a [child]; the shell never
/// knows what a comment or a project is.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.tab,
    required this.onTabSelected,
    required this.userName,
    required this.onLogOut,
    this.trailing,
    this.fullWidth = false,
    required this.child,
  });

  final ShellTab tab;
  final ValueChanged<ShellTab> onTabSelected;

  /// Shown beside the avatar in the user chip.
  final String userName;
  final VoidCallback onLogOut;

  /// Right-aligned in the nav row, ending at the column's right edge — where
  /// §3 puts `New project`. The shell reserves the slot; the screen fills it.
  final Widget? trailing;

  final Widget child;

  /// Lets [child] use the window's width instead of the 624px column. The nav
  /// row stays in the column.
  ///
  /// Triage needs it. Inside the column the comments screen always took its
  /// phone layout, even on a 1493px window, and 22 of 27 comments were out of
  /// reach (found 25 Sep).
  final bool fullWidth;

  /// Clears the user chip, which sits outside the column at the bottom left.
  static const double _wideFrom = 1100;

  @override
  Widget build(BuildContext context) {
    if (fullWidth) {
      final size = MediaQuery.sizeOf(context);
      final wide = size.width >= _wideFrom;
      // The board (Home (8)) needs every column it can get, so the chip does
      // not keep a 240 px gutter down the left for itself: it moves to the
      // top right, beside the nav, where it covers nothing.
      return Scaffold(
        backgroundColor: T.page,
        body: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: T.navTop),
                Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: T.columnWidth,
                    child: _NavRow(
                      tab: tab,
                      onTabSelected: onTabSelected,
                      trailing: trailing,
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
                    child: child,
                  ),
                ),
              ],
            ),
            Positioned(
              right: wide ? 24 : 16,
              top: 16,
              child: _UserChip(name: userName, onLogOut: onLogOut),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: T.page,
      body: Stack(
        children: [
          // The column is centred rather than pinned to x=408, so it stays
          // centred at widths other than the 1440 the frames were drawn at.
          // At 1440 the two are the same position.
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: T.columnWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: T.navTop),
                  _NavRow(
                    tab: tab,
                    onTabSelected: onTabSelected,
                    trailing: trailing,
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
          Positioned(
            left: T.userChip.dx,
            bottom: T.userChipBottom,
            child: _UserChip(name: userName, onLogOut: onLogOut),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.tab,
    required this.onTabSelected,
    required this.trailing,
  });

  final ShellTab tab;
  final ValueChanged<ShellTab> onTabSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in ShellTab.values) ...[
          _NavTab(tab: t, active: t == tab, onTap: () => onTabSelected(t)),
          // Gap after every tab but the last.
          if (t != ShellTab.values.last) const SizedBox(width: T.navGap),
        ],
        const Spacer(),
        ?trailing,
      ],
    );
  }
}

/// Active state is carried three ways: `--accent-text`, weight 600, and the
/// 2px underline. Colour alone would fail anyone who cannot see the
/// difference.
///
/// The label and underline take `--accent-text`, not `--accent`: `--accent` is
/// a fill colour and reads too dark as a glyph on pure black.
class _NavTab extends StatelessWidget {
  const _NavTab({required this.tab, required this.active, required this.onTap});

  final ShellTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      tab.label,
      style: T.ui.copyWith(
        color: active ? T.accentText : T.text3,
        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
      ),
    );

    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        // The underline hugs the label, so no padding may widen it.
        //
        // IntrinsicWidth is load-bearing: inside a Row the column is given
        // unbounded width, so a bare `stretch` cannot resolve and a bare
        // Container paints at zero width — an underline that exists in the
        // tree and never appears on screen.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 6),
              Container(
                height: T.navUnderline,
                color: active ? T.accentText : T.page,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom-left, outside the column: 32px avatar, name, `Log Out`.
///
/// The frame fills the avatar with a teal-to-navy gradient that no token
/// covers; ruled to a flat `--surface-3` with a `--text-1` initial instead.
class _UserChip extends StatelessWidget {
  const _UserChip({required this.name, required this.onLogOut});

  final String name;
  final VoidCallback onLogOut;

  @override
  Widget build(BuildContext context) {
    // An empty name must not crash the shell, and must not render a blank
    // circle either — a session always has an identity of some kind.
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: T.avatarSize,
          height: T.avatarSize,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: T.surface3,
            shape: BoxShape.circle,
          ),
          child: Text(
            initial,
            style: T.supporting.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              name,
              style: T.supporting.copyWith(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 2),
            Semantics(
              button: true,
              child: InkWell(
                onTap: onLogOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.logout, size: 16, color: T.text3),
                    const SizedBox(width: 6),
                    Text(
                      'Log Out',
                      style: T.supporting.copyWith(color: T.text3),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
