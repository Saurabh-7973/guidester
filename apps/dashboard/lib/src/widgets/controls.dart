import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Buttons and fields, drawn to the Figma frames (D75). Defined once here and used
/// everywhere, because the token guard forbids a colour outside the token
/// files and one shared widget is easier to keep honest than a theme every
/// screen can override.
///
/// Below [T.compactBreakpoint] both grow to [T.touchTarget]: a 32 px control
/// is fine for a mouse and too small for a thumb.
enum GButtonKind { primary, secondary, ghost, danger }

class GButton extends StatefulWidget {
  const GButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.kind = GButtonKind.primary,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final GButtonKind kind;

  /// Fill the parent's width (forms), rather than hug the label.
  final bool expand;

  @override
  State<GButton> createState() => _GButtonState();
}

class _GButtonState extends State<GButton> {
  bool _hover = false;
  bool _focus = false;
  bool _down = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  (Color fill, Color text, Color? border) _colours() {
    if (!_enabled && !widget.busy) {
      return switch (widget.kind) {
        // The frames' disabled Continue: a navy fill, not an opacity.
        GButtonKind.primary ||
        GButtonKind.danger => (T.accentDim, T.text3, null),
        GButtonKind.secondary => (Colors.transparent, T.text3, T.accentDim),
        GButtonKind.ghost => (Colors.transparent, T.text3, null),
      };
    }
    return switch (widget.kind) {
      GButtonKind.primary => (
        _down ? T.accentPressed : (_hover ? T.accentHover : T.accent),
        T.onAccent,
        null,
      ),
      GButtonKind.danger => (T.red, T.onAccent, null),
      // The frames' "Open Pub Dev" and "No": blue edge, white label.
      GButtonKind.secondary => (
        _hover ? T.accentSubtle : Colors.transparent,
        T.text1,
        T.accent,
      ),
      GButtonKind.ghost => (
        _hover ? T.surface2 : Colors.transparent,
        T.text2,
        null,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < T.compactBreakpoint;
    final (fill, text, border) = _colours();
    final content = widget.busy
        ? SizedBox(
            height: 14,
            width: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: text),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 14, color: text),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body.copyWith(
                    color: text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      // Excluding the children drops the gesture's own tap action, so it is
      // declared here, or a screen reader could find the button and not
      // press it.
      onTap: _enabled ? _activate : null,
      focusable: _enabled,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTapDown: _enabled ? (_) => setState(() => _down = true) : null,
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: _enabled ? _activate : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                height: compact ? T.touchTarget : T.controlHeight,
                width: widget.expand ? double.infinity : null,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(T.rControl),
                  border: border == null ? null : Border.all(color: border),
                ),
                child: content,
              ),
              if (_focus)
                Positioned(
                  key: const ValueKey('focus-ring'),
                  left: -3,
                  top: -3,
                  right: -3,
                  bottom: -3,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(T.rControl + 3),
                        border: Border.all(color: T.accentText, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The outlined sibling, kept so existing screens compile. Plans 2b-2c move
/// callers to `GButton(kind: GButtonKind.secondary)` and delete this.
class GButtonOutlined extends StatelessWidget {
  const GButtonOutlined({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => GButton(
    label: label,
    onPressed: onPressed,
    icon: icon,
    kind: GButtonKind.secondary,
  );
}

class GField extends StatelessWidget {
  const GField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.error,
    this.suffix,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.autofillHints,
    this.onSubmitted,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hint;

  /// Shown above the field. A placeholder vanishes on the first keystroke, so
  /// a form field with only a hint leaves the user guessing what it was.
  final String? label;

  /// Inline, under the field, in red. Null hides it.
  final String? error;
  final Widget? suffix;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < T.compactBreakpoint;
    final hasError = error != null;
    final height = compact ? T.touchTarget : T.controlHeight + 4;
    // The input container is as tall as its content, not its box, unless a
    // suffix icon props it open; the outline is drawn around the container.
    // Padding the 20 px line out to the full height keeps both the text and
    // the focused border where the box is.
    final vertical = (height - T.body.fontSize! * T.body.height!) / 2;
    final field = SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        autofocus: autofocus,
        enabled: enabled,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
        style: T.body,
        cursorColor: T.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: T.body.copyWith(color: T.text3),
          filled: true,
          fillColor: T.surface2,
          isDense: true,
          suffixIcon: suffix,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: vertical,
          ),
          // The frames draw no edge at rest; focus is the accent.
          border: _border(T.surface2),
          enabledBorder: _border(hasError ? T.red : T.surface2),
          focusedBorder: _border(hasError ? T.red : T.accent),
          disabledBorder: _border(T.surface2),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The visible label is excluded and handed to the field itself, so
        // a screen reader meets one text field named "Email". Wrapping it in
        // Semantics(textField: true) made a second, empty one; merging pulled
        // the suffix button into the field.
        if (label != null) ...[
          ExcludeSemantics(
            child: Text(label!, style: T.body.copyWith(color: T.text2)),
          ),
          const SizedBox(height: 6),
        ],
        Semantics(label: label ?? hint, child: field),
        if (hasError) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(error!, style: T.meta.copyWith(color: T.red)),
          ),
        ],
      ],
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(T.rControl),
        borderSide: BorderSide(color: color, width: width),
      );
}

/// A [GField] for passwords, with the eye that shows what was typed.
class GPasswordField extends StatefulWidget {
  const GPasswordField({
    super.key,
    required this.controller,
    this.hint = 'Password',
    this.error,
    this.enabled = true,
    this.focusNode,
    this.autofocus = false,
    this.newPassword = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final String? error;
  final bool enabled;
  final FocusNode? focusNode;
  final bool autofocus;

  /// Lets a password manager offer to generate and save one.
  final bool newPassword;
  final ValueChanged<String>? onSubmitted;

  @override
  State<GPasswordField> createState() => _GPasswordFieldState();
}

class _GPasswordFieldState extends State<GPasswordField> {
  bool _shown = false;

  void _toggle() => setState(() => _shown = !_shown);

  @override
  Widget build(BuildContext context) {
    return GField(
      controller: widget.controller,
      hint: widget.hint,
      error: widget.error,
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      obscure: !_shown,
      autofillHints: [
        widget.newPassword ? AutofillHints.newPassword : AutofillHints.password,
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      suffix: Semantics(
        button: true,
        label: _shown ? 'Hide password' : 'Show password',
        onTap: _toggle,
        excludeSemantics: true,
        child: IconButton(
          icon: Icon(
            _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 16,
            color: T.text3,
          ),
          onPressed: _toggle,
        ),
      ),
    );
  }
}
