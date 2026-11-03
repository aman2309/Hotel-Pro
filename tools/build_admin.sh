#!/bin/sh
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$PROJECT_DIR"
flutter build web --release --target=lib/admin_main.dart --output=build/admin_web "$@"
python3 tools/prepare_admin_web.py
