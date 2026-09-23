#!/usr/bin/env bash
# Uninstalls agy-statusline from ~/.gemini/antigravity-cli and unregisters it in settings.json.
set -euo pipefail

AGY_DIR="$HOME/.gemini/antigravity-cli"
DEST="$AGY_DIR/statusline.sh"
SETTINGS="$AGY_DIR/settings.json"

check_dependencies() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "error: jq is required (brew install jq / apt install jq)"
    exit 1
  fi
}

remove_binary() {
  if [[ -f $DEST ]]; then
    rm -f "$DEST"
    echo "removed $DEST"
    return 0
  fi
  echo "statusline binary not found at $DEST (already removed)"
}

clean_settings() {
  if [[ ! -f $SETTINGS ]]; then
    echo "settings file not found at $SETTINGS"
    return 0
  fi

  cp "$SETTINGS" "$SETTINGS.bak"
  jq 'del(.statusLine)' "$SETTINGS.bak" > "$SETTINGS"
  echo "updated $SETTINGS (statusLine removed, backup at $SETTINGS.bak)"
}

clean_temporary_files() {
  rm -f /tmp/agy_statusline_debug /tmp/agy_statusline_last.json \
        /tmp/agy_statusline_real.json /tmp/agy_statusline_history.log 2>/dev/null || true
}

main() {
  check_dependencies
  remove_binary
  clean_settings
  clean_temporary_files
  echo "done — restart agy to restore the default status line"
}

main "$@"
