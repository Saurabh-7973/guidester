#!/usr/bin/env bash
# Builds the dashboard for the web against your own Supabase project.
#
# Reads SUPABASE_URL and SUPABASE_ANON_KEY from dart_defines.local.json next
# to pubspec.yaml (git-ignored). The anon key is public by design; never put
# the service_role key here.
#
#   {"SUPABASE_URL": "https://<ref>.supabase.co", "SUPABASE_ANON_KEY": "<anon>"}
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
if [ ! -f dart_defines.local.json ]; then
  echo "Missing dart_defines.local.json. See the comment at the top of this script." >&2
  exit 1
fi
flutter build web --release --dart-define-from-file=dart_defines.local.json "$@"
