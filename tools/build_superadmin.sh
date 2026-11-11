#!/bin/sh
# Super admin console (email + password) for its own Firebase Hosting site.
# Hotel owners use tools/build_admin.sh (mobile OTP) on the hotel site.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
flutter build web --release --target=lib/admin_main.dart --output=build/superadmin_web --dart-define=WEB_PORTAL=superadmin "$@"
python3 tools/prepare_admin_web.py build/superadmin_web superadmin
