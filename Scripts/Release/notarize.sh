#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../Platform/environment.sh"

subcmd="${1:-submit}"
shift || true

if [[ "$OJD_ENV" != "release" ]]; then
  echo "ERROR: Notarization requires OJD_ENV=release"
  exit 1
fi

if [[ "$subcmd" == "store-credentials" ]]; then
  profile="${1:-${NOTARIZE_KEYCHAIN_PROFILE:-OpenJoystickDriver}}"
  if [[ -z "${NOTARIZE_APPLE_ID:-}" ]]; then
    if [[ ! -t 0 || -n "${CI:-}" ]]; then
      die "NOTARIZE_APPLE_ID is required in noninteractive mode"
    fi
    read -r -p "Apple ID for notarization: " NOTARIZE_APPLE_ID
    [[ -n "$NOTARIZE_APPLE_ID" ]] || die "Apple ID cannot be empty"
  fi
  args=(store-credentials "$profile" --apple-id "$NOTARIZE_APPLE_ID" --team-id "$DEVELOPMENT_TEAM")
  echo "notarytool will securely prompt for the app-specific password."
  xcrun notarytool "${args[@]}"
  python3 "$LIB_DIR/env_file.py" update "$OJD_ENV_FILE" NOTARIZE_APPLE_ID "$NOTARIZE_APPLE_ID"
  python3 "$LIB_DIR/env_file.py" update "$OJD_ENV_FILE" NOTARIZE_KEYCHAIN_PROFILE "$profile"
  echo "Stored notarytool profile: $profile"
  echo "Updated NOTARIZE_KEYCHAIN_PROFILE in $OJD_ENV_FILE"
  exit 0
fi

if [[ -z "${NOTARIZE_KEYCHAIN_PROFILE:-}" && ( -z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_PASSWORD:-}" ) ]]; then
  echo "ERROR: Notarization credentials not set in .env.release"
  echo ""
  echo "  NOTARIZE_APPLE_ID  = your Apple ID email"
  echo "  NOTARIZE_PASSWORD  = app-specific password from:"
  echo "    appleid.apple.com -> Sign-In and Security -> App-Specific Passwords"
  exit 1
fi

APP="/Applications/OpenJoystickDriver.app"
ZIP_PATH="$PROJECT_DIR/.build/OpenJoystickDriver-notarize.zip"
if [[ "$subcmd" == "submit" && $# -gt 0 ]]; then
  [[ $# -eq 2 ]] || die "submit takes no arguments, or the app and the archive: submit <app> <zip>"
  APP="$1"
  ZIP_PATH="$2"
fi

readonly TIMEOUT_MINUTES=180
readonly POLL_INTERVAL=30
readonly MAX_RETRIES=5

if [[ ! -d "$APP" ]]; then
  echo "ERROR: App not found at $APP"
  echo "Run: just install-release"
  exit 1
fi

if [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_ARGS=(--keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE")
else
  AUTH_ARGS=(
    --apple-id "$NOTARIZE_APPLE_ID"
    --password "$NOTARIZE_PASSWORD"
    --team-id "$DEVELOPMENT_TEAM"
  )
fi

if [[ "$subcmd" == "history" ]]; then
  echo "Recent notarization history:"
  xcrun notarytool history "${AUTH_ARGS[@]}"
  exit 0
fi

if [[ "$subcmd" == "status" ]]; then
  if [[ -n "${1:-}" ]]; then
    echo "Checking submission: $1"
    xcrun notarytool info "$1" "${AUTH_ARGS[@]}"
    echo ""
    echo "To fetch the log: just release-notarize-log $1"
  else
    echo "Recent notarization history:"
    xcrun notarytool history "${AUTH_ARGS[@]}"
  fi
  exit 0
fi

if [[ "$subcmd" == "log" ]]; then
  [[ -n "${1:-}" ]] || die "Missing submission id (Usage: just release-notarize-log <id>)"
  echo "Fetching log for: $1"
  xcrun notarytool log "$1" "${AUTH_ARGS[@]}"
  exit 0
fi

if [[ "$subcmd" != "submit" ]]; then
  die "Unknown notarize subcommand: $subcmd"
fi

echo "Creating zip for notarization..."
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
echo "  Zip: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

echo "Submitting to Apple for notarization..."
SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
  "${AUTH_ARGS[@]}" 2>&1)

echo "$SUBMIT_OUTPUT"

SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1)

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "ERROR: Failed to parse submission ID from notarytool output"
  exit 1
fi

echo "  Submission ID: $SUBMISSION_ID"

rm -f "$ZIP_PATH"

DEADLINE=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))
CONSECUTIVE_FAILURES=0

echo "Polling for notarization status (timeout: ${TIMEOUT_MINUTES}m, interval: ${POLL_INTERVAL}s)..."
echo "  Note: First-ever submissions can take hours (Apple may also delay on weekends)."
echo "        Subsequent ones typically finish in ~5 min."
echo ""

while true; do
  NOW=$(date +%s)
  if (( NOW >= DEADLINE )); then
    echo "ERROR: Notarization timed out after ${TIMEOUT_MINUTES} minutes"
    echo "  Submission ID: $SUBMISSION_ID"
    echo ""
    echo "  Apple still has the submission queued. It may complete later."
    echo "  Check status:  just release-notarize-status $SUBMISSION_ID"
    echo "  View history:  just release-notarize-history"
    echo ""
    echo "  If it completes, staple manually:"
    echo "    xcrun stapler staple $APP"
    exit 1
  fi

  REMAINING=$(( (DEADLINE - NOW) / 60 ))

  if INFO_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" \
    "${AUTH_ARGS[@]}" 2>&1); then
    CONSECUTIVE_FAILURES=0
  else
    CONSECUTIVE_FAILURES=$(( CONSECUTIVE_FAILURES + 1 ))
    echo "[$(date '+%H:%M:%S')] Poll failed (attempt $CONSECUTIVE_FAILURES/$MAX_RETRIES): $(echo "$INFO_OUTPUT" | head -1)"
    if (( CONSECUTIVE_FAILURES >= MAX_RETRIES )); then
      echo "ERROR: Stopping after $MAX_RETRIES consecutive poll failures"
      echo "$INFO_OUTPUT"
      exit 1
    fi
    sleep "$POLL_INTERVAL"
    continue
  fi

  STATUS=$(echo "$INFO_OUTPUT" | grep -i "status:" | head -1 | sed 's/.*status:[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | xargs)

  echo "[$(date '+%H:%M:%S')] Status: $STATUS (${REMAINING}m remaining)"

  case "$STATUS" in
    accepted)
      echo ""
      echo "Notarization accepted."
      break
      ;;
    invalid|rejected)
      echo ""
      echo "ERROR: Notarization failed with status: $STATUS"
      echo ""
      echo "Fetching notarization log..."
      xcrun notarytool log "$SUBMISSION_ID" \
        "${AUTH_ARGS[@]}" 2>&1 || true
      exit 1
      ;;
    "in progress"|*)
      sleep "$POLL_INTERVAL"
      ;;
  esac
done

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

echo ""
echo "Notarization complete."
echo "  App: $APP"
echo "  Verify: spctl --assess --verbose=4 $APP"
