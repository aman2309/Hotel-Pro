#!/bin/zsh
# Hotel Silver Cloud — run / build helpers
# Usage:
#   ./run_platforms.sh mac
#   ./run_platforms.sh android
#   ./run_platforms.sh apk
#   ./run_platforms.sh windows   # only on a Windows PC
#   ./run_platforms.sh all       # mac + android (if device/emulator available)

set -e
cd "$(dirname "$0")"

cmd="${1:-all}"

case "$cmd" in
  mac|macos)
    echo ">> Running on macOS..."
    flutter run -d macos
    ;;
  android)
    echo ">> Running on Android (device/emulator must be connected)..."
    flutter devices
    flutter run -d android
    ;;
  apk)
    echo ">> Building Android APK..."
    flutter build apk --release
    echo ""
    echo "APK ready:"
    echo "  $(pwd)/build/app/outputs/flutter-apk/app-release.apk"
    ;;
  windows)
    echo ">> Windows desktop build only works on a Windows PC."
    echo "   On Windows, run:"
    echo "     flutter pub get"
    echo "     flutter run -d windows"
    echo "   Or release:"
    echo "     flutter build windows --release"
    exit 1
    ;;
  all)
    echo ">> Devices:"
    flutter devices
    echo ""
    if flutter devices 2>/dev/null | grep -qi "macos"; then
      echo ">> Starting macOS in background..."
      flutter run -d macos &
      MAC_PID=$!
      echo "   macOS PID: $MAC_PID"
    fi
    if flutter devices 2>/dev/null | grep -qiE "android|emulator"; then
      echo ">> Starting Android..."
      flutter run -d android
    else
      echo "!! No Android device/emulator found."
      echo "   Connect a phone (USB debugging ON) or create an AVD in Android Studio,"
      echo "   then run:  ./run_platforms.sh android"
      echo ""
      echo "   Or install APK:  ./run_platforms.sh apk"
      wait
    fi
    ;;
  *)
    echo "Usage: $0 {mac|android|apk|windows|all}"
    exit 1
    ;;
esac
