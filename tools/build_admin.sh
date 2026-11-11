#!/bin/sh
# Hotel owner website (mobile OTP login). Super admin has its own site:
# tools/build_superadmin.sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
flutter build web --release --target=lib/admin_main.dart --output=build/admin_web --dart-define=WEB_PORTAL=hotel "$@"
python3 tools/prepare_admin_web.py build/admin_web hotel
