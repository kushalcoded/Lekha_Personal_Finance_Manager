#!/usr/bin/env bash
# Puts a Lekha backup (phone: Settings → Export / share backup) on the Pixel_7
# emulator and opens the app on it, cut off from the cloud (see clone.dart).
#
#   bash test_driver/clone_to_emulator.sh <lekha_backup_….json>
#
# run_android.sh clears the app's data, so run this again after it.
set -euo pipefail
backup="$(cygpath -m "$1")"
cd "$(dirname "$0")/.."

device=emulator-5554
pkg=com.expanse.personal_tracker
adb="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"
mirror="$(cygpath -m "$USERPROFILE")/flutter_mirror"
[ -d "$mirror" ] && export FLUTTER_STORAGE_BASE_URL="file:///$mirror"

# x64 only: the local engine mirror holds just the emulator's debug engine.
flutter build apk --debug --target=test_driver/clone.dart --target-platform android-x64
"$adb" -s "$device" install -r build/app/outputs/flutter-apk/app-debug.apk
"$adb" -s "$device" shell am force-stop "$pkg"
# The restored settings turn SMS detection on, and its permission prompt would
# otherwise cover the app (and background it mid-test).
for perm in RECEIVE_SMS POST_NOTIFICATIONS; do
  "$adb" -s "$device" shell pm grant "$pkg" "android.permission.$perm" || true
done

# The app's private folder is writable only as the app; run-as allows that on a
# debug build. The staging copy is deleted straight after.
tmp=/data/local/tmp/lekha_clone.json
MSYS_NO_PATHCONV=1 "$adb" -s "$device" push "$backup" "$tmp" >/dev/null
MSYS_NO_PATHCONV=1 "$adb" -s "$device" shell \
  "run-as $pkg sh -c 'mkdir -p app_flutter && cat $tmp > app_flutter/clone.json'; rm $tmp"
"$adb" -s "$device" shell monkey -p "$pkg" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1

# clone.dart deletes the file only once the restore is done. Wait for that, so
# nothing (like run_android.sh's next install) kills the app mid-restore.
for _ in $(seq 60); do
  if ! "$adb" -s "$device" shell run-as "$pkg" ls app_flutter/clone.json >/dev/null 2>&1; then
    echo "Loaded $(basename "$backup") into Lekha on $device"
    exit 0
  fi
  sleep 1
done
echo "The app never picked up the backup; see: adb logcat -s flutter" >&2
exit 1
