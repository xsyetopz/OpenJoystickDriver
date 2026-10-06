# OpenJoystickDriver repository tasks.
# Run `just` (or `just --list`) to see all available recipes.
# Just orchestrates standard tools; ./Scripts/ojd owns repository-specific behavior.

# Show available recipes
default:
    @just --list

# Install the repository command runner and Git hooks
setup:
    ./Scripts/ojd setup

# Install repository Git hooks
hooks-install:
    ./Scripts/ojd hooks install

# Validate repository Git hook configuration
hooks-validate:
    ./Scripts/ojd hooks validate

# =========================================================================
# Build
# =========================================================================

# Build + sign app bundle into .build/ (no dext)
build-dev:
    ./Scripts/ojd build dev

# Build + sign app bundle for release (no dext)
build-release:
    ./Scripts/ojd build release

# Build DriverKit .dext and embed into .build/ app
build-dext:
    ./Scripts/ojd build dext

# Full rebuild and install (app + dext) into /Applications
install-dev:
    ./Scripts/ojd build install dev

# Full rebuild and install release build
install-release:
    ./Scripts/ojd build install release

# App-only rebuild and install (preserves installed sysext)
install-fast-dev:
    ./Scripts/ojd build install-fast dev

# =========================================================================
# DriverKit
# =========================================================================

# Generate a fresh SwifterKit DriverKit project
driverkit-generate *args:
    ./Scripts/ojd driverkit generate {{ args }}

# Verify generated DriverKit reproducibility and unsigned build
driverkit-check:
    ./Scripts/ojd check driverkit

# =========================================================================
# Lint & Format
# =========================================================================

# Run standard formatters, linters, and type checks without a repository wrapper
lint:
    ruff format --check Scripts Tests/RepositoryScripts
    ruff check Scripts Tests/RepositoryScripts
    pyright
    find Scripts -type f \( -name '*.sh' -o -name ojd \) -print0 | xargs -0 shellcheck --external-sources --source-path=SCRIPTDIR
    git ls-files -z -co --exclude-standard -- '*.md' ':!.agents/' | xargs -0 markdownlint-cli2
    swift-format lint --recursive --strict Package.swift Sources Tests
    xcode="${DEVELOPER_DIR:-$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -exec test -x '{}/Contents/Developer/usr/bin/xcodebuild' ';' -print | sort -r | head -n1)/Contents/Developer}"; DEVELOPER_DIR="$xcode" swiftlint lint --no-cache --strict

# Format Python and Swift sources in place
format:
    ruff format Scripts Tests/RepositoryScripts
    swift-format format --recursive --in-place Package.swift Sources Tests

# =========================================================================
# Catalog
# =========================================================================

# Verify (--check) or rebuild (--write) the runtime catalog from pinned sources
catalog-regenerate *args:
    ./Scripts/ojd catalog regenerate {{ args }}

# Generate review-only records from a pinned Linux xpad.c
catalog-xpad *args:
    ./Scripts/ojd catalog xpad {{ args }}

# =========================================================================
# Checks
# =========================================================================

# Run the fast structural checks used by local Git hooks
check-hook:
    python3 Scripts/Quality/check_swift_file_length.py
    python3 Scripts/Quality/check_localization_keys.py
    git diff --check HEAD^ HEAD

# Run snapshot-safe validation
check-fast: check-schemas lint
    ./Scripts/ojd catalog regenerate --check
    ./Scripts/ojd errors regenerate --check
    ./Scripts/ojd check profiles
    python3 Scripts/Quality/check_swift_file_length.py
    python3 Scripts/Quality/check_localization_keys.py
    .build/schema-validator/bin/python -m unittest discover -s Tests/RepositoryScripts
    git diff --check

# Enforce the code-line limits for tracked Swift files (500 in Sources, 1000 in Tests)
check-swift-file-length:
    python3 Scripts/Quality/check_swift_file_length.py

# Run the complete local validation suite
check: check-fast
    ./Scripts/ojd check tools
    ./Scripts/ojd check driverkit
    ./Scripts/ojd test parsers-macos14
    xcode="${DEVELOPER_DIR:-$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -exec test -x '{}/Contents/Developer/usr/bin/xcodebuild' ';' -print | sort -r | head -n1)/Contents/Developer}"; DEVELOPER_DIR="$xcode" swift test --no-parallel

# Check canonical controller records
check-profiles:
    ./Scripts/ojd check profiles

# Validate schemas and create the schema Python environment that pyright and the script tests use
check-schemas:
    ./Scripts/ojd check schemas

# Build supported native tools without opening hardware
check-tools:
    ./Scripts/ojd check tools

# Verify generated DriverKit reproducibility and unsigned build
check-driverkit:
    ./Scripts/ojd check driverkit

# Run focused parser regressions for macOS 14 (no Swift Testing runtime)
test-parsers-macos14:
    ./Scripts/ojd test parsers-macos14

# =========================================================================
# Environment
# =========================================================================

# Validate the single-file env contract without printing values
env-audit:
    ./Scripts/ojd env audit

# =========================================================================
# Docs
# =========================================================================

# Refresh archived GitHub issue and pull-request evidence
docs-export-external-issues:
    ./Scripts/ojd docs export-external-issues

# Publish wiki/ to the GitHub wiki (pass --dry-run to preview without pushing)
wiki *args:
    ./Scripts/ojd docs publish-wiki {{ args }}

# =========================================================================
# Signing
# =========================================================================

# Copy profiles from ~/Documents/Profiles into MobileDevice
signing-install-profiles *args:
    ./Scripts/ojd signing install-profiles {{ args }}

# Generate .env.dev + .env.release from Keychain + profiles
signing-configure:
    ./Scripts/ojd signing configure

# Diagnose common cert/profile mismatch errors (safe output)
signing-doctor:
    ./Scripts/ojd signing doctor

# Audit profiles without leaking identifiers
signing-audit *paths:
    ./Scripts/ojd signing audit {{ paths }}

# Show safe-ish .cer info (Team ID = Subject OU)
signing-cert-info *args:
    ./Scripts/ojd signing cert-info {{ args }}

# Show safe-ish profile embedded cert info
signing-profile-info *args:
    ./Scripts/ojd signing profile-info {{ args }}

# Import embedded cert from a profile into Keychain
signing-import-embedded profile:
    ./Scripts/ojd signing import-embedded {{ profile }}

# Import GitHub Actions release secrets (CI only)
signing-ci-release-setup:
    ./Scripts/ojd signing ci-release-setup

# Write/import GitHub Actions release secrets
signing-export-github-secrets *args:
    ./Scripts/ojd signing export-github-secrets {{ args }}

# =========================================================================
# Diagnostics
# =========================================================================

# Run dext diagnostics (activation, codesign, IORegistry, app service)
diagnose-dext:
    ./Scripts/ojd diagnose dext

# Validate/probe a raw-USB record without app signing
diagnose-record *args:
    ./Scripts/ojd diagnose record {{ args }}

# Run SDL3 probe against the virtual device
diagnose-sdl3 *args:
    ./Scripts/ojd diagnose sdl3 {{ args }}

# Run SDL3 through GameController/MFI and test rumble
diagnose-sdl3-gamecontroller *args:
    ./Scripts/ojd diagnose sdl3-gamecontroller {{ args }}

# Run SDL3 through Xbox 360 HIDAPI and test rumble
diagnose-sdl3-hidapi-x360 *args:
    ./Scripts/ojd diagnose sdl3-hidapi-x360 {{ args }}

# Run GameController.framework probe
diagnose-gamecontroller *args:
    ./Scripts/ojd diagnose gamecontroller {{ args }}

# Run current backend acceptance loop
diagnose-backends *args:
    ./Scripts/ojd diagnose backends {{ args }}

# Interactively identify each physical rumble actuator, stopping between steps
diagnose-rumble-motors vid pid intensity="160" duration_ms="500":
    ./Scripts/ojd diagnose rumble-motors {{ vid }} {{ pid }} {{ intensity }} {{ duration_ms }}

# =========================================================================
# Repair
# =========================================================================

# Kill stale DriverKit process copies after upgrade
repair-stale-dext:
    ./Scripts/ojd repair stale-dext

# Clean SwiftPM build products after toolchain/target changes
repair-swiftpm-module-cache:
    ./Scripts/ojd repair swiftpm-module-cache

# =========================================================================
# Launch
# =========================================================================

# Launch an SDL app through GameController/MFI rumble route
launch-sdl-gamecontroller *args:
    ./Scripts/ojd launch sdl-gamecontroller {{ args }}

# =========================================================================
# Release
# =========================================================================

# Check release environment and signing assets for a tester build
package-tester-check:
    OJD_ENV=release ./Scripts/ojd env audit
    OJD_ENV=release ./Scripts/ojd signing doctor

# Build a private notarized Developer ID tester DMG without installing or publishing it
package-tester:
    ./Scripts/ojd package tester

# Set the app release version in Info.plist (SemVer, no build metadata)
release-bump-version version:
    ./Scripts/ojd release bump-version {{ version }}

# Build, notarize, staple, and package a release DMG
release-package *args:
    ./Scripts/ojd release package {{ args }}

# Package and install the release app locally
release-local-install *args:
    ./Scripts/ojd release install-local {{ args }}

# Submit the current release build for notarization
release-notarize-submit:
    ./Scripts/ojd release notarize submit

# Check notarization status (optionally pass a submission ID)
release-notarize-status *args:
    ./Scripts/ojd release notarize status {{ args }}

# Show notarization history
release-notarize-history:
    ./Scripts/ojd release notarize history

# Show notarization log for a submission
release-notarize-log id:
    ./Scripts/ojd release notarize log {{ id }}

# Store notarization credentials in Keychain
release-notarize-store-credentials *args:
    ./Scripts/ojd release notarize store-credentials {{ args }}
