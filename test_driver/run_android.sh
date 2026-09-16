#!/usr/bin/env bash
# The end-to-end run on the Pixel_7 emulator. Screenshots land in
# build/integration_screenshots/.
#
#   bash test_driver/run_android.sh                 # fresh install → login
#   bash test_driver/run_android.sh <backup.json>   # …then every signed-in tab
#                                                   # on that data (clone.dart)
#
# Pinned to emulator-5554 on purpose: it starts by clearing the app's data,
# which on the phone would wipe Lekha.
set -euo pipefail
backup="${1:+$(cygpath -am "$1")}"  # before cd, so a relative path still works
cd "$(dirname "$0")/.."

device=emulator-5554
adb="$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe"

# flutter's own uninstall after a run looks for the wrong package name
# (com.example…), so onboarding would already be done on the next run.
"$adb" -s "$device" shell pm clear com.expanse.personal_tracker >/dev/null 2>&1 || true

# Norton's SSL scanning stops Gradle downloading the debug engine; a verified
# local copy lives here (see CONTEXT.md).
mirror="$(cygpath -m "$USERPROFILE")/flutter_mirror"
[ -d "$mirror" ] && export FLUTTER_STORAGE_BASE_URL="file:///$mirror"

flutter drive --target=test_driver/app.dart -d "$device"

if [ -n "$backup" ]; then
  bash test_driver/clone_to_emulator.sh "$backup"
  flutter drive --target=test_driver/signed_in.dart -d "$device"
fi
