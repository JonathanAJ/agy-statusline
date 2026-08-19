#!/usr/bin/env bash
# Installs agy-statusline into ~/.gemini/antigravity-cli and registers it in settings.json.
set -euo pipefail

AGY_DIR="$HOME/.gemini/antigravity-cli"
SRC="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
DEST="$AGY_DIR/statusline.sh"
SETTINGS="$AGY_DIR/settings.json"

command -v jq >/dev/null || { echo "error: jq is required (brew install jq)"; exit 1; }
[[ -d $AGY_DIR ]] || { echo "error: $AGY_DIR not found — is the Antigravity CLI installed?"; exit 1; }

cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "installed $DEST"

block='{"type":"command","command":"~/.gemini/antigravity-cli/statusline.sh"}'
if [[ -f $SETTINGS ]]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  jq --argjson sl "$block" '.statusLine = $sl' "$SETTINGS.bak" > "$SETTINGS"
  echo "updated $SETTINGS (backup at $SETTINGS.bak)"
else
  jq -n --argjson sl "$block" '{statusLine: $sl}' > "$SETTINGS"
  echo "created $SETTINGS"
fi

echo "done — restart agy to see your new status line"
echo "preview now with: $DEST < examples/payload.json"
