#!/usr/bin/env bash
# Diagnostics and testing script for agy-statusline.
# Validates settings, permissions, test payloads, and real-time capture.

set -euo pipefail

AGY_DIR="$HOME/.gemini/antigravity-cli"
SETTINGS="$AGY_DIR/settings.json"
INSTALLED_SL="$AGY_DIR/statusline.sh"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_SL="$REPO_DIR/statusline.sh"
SAMPLE_PAYLOAD="$REPO_DIR/examples/payload.json"
FLAG_FILE="/tmp/agy_statusline_debug"
LAST_PAYLOAD="/tmp/agy_statusline_last.json"

C_BLU=$'\e[38;5;111m'
C_GRN=$'\e[38;5;114m'
C_YLW=$'\e[38;5;179m'
C_RED=$'\e[38;5;203m'
C_MAG=$'\e[38;5;176m'
C_RST=$'\e[0m'
C_BLD=$'\e[1m'

info() { printf "%s[INFO]%s %s\n" "$C_BLU" "$C_RST" "$*"; }
ok()   { printf "%s[OK]%s   %s\n" "$C_GRN" "$C_RST" "$*"; }
warn() { printf "%s[WARN]%s %s\n" "$C_YLW" "$C_RST" "$*"; }
fail() { printf "%s[FAIL]%s %s\n" "$C_RED" "$C_RST" "$*"; }

check_prerequisites() {
  if ! command -v jq >/dev/null 2>&1; then
    fail "jq is required but not installed."
    return 1
  fi
  ok "Prerequisite 'jq' found."
}

check_configuration() {
  if [[ ! -f $SETTINGS ]]; then
    warn "Configuration file not found at $SETTINGS."
    return 0
  fi

  local configured_cmd resolved_path
  configured_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if [[ -z $configured_cmd ]]; then
    warn "No statusLine.command entry found in $SETTINGS."
    return 0
  fi

  resolved_path="${configured_cmd/#\~/$HOME}"
  if [[ -f $resolved_path ]]; then
    ok "statusLine.command configured and target exists: $configured_cmd"
    return 0
  fi
  warn "Configured target file does not exist: $resolved_path"
}

check_script_status() {
  if [[ ! -f $INSTALLED_SL ]]; then
    warn "Script is not installed at $INSTALLED_SL."
    return 0
  fi

  if [[ ! -x $INSTALLED_SL ]]; then
    warn "Installed script $INSTALLED_SL is not executable."
    return 0
  fi
  ok "Installed script exists and is executable."

  if ! cmp -s "$REPO_SL" "$INSTALLED_SL"; then
    info "Installed script differs from local repository copy."
    return 0
  fi
  ok "Installed script is in sync with repository copy."
}

run_synthetic_tests() {
  local target_bin="$REPO_SL"
  [[ -x $INSTALLED_SL ]] && target_bin="$INSTALLED_SL"

  printf "\n%s--- Synthetic Test: Default Mode (cycle_mode=default) ---%s\n" "$C_BLD" "$C_RST"
  AGY_DEBUG="" echo '{"cycle_mode":"default","terminal_width":120}' | "$target_bin"

  printf "\n%s--- Synthetic Test: Plan Mode (cycle_mode=plan) ---%s\n" "$C_BLD" "$C_RST"
  AGY_DEBUG="" echo '{"cycle_mode":"plan","terminal_width":120}' | "$target_bin"

  printf "\n%s--- Synthetic Test: Accept Edits Mode (cycle_mode=accept-edits) ---%s\n" "$C_BLD" "$C_RST"
  AGY_DEBUG="" echo '{"cycle_mode":"accept-edits","terminal_width":120}' | "$target_bin"
  printf "\n"
}

run_example_payload() {
  if [[ ! -f $SAMPLE_PAYLOAD ]]; then
    return 0
  fi

  local target_bin="$REPO_SL"
  [[ -x $INSTALLED_SL ]] && target_bin="$INSTALLED_SL"

  printf "%s--- Sample Payload Test (examples/payload.json) ---%s\n" "$C_BLD" "$C_RST"
  AGY_DEBUG="" "$target_bin" < "$SAMPLE_PAYLOAD"
  printf "\n"
}

check_captured_payload() {
  touch "$FLAG_FILE" 2>/dev/null || true

  if [[ ! -f $LAST_PAYLOAD ]]; then
    info "No live payload captured yet at $LAST_PAYLOAD."
    info "Live capture enabled via $FLAG_FILE. Trigger an action in agy to record."
    return 0
  fi

  ok "Captured payload found at $LAST_PAYLOAD."
  printf "\n%s=== Captured Payload Content ===%s\n" "$C_MAG" "$C_RST"
  jq . "$LAST_PAYLOAD"
  printf "%s=================================%s\n\n" "$C_MAG" "$C_RST"

  local target_bin="$REPO_SL"
  [[ -x $INSTALLED_SL ]] && target_bin="$INSTALLED_SL"

  printf "%sLive Status Line Rendering:%s\n" "$C_BLD" "$C_RST"
  AGY_DEBUG="" "$target_bin" < "$LAST_PAYLOAD"
}

main() {
  printf "\n%s=== agy-statusline Diagnostics ===%s\n\n" "$C_BLD" "$C_RST"
  check_prerequisites
  check_configuration
  check_script_status
  run_synthetic_tests
  run_example_payload
  check_captured_payload
  printf "\n%s==================================%s\n\n" "$C_BLD" "$C_RST"
}

main "$@"
