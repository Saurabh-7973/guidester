#!/usr/bin/env bash
# Fails if a hex colour literal appears anywhere outside the token files.
#
# GUIDESTER_WEB_BUILD_SPEC.md §10, Block A: "No component may hard-code a hex;
# add a CI grep that fails on `#` in component files outside tokens.css."
#
# The two permitted homes for a colour:
#   web/tokens.css                  the source of truth
#   lib/src/theme/tokens.dart       its Dart mirror, held to it by tokens_test
#
# Everything else — screens, widgets, theme wiring — must reference `T`.
# Tests are checked too: a hex in a test is how a wrong value gets blessed.
set -uo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.." || exit 1

# 0xAARRGGBB / 0xRRGGBB (Dart Color) and #RGB / #RRGGBB / #RRGGBBAA (CSS).
# `# 1a2b3c` in prose does not match; a bare `#` in a comment does not match.
PATTERN='(0x[0-9a-fA-F]{6,8}\b|#[0-9a-fA-F]{3}\b|#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{8}\b)'

ALLOWED=(
  './web/tokens.css'
  './lib/src/theme/tokens.dart'
)

# Files that predate the spec. Block A is scoped to tokens and the shell, so
# these are not mine to rewrite — but they must not be invisible either.
#
# This list only ever shrinks. Block B empties the first three, Block C the
# fourth; app_theme.dart disappears entirely once nothing imports it. A file
# NOT on this list and NOT in ALLOWED fails immediately, so the hole cannot
# widen while it waits to be closed.
LEGACY=(
  './lib/src/screens/comments_screen.dart'   # Block B
  './lib/src/widgets/screenshot_view.dart'   # Block B
)

is_allowed () {
  local f="$1"
  for a in "${ALLOWED[@]}"; do [ "$f" = "$a" ] && return 0; done
  return 1
}

is_legacy () {
  local f="$1"
  for a in "${LEGACY[@]}"; do [ "$f" = "$a" ] && return 0; done
  return 1
}

FAILED=0
PENDING=0
while IFS= read -r file; do
  is_allowed "$file" && continue
  if is_legacy "$file"; then
    if hits="$(grep -cE "$PATTERN" "$file")"; then
      PENDING=$((PENDING + hits))
    fi
    continue
  fi
  if hits="$(grep -nE "$PATTERN" "$file")"; then
    if [ "$FAILED" -eq 0 ]; then
      echo "Hex colour literals outside the token files:"
      echo
    fi
    FAILED=1
    while IFS= read -r hit; do
      echo "  ${file}:${hit}"
    done <<< "$hits"
  fi
done < <(find ./lib ./test ./web -type f \( -name '*.dart' -o -name '*.css' -o -name '*.html' \) | sort)

if [ "$FAILED" -eq 1 ]; then
  cat <<'MSG'

Colour lives in web/tokens.css and is mirrored in lib/src/theme/tokens.dart.
Reference it as `T.<name>`; do not write the value a second time.

If you need a colour the spec does not define, STOP and ask for the token —
do not choose one. That is the rule this check exists to enforce.
MSG
  exit 1
fi

echo "PASS  no hex literals outside web/tokens.css and lib/src/theme/tokens.dart"
if [ "$PENDING" -gt 0 ]; then
  echo "      ${PENDING} literals remain in ${#LEGACY[@]} pre-spec files awaiting Blocks B-D:"
  for a in "${LEGACY[@]}"; do
    n="$(grep -cE "$PATTERN" "$a" 2>/dev/null || true)"
    [ "${n:-0}" -gt 0 ] && echo "        ${n}  ${a#./}"
  done
  echo "      This list only shrinks. Adding a file to it is not allowed."
fi
