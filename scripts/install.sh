#!/bin/zsh
# Build the current version with release.sh and install it to /Applications.
# Quits a running Tower, replaces /Applications/Tower.app, then opens the new build.
set -euo pipefail

repo_root="${0:A:h:h}"
built_app_path="$repo_root/dist/DerivedData/Build/Products/Release/Tower.app"
installed_app_path="/Applications/Tower.app"

"$repo_root/scripts/release.sh" --allow-dirty

if pgrep -x Tower >/dev/null; then
  echo "quitting running Tower"
  osascript -e 'quit app "Tower"' || pkill -x Tower || true
  while pgrep -x Tower >/dev/null; do sleep 0.2; done
fi

rm -rf "$installed_app_path"
ditto "$built_app_path" "$installed_app_path"
codesign --verify --strict "$installed_app_path"

open "$installed_app_path"
echo "installed: $installed_app_path"
