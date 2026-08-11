# OpenJoystickDriver — justfile recipes mirroring ./scripts/ojd subcommands.
# Run `just` (or `just --list`) to see all available recipes.
# The scripts/ojd dispatcher remains the canonical interface; these recipes
# provide parallel convenience shortcuts.

# Show available recipes
default:
    @just --list

# =========================================================================
# Build
# =========================================================================

# Build + sign app bundle into .build/ (no dext)
build-dev:
    ./scripts/ojd build dev

# Build + sign app bundle for release (no dext)
build-release:
    ./scripts/ojd build release

# Build DriverKit .dext and embed into .build/ app
build-dext:
    ./scripts/ojd build dext

# Full rebuild and install (app + dext) into /Applications
install-dev:
    ./scripts/ojd build install dev

# Full rebuild and install release build
install-release:
    ./scripts/ojd build install release

# App-only rebuild and install (preserves installed sysext)
install-fast-dev:
    ./scripts/ojd build install-fast dev

# =========================================================================
# DriverKit
# =========================================================================

# Generate a fresh SwifterKit DriverKit project
driverkit-generate *args:
    ./scripts/ojd driverkit generate {{args}}

# Verify generated DriverKit reproducibility and unsigned build
driverkit-check:
    ./scripts/ojd check driverkit

# =========================================================================
# Lint & Format
# =========================================================================

# Run SwiftLint (requires swiftlint)
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    command -v swiftlint >/dev/null 2>&1 || { echo "ERROR: swiftlint not found (brew install swiftlint)" >&2; exit 2; }
    framework_path="$(xcrun --show-sdk-path 2>/dev/null)/../../usr/lib"
    [ -d "$framework_path/sourcekitdInProc.framework" ] || framework_path=""
    if [ -n "$framework_path" ]; then
      DYLD_FRAMEWORK_PATH="$framework_path" swiftlint lint --no-cache --strict
    else
      swiftlint lint --no-cache --strict
    fi

# Format Swift sources in-place
format:
    swift-format format --recursive --in-place Sources Tests

# =========================================================================
# Catalog
# =========================================================================

# Verify (--check) or rebuild (--write) the runtime catalog from pinned sources
catalog-regenerate *args:
    python3 scripts/catalog/generate-controller-catalog.py {{args}}

# Generate review-only records from a pinned Linux xpad.c
catalog-xpad *args:
    python3 scripts/catalog/generate-xpad-records.py {{args}}

# =========================================================================
# Checks
# =========================================================================

# Check canonical controller records
check-profiles:
    python3 scripts/catalog/validate-profiles.py

# Check script ownership, paths, modes, and syntax
check-scripts:
    python3 scripts/quality/validate-scripts.py

# Check Swift file sizes and ownership layout
check-swift-structure:
    python3 scripts/quality/validate-swift-structure.py

# Verify generated DriverKit reproducibility and unsigned build
check-driverkit:
    ./scripts/ojd check driverkit

# Run focused parser regressions for macOS 14 (no Swift Testing runtime)
test-parsers-macos14:
    ./scripts/ojd test parsers-macos14

# =========================================================================
# Environment
# =========================================================================

# Validate the single-file env contract without printing values
env-audit:
    python3 scripts/quality/env-audit.py

# =========================================================================
# Docs
# =========================================================================

# Refresh archived GitHub issue and pull-request evidence
docs-export-external-issues:
    python3 scripts/docs/issues/export.py

# =========================================================================
# Signing
# =========================================================================

# Copy profiles from ~/Documents/Profiles into MobileDevice
signing-install-profiles *args:
    ./scripts/ojd signing install-profiles {{args}}

# Generate .env.dev + .env.release from Keychain + profiles
signing-configure:
    ./scripts/ojd signing configure

# Diagnose common cert/profile mismatch errors (safe output)
signing-doctor:
    ./scripts/ojd signing doctor

# Audit profiles without leaking identifiers
signing-audit *paths:
    ./scripts/ojd signing audit {{paths}}

# Show safe-ish .cer info (Team ID = Subject OU)
signing-cert-info *args:
    ./scripts/ojd signing cert-info {{args}}

# Show safe-ish profile embedded cert info
signing-profile-info *args:
    ./scripts/ojd signing profile-info {{args}}

# Import embedded cert from a profile into Keychain
signing-import-embedded profile:
    ./scripts/ojd signing import-embedded {{profile}}

# Import GitHub Actions release secrets (CI only)
signing-ci-release-setup:
    ./scripts/ojd signing ci-release-setup

# Write/import GitHub Actions release secrets
signing-export-github-secrets *args:
    ./scripts/ojd signing export-github-secrets {{args}}

# =========================================================================
# Diagnostics
# =========================================================================

# Run dext diagnostics (activation, codesign, IORegistry, app service)
diagnose-dext:
    ./scripts/ojd diagnose dext

# Validate/probe a raw-USB record without app signing
diagnose-record *args:
    ./scripts/ojd diagnose record {{args}}

# Run SDL3 probe against the virtual device
diagnose-sdl3 *args:
    ./scripts/ojd diagnose sdl3 {{args}}

# Run SDL3 through GameController/MFI and test rumble
diagnose-sdl3-gamecontroller *args:
    ./scripts/ojd diagnose sdl3-gamecontroller {{args}}

# Run SDL3 through Xbox 360 HIDAPI and test rumble
diagnose-sdl3-hidapi-x360 *args:
    ./scripts/ojd diagnose sdl3-hidapi-x360 {{args}}

# Run GameController.framework probe
diagnose-gamecontroller *args:
    ./scripts/ojd diagnose gamecontroller {{args}}

# Check a macOS 10.15 test app bundle
diagnose-catalina *args:
    ./scripts/ojd diagnose catalina {{args}}

# Run current backend acceptance loop
diagnose-backends *args:
    ./scripts/ojd diagnose backends {{args}}

# =========================================================================
# Repair
# =========================================================================

# Kill stale DriverKit process copies after upgrade
repair-stale-dext:
    ./scripts/ojd repair stale-dext

# Clean SwiftPM build products after toolchain/target changes
repair-swiftpm-module-cache:
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ ! -d ".build" ]]; then
        echo "No .build directory; nothing to clean."
        exit 0
    fi
    swift package clean
    echo "Cleaned SwiftPM build products."

# =========================================================================
# Launch
# =========================================================================

# Launch an SDL app through GameController/MFI rumble route
launch-sdl-gamecontroller *args:
    ./scripts/ojd launch sdl-gamecontroller {{args}}

# =========================================================================
# Release
# =========================================================================

# Update release version references (changelog heading must exist)
release-bump-version version:
    ./scripts/ojd release bump-version {{version}}

# Build, notarize, staple, and package a release DMG
release-package *args:
    ./scripts/ojd release package {{args}}

# Package and install the release app locally
release-local-install version="0.5.0-beta.1":
    ./scripts/ojd release install-local "{{version}}"

# Submit the current release build for notarization
release-notarize-submit:
    ./scripts/ojd release notarize submit

# Check notarization status (optionally pass a submission ID)
release-notarize-status *args:
    ./scripts/ojd release notarize status {{args}}

# Show notarization history
release-notarize-history:
    ./scripts/ojd release notarize history

# Show notarization log for a submission
release-notarize-log id:
    ./scripts/ojd release notarize log {{id}}

# Store notarization credentials in Keychain
release-notarize-store-credentials *args:
    ./scripts/ojd release notarize store-credentials {{args}}
