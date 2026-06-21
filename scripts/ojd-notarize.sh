#!/usr/bin/env bash
# Notarize helper for OpenJoystickDriver. Requires OJD_ENV=release.
#
# Human-facing entrypoint:
#   ./scripts/ojd notarize <submit|status|history|log>
#
# Prerequisites:
#   1. Developer ID signing (.env.release)
#   2. NOTARIZE_KEY_ID/NOTARIZE_ISSUER_ID with NOTARIZE_API_KEY_BASE64,
#      or NOTARIZE_KEYCHAIN_PROFILE,
#      or NOTARIZE_APPLE_ID/NOTARIZE_PASSWORD in .env.release
#
# Environment variables:
#   NOTARIZE_TIMEOUT_MINUTES  -- overall timeout (default: 180, i.e. 3 hours)
#                               First-ever submissions can take hours; subsequent ones ~5 min.
#   NOTARIZE_POLL_INTERVAL    -- seconds between polls (default: 30)
#   NOTARIZE_MAX_RETRIES      -- consecutive transient failures before abort (default: 5)
#
# USAGE:
#   OJD_ENV=release ./scripts/notarize.sh
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ojd-common.sh"

die() {
  echo "ERROR: $*" >&2
  exit 2
}

subcmd="${1:-submit}"
shift || true

if [[ "$subcmd" == "-h" || "$subcmd" == "--help" || "$subcmd" == "help" ]]; then
  cat << 'TXT'
Usage:
  OJD_ENV=release ./scripts/ojd notarize submit
  OJD_ENV=release ./scripts/ojd notarize status [submission-id]
  OJD_ENV=release ./scripts/ojd notarize log <submission-id>
  OJD_ENV=release ./scripts/ojd notarize history
  OJD_ENV=release ./scripts/ojd notarize store-credentials [profile-name]
TXT
  exit 0
fi

if [[ "$OJD_ENV" != "release" ]]; then
  echo "ERROR: Notarization requires OJD_ENV=release"
  exit 1
fi

if [[ "$subcmd" == "store-credentials" ]]; then
  profile="${1:-${NOTARIZE_KEYCHAIN_PROFILE:-OpenJoystickDriver}}"
  if [[ -z "${NOTARIZE_APPLE_ID:-}" ]]; then
    echo "ERROR: NOTARIZE_APPLE_ID is required."
    exit 1
  fi
  args=(store-credentials "$profile" --apple-id "$NOTARIZE_APPLE_ID" --team-id "$DEVELOPMENT_TEAM")
  if [[ -n "${NOTARIZE_PASSWORD:-}" ]]; then
    args+=(--password "$NOTARIZE_PASSWORD")
  fi
  xcrun notarytool "${args[@]}"
  echo "Stored notarytool profile: $profile"
  exit 0
fi

APP="${OJD_NOTARIZE_APP:-/Applications/OpenJoystickDriver.app}"
ZIP_PATH="${OJD_NOTARIZE_ZIP:-$PROJECT_DIR/.build/OpenJoystickDriver-notarize.zip}"

TIMEOUT_MINUTES="${NOTARIZE_TIMEOUT_MINUTES:-180}"
POLL_INTERVAL="${NOTARIZE_POLL_INTERVAL:-30}"
MAX_RETRIES="${NOTARIZE_MAX_RETRIES:-5}"

NOTARIZE_API_KEY_FILE=""
NOTARIZE_API_KEY_TEMP=""

cleanup_notarize_api_key() {
  if [[ -n "$NOTARIZE_API_KEY_TEMP" ]]; then
    rm -f "$NOTARIZE_API_KEY_TEMP"
  fi
}
trap cleanup_notarize_api_key EXIT

api_key_requested=0
for key in NOTARIZE_KEY_ID NOTARIZE_ISSUER_ID NOTARIZE_API_KEY_BASE64 NOTARIZE_API_KEY_PATH; do
  if [[ -n "${!key:-}" ]]; then
    api_key_requested=1
  fi
done

if [[ "$api_key_requested" -eq 1 ]]; then
  missing=()
  [[ -n "${NOTARIZE_KEY_ID:-}" ]] || missing+=("NOTARIZE_KEY_ID")
  [[ -n "${NOTARIZE_ISSUER_ID:-}" ]] || missing+=("NOTARIZE_ISSUER_ID")
  if [[ -z "${NOTARIZE_API_KEY_BASE64:-}" && -z "${NOTARIZE_API_KEY_PATH:-}" ]]; then
    missing+=("NOTARIZE_API_KEY_BASE64 or NOTARIZE_API_KEY_PATH")
  fi
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "ERROR: Incomplete App Store Connect API key notarization settings."
    printf '  Missing: %s\n' "${missing[@]}"
    exit 1
  fi

  if [[ -n "${NOTARIZE_API_KEY_BASE64:-}" ]]; then
    NOTARIZE_API_KEY_TEMP="$(mktemp "${TMPDIR:-/tmp}/ojd-notary-api-key.XXXXXX")"
    if ! printf '%s' "$NOTARIZE_API_KEY_BASE64" | python3 -c 'import base64, pathlib, sys
encoded = "".join(sys.stdin.read().split())
try:
    decoded = base64.b64decode(encoded, validate=True)
except Exception as exc:
    print(f"invalid base64: {exc}", file=sys.stderr)
    sys.exit(1)
if not decoded:
    print("decoded key is empty", file=sys.stderr)
    sys.exit(1)
pathlib.Path(sys.argv[1]).write_bytes(decoded)
' "$NOTARIZE_API_KEY_TEMP"; then
      rm -f "$NOTARIZE_API_KEY_TEMP"
      NOTARIZE_API_KEY_TEMP=""
      die "NOTARIZE_API_KEY_BASE64 is not valid base64"
    fi
    chmod 600 "$NOTARIZE_API_KEY_TEMP"
    NOTARIZE_API_KEY_FILE="$NOTARIZE_API_KEY_TEMP"
  else
    NOTARIZE_API_KEY_FILE="$NOTARIZE_API_KEY_PATH"
    case "$NOTARIZE_API_KEY_FILE" in
      "~/"*) NOTARIZE_API_KEY_FILE="$HOME/${NOTARIZE_API_KEY_FILE#~/}" ;;
    esac
    [[ -f "$NOTARIZE_API_KEY_FILE" ]] || die "NOTARIZE_API_KEY_PATH does not exist: $NOTARIZE_API_KEY_FILE"
  fi
elif [[ -z "${NOTARIZE_KEYCHAIN_PROFILE:-}" && (-z "${NOTARIZE_APPLE_ID:-}" || -z "${NOTARIZE_PASSWORD:-}") ]]; then
  echo "ERROR: Notarization credentials not set in .env.release"
  echo ""
  echo "Preferred App Store Connect API key settings:"
  echo "  NOTARIZE_KEY_ID"
  echo "  NOTARIZE_ISSUER_ID"
  echo "  NOTARIZE_API_KEY_BASE64 (or NOTARIZE_API_KEY_PATH)"
  echo ""
  echo "Fallback Apple ID settings:"
  echo "  NOTARIZE_APPLE_ID  = your Apple ID email"
  echo "  NOTARIZE_PASSWORD  = app-specific password from:"
  echo "    appleid.apple.com → Sign-In and Security → App-Specific Passwords"
  exit 1
fi

if [[ "$api_key_requested" -eq 1 ]]; then
  AUTH_ARGS=(--key "$NOTARIZE_API_KEY_FILE" --key-id "$NOTARIZE_KEY_ID" --issuer "$NOTARIZE_ISSUER_ID")
elif [[ -n "${NOTARIZE_KEYCHAIN_PROFILE:-}" ]]; then
  AUTH_ARGS=(--keychain-profile "$NOTARIZE_KEYCHAIN_PROFILE")
  if [[ -n "${NOTARIZE_KEYCHAIN:-}" ]]; then
    AUTH_ARGS+=(--keychain "$NOTARIZE_KEYCHAIN")
  fi
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
    echo "To fetch the log: OJD_ENV=release ./scripts/ojd notarize log $1"
  else
    echo "Recent notarization history:"
    xcrun notarytool history "${AUTH_ARGS[@]}"
  fi
  exit 0
fi

if [[ "$subcmd" == "log" ]]; then
  [[ -n "${1:-}" ]] || die "Missing submission id (Usage: ./scripts/ojd notarize log <id>)"
  echo "Fetching log for: $1"
  xcrun notarytool log "$1" "${AUTH_ARGS[@]}"
  exit 0
fi

if [[ "$subcmd" != "submit" ]]; then
  die "Unknown notarize subcommand: $subcmd"
fi

if [[ ! -d "$APP" ]]; then
  echo "ERROR: App not found at $APP"
  echo "Run: OJD_ENV=release ./scripts/ojd rebuild release"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Create zip for upload
# ---------------------------------------------------------------------------
echo "Creating zip for notarization..."
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
echo "  Zip: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1))"

# ---------------------------------------------------------------------------
# Step 2a: Submit to Apple (no --wait)
# ---------------------------------------------------------------------------
echo "Submitting to Apple for notarization..."
if SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" \
  "${AUTH_ARGS[@]}" 2>&1); then
  echo "$SUBMIT_OUTPUT"
else
  submit_status=$?
  echo "$SUBMIT_OUTPUT"
  echo "ERROR: notarytool submit failed (exit $submit_status)"
  exit "$submit_status"
fi

# Parse submission ID (UUID) from output
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "ERROR: Failed to parse submission ID from notarytool output"
  exit 1
fi

echo "  Submission ID: $SUBMISSION_ID"

# Remove zip now -- it's already uploaded
rm -f "$ZIP_PATH"

# ---------------------------------------------------------------------------
# Step 2b: Poll for completion with timeout and retry
# ---------------------------------------------------------------------------
DEADLINE=$(($(date +%s) + TIMEOUT_MINUTES * 60))
CONSECUTIVE_FAILURES=0

echo "Polling for notarization status (timeout: ${TIMEOUT_MINUTES}m, interval: ${POLL_INTERVAL}s)..."
echo "  Note: First-ever submissions can take hours (Apple may also delay on weekends)."
echo "        Subsequent ones typically finish in ~5 min."
echo ""

while true; do
  NOW=$(date +%s)
  if ((NOW >= DEADLINE)); then
    echo "ERROR: Notarization timed out after ${TIMEOUT_MINUTES} minutes"
    echo "  Submission ID: $SUBMISSION_ID"
    echo ""
    echo "  The submission is still queued with Apple -- it may yet complete."
    echo "  Check status:  OJD_ENV=release ./scripts/ojd notarize status $SUBMISSION_ID"
    echo "  View history:  OJD_ENV=release ./scripts/ojd notarize history"
    echo ""
    echo "  If it completes later, staple manually:"
    echo "    xcrun stapler staple $APP"
    exit 1
  fi

  REMAINING=$(((DEADLINE - NOW) / 60))

  # Query status, handling transient failures
  if INFO_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" \
    "${AUTH_ARGS[@]}" 2>&1); then
    CONSECUTIVE_FAILURES=0
  else
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))
    echo "[$(date '+%H:%M:%S')] Poll failed (attempt $CONSECUTIVE_FAILURES/$MAX_RETRIES): $(echo "$INFO_OUTPUT" | head -1)"
    if ((CONSECUTIVE_FAILURES >= MAX_RETRIES)); then
      echo "ERROR: $MAX_RETRIES consecutive poll failures -- giving up"
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
    invalid | rejected)
      echo ""
      echo "ERROR: Notarization failed with status: $STATUS"
      echo ""
      echo "Fetching notarization log..."
      xcrun notarytool log "$SUBMISSION_ID" \
        "${AUTH_ARGS[@]}" 2>&1 || true
      exit 1
      ;;
    "in progress" | *)
      sleep "$POLL_INTERVAL"
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Step 3: Staple the ticket to the app
# ---------------------------------------------------------------------------
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

echo ""
echo "Notarization complete."
echo "  App: $APP"
echo "  Verify: spctl --assess --verbose=4 $APP"
