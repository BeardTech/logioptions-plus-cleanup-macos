#!/bin/bash
# Targeted removal of Logi Options+ for the current macOS account.
# Without --execute, only previews the proposed changes.

set -u
shopt -s nocasematch

MODE="preview"
case "${1:-}" in
  "") ;;
  --execute) MODE="execute" ;;
  -h|--help)
    echo "Usage: $0 [--execute]"
    echo "No option: preview only. --execute: remove matching items."
    exit 0 ;;
  *) echo "Unknown option: $1" >&2; exit 2 ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script requires macOS." >&2
  exit 1
fi
if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script from your user account, without sudo. It will request sudo for system files." >&2
  exit 1
fi

USER_UID="$(id -u)"
FAILURES=0

report() { printf '%s\n' "$*"; }
remove_user() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  report "[user] $path"
  if [[ "$MODE" == "execute" ]]; then
    rm -rf -- "$path" || { report "  REMOVAL FAILED"; FAILURES=$((FAILURES+1)); }
  fi
}
remove_system() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  report "[system] $path"
  if [[ "$MODE" == "execute" ]]; then
    sudo rm -rf -- "$path" || { report "  REMOVAL FAILED"; FAILURES=$((FAILURES+1)); }
  fi
}
scan_names() {
  local base="$1" scope="$2" path name
  [[ -d "$base" ]] || return 0
  while IFS= read -r -d '' path; do
    name="${path##*/}"
    case "$name" in
      *logioptionsplus*|*logi.optionsplus*|*logi\ options+*|com.logi.cp-dev-mgr*)
        if [[ "$scope" == "system" ]]; then remove_system "$path"; else remove_user "$path"; fi ;;
    esac
  done < <(find "$base" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
}

report "Mode: $MODE — account: $(id -un)"
report "Other Logitech products are not targeted."

if [[ "$MODE" == "execute" ]]; then
  # Authenticate once before making changes.
  sudo -v || exit 1
  launchctl bootout "gui/$USER_UID" /Library/LaunchAgents/com.logi.optionsplus.plist 2>/dev/null || true
  sudo launchctl bootout system /Library/LaunchDaemons/com.logi.optionsplus.updater.plist 2>/dev/null || true
  # Remaining processes run from this Options+-specific path.
  pkill -f '^/Library/Application Support/Logitech.localized/LogiOptionsPlus/' 2>/dev/null || true
  sudo pkill -f '^/Library/Application Support/Logitech.localized/LogiOptionsPlus/' 2>/dev/null || true
fi

report ""
report "Files to remove:"
remove_system /Applications/logioptionsplus.app
remove_system '/Applications/Utilities/Logi Options+ Driver Installer.bundle'
remove_system '/Library/Application Support/Logi/LogiOptionsPlus'
remove_system '/Library/Application Support/Logi/.logishrd/LogiOptionsPlus'
remove_system '/Library/Application Support/Logi/machine_identifier_op'
remove_system '/Library/Application Support/Logitech.localized/LogiOptionsPlus'
remove_system /Users/Shared/LogiOptionsPlus

for base in \
  /Library/Preferences /Library/Caches /Library/Logs /Library/PrivilegedHelperTools \
  /Library/LaunchAgents /Library/LaunchDaemons \
  "$HOME/Library/Application Support" "$HOME/Library/Preferences" \
  "$HOME/Library/Caches" "$HOME/Library/Logs" \
  "$HOME/Library/LaunchAgents" "$HOME/Library/LaunchDaemons" \
  "$HOME/Library/Containers" "$HOME/Library/Group Containers" \
  "$HOME/Library/Saved Application State" "$HOME/Library/HTTPStorages" \
  "$HOME/Library/WebKit"; do
  case "$base" in /Library/*) scan_names "$base" system ;; *) scan_names "$base" user ;; esac
done

# Files inside shared directories, without removing their parent directories.
for base in \
  "$HOME/Library/Application Support/Logi" \
  "$HOME/Library/Application Support/CrashReporter" \
  "$HOME/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments"; do
  scan_names "$base" user
done

# Do not display secrets: dump-keychain without -d reads metadata only.
# Select only generic passwords whose service, label, or account explicitly
# names Options+.
KEYCHAIN_ITEMS="$(mktemp)" || exit 1
trap 'rm -f "$KEYCHAIN_ITEMS"' EXIT
while IFS= read -r line; do
  keychain="${line#*\"}"
  keychain="${keychain%\"*}"
  [[ -f "$keychain" ]] || continue
  security dump-keychain "$keychain" 2>/dev/null | awk -v kc="$keychain" '
    function clean(s) { sub(/^.*<blob>="/, "", s); sub(/"$/, "", s); return s }
    function match_options(s, x) {
      x=tolower(s)
      return x ~ /logioptionsplus|logi\.optionsplus|logi options\+|com\.logi\.cp-dev-mgr/
    }
    function emit() {
      if (cls == "genp" && (match_options(svc) || match_options(label) || match_options(acct)))
        print kc "\034" svc "\034" acct "\034" label
    }
    /^class: / { emit(); cls=$2; gsub(/"/, "", cls); svc=""; acct=""; label=""; next }
    /"svce"<blob>="/ { svc=clean($0) }
    /"acct"<blob>="/ { acct=clean($0) }
    /0x00000007 <blob>="/ { label=clean($0) }
    END { emit() }
  ' >> "$KEYCHAIN_ITEMS"
done < <(security list-keychains -d user 2>/dev/null)

report ""
report "Keychain items to remove:"
if [[ ! -s "$KEYCHAIN_ITEMS" ]]; then
  report "  No Options+ items found in accessible user Keychains."
else
  sort -u "$KEYCHAIN_ITEMS" -o "$KEYCHAIN_ITEMS"
  while IFS=$'\034' read -r keychain service account label; do
    report "[Keychain] $keychain — service: $service ; account: $account ; label: $label"
    if [[ "$MODE" == "execute" ]]; then
      if [[ -n "$service" ]]; then
        security delete-generic-password -s "$service" -a "$account" "$keychain" >/dev/null 2>&1
      else
        security delete-generic-password -l "$label" -a "$account" "$keychain" >/dev/null 2>&1
      fi
      if [[ $? -ne 0 ]]; then report "  REMOVAL FAILED"; FAILURES=$((FAILURES+1)); fi
    fi
  done < "$KEYCHAIN_ITEMS"
fi

if [[ "$MODE" == "execute" ]]; then
  # Reset privacy permissions for these two exact bundle identifiers if possible.
  tccutil reset All com.logi.optionsplus >/dev/null 2>&1 || true
  tccutil reset All com.logi.cp-dev-mgr >/dev/null 2>&1 || true
  report ""
  report "Done. Restart macOS to clear cached login items. Failures: $FAILURES"
  [[ "$FAILURES" -eq 0 ]]
else
  report ""
  report "No changes made. To remove these items, run: ./uninstall-logi-options-plus.sh --execute"
fi
