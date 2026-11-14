schema_python := ".build/schema-validator/bin/python"
env := "Scripts/with-env.sh"
release := "env OJD_ENV=release"

# Create the Python environment the catalog, schema and script tests use.
schema-env:
    [[ -x {{ schema_python }} ]] || { python3 -m venv .build/schema-validator && {{ schema_python }} -m pip install --quiet -r Scripts/Quality/requirements.txt; }

# Build and sign the app bundle into .build, without the dext.
build-dev:
    Scripts/Build/build.sh build dev

# Build and sign the release app bundle, without the dext.
build-release:
    {{ release }} Scripts/Build/build.sh build release

# Build the DriverKit .dext and embed it in the .build app.
build-dext:
    Scripts/Build/build.sh build dext

# Rebuild the app and dext, then install into /Applications.
install-dev:
    Scripts/Build/install.sh install dev

# Rebuild the release app and dext, then install into /Applications.
install-release:
    {{ release }} Scripts/Build/install.sh install release

# Rebuild and install the app only, keeping the installed system extension.
install-fast-dev:
    Scripts/Build/install.sh install-fast dev

# Generate the DriverKit project into a folder that does not exist yet.
driverkit-generate *path:
    Scripts/Build/driverkit.sh generate {{ path }}

# Check that the generated DriverKit project reproduces and builds unsigned.
driverkit-check:
    Scripts/Build/driverkit.sh validate

# Validate the schemas and a live support report.
check-schemas: schema-env
    {{ schema_python }} -m Scripts.Quality.validate_schemas
    {{ schema_python }} Tests/RepositoryScripts/test_schema_style.py

# Check the canonical controller records.
check-profiles: schema-env
    {{ schema_python }} -m Scripts.Quality.check_profiles

# Build the SDL gamepad probe and the WebRTC bridge package, and test the bridge.
check-tools:
    {{ env }} xmake build -P Tools/SDLGamepadProbe SDLGamepadProbe
    {{ env }} swift test --package-path Tools/WebRTCBridge

# Run the parser regressions that need no Swift Testing runtime (macOS 14).
test-parsers-macos14:
    {{ env }} swift run ParserCompatibilityHarness

# Diff the tree against the equivalence snapshots.
snapshots-check:
    python3 -m Scripts.Quality.equivalence_snapshots check

# Rewrite the equivalence snapshots from the tree.
snapshots-write:
    python3 -m Scripts.Quality.equivalence_snapshots write

# Verify (--check) or rebuild (--write) the runtime catalog.
catalog-regenerate *args: schema-env
    {{ schema_python }} -m Scripts.Catalog.generate_controller_catalog {{ args }}

# Verify (--check) or rebuild (--write) the error code enum and wiki table.
errors-regenerate *args: schema-env
    {{ schema_python }} -m Scripts.Catalog.generate_error_codes {{ args }}

# Verify (--check) or rebuild (--write) the wiki control crosswalk.
vocabulary-regenerate *args:
    python3 -m Scripts.Catalog.generate_crosswalk {{ args }}

# Fail on whitespace errors in the working tree and in the commits ahead of origin/main.
check-whitespace:
    git diff --check
    git diff --check "$(git merge-base HEAD origin/main 2>/dev/null || git hash-object -t tree /dev/null)" HEAD

# Convert wiki/ into GitHub wiki pages in an empty folder.
wiki-build output *args:
    python3 -m Scripts.Documentation.wiki.build {{ output }} {{ args }}

# Publish wiki/ to the GitHub wiki; --dry-run shows the diff only.
wiki *args:
    python3 -m Scripts.Documentation.wiki.publish {{ args }}

# Copy provisioning profiles from ~/Documents/Profiles into MobileDevice.
signing-install-profiles *args:
    Scripts/Signing/signing.sh install-profiles {{ args }}

# Write .env.dev and .env.release from the Keychain and the profiles.
signing-configure *args:
    Scripts/Signing/signing.sh configure {{ args }}

# Audit provisioning profiles without printing identifiers.
signing-audit *paths:
    Scripts/Signing/signing.sh audit {{ paths }}

# Show the Team ID and subject of a .cer file.
signing-cert-info cer:
    Scripts/Signing/signing.sh cert-info {{ cer }}

# Show the certificates embedded in a provisioning profile.
signing-profile-info profile:
    Scripts/Signing/signing.sh profile-info {{ profile }}

# Import every certificate embedded in a profile into the Keychain.
signing-import-embedded profile:
    Scripts/Signing/signing.sh import-embedded {{ profile }}

# Import the GitHub Actions release secrets (CI only).
signing-ci-release-setup:
    Scripts/Signing/signing.sh ci-release-setup

# Write or import the GitHub Actions release secrets.
signing-export-github-secrets *args:
    Scripts/Signing/export-github-secrets.sh {{ args }}

# Run the dext diagnostics: activation, codesign, IORegistry, app service.
diagnose-dext:
    Scripts/Diagnostics/dext/diagnose.sh

# Validate or probe a canonical controller record through the USB dext.
diagnose-record record *args:
    {{ env }} swift run OpenJoystickDriverHIDTool --record-probe "$(realpath {{ record }})" {{ args }}

# Print an authorized device's USB descriptor facts (hex vid and pid).
diagnose-usb-passive vid pid:
    {{ env }} swift run OpenJoystickDriverHIDTool --usb-passive --vid {{ vid }} --pid {{ pid }}

# Run the SDL3 probe against the virtual device.
diagnose-sdl3 *args:
    Scripts/Diagnostics/backend.sh sdl3 {{ args }}

# Run SDL3 through GameController and test rumble.
diagnose-sdl3-gamecontroller *args:
    Scripts/Diagnostics/backend.sh sdl3-gamecontroller {{ args }}

# Run SDL3 through the Xbox 360 HIDAPI backend and test rumble.
diagnose-sdl3-hidapi-x360 *args:
    Scripts/Diagnostics/backend.sh sdl3-hidapi-x360 {{ args }}

# Run the GameController.framework probe.
diagnose-gamecontroller *args:
    Scripts/Diagnostics/backend.sh gamecontroller {{ args }}

# Run the backend acceptance loop.
diagnose-backends *args:
    Scripts/Diagnostics/backend.sh backends {{ args }}

# Feed every control to each browser's Gamepad API and report its slot.
diagnose-browsers *args:
    python3 -m Scripts.Diagnostics.browser_gamepad {{ args }}

# Identify each physical rumble actuator, pausing between steps.
diagnose-rumble-motors vid pid intensity="160" duration_ms="500":
    Scripts/Diagnostics/rumble-motors.sh {{ vid }} {{ pid }} {{ intensity }} {{ duration_ms }}

# Kill stale DriverKit process copies after an upgrade.
repair-stale-dext:
    python3 -m Scripts.Diagnostics.dext.repair

# Capture the installed app's windows into .ojd-shots; pass --area, --settings-pane or --all.
shots-capture *args:
    python3 -m Scripts.GUI.capture {{ args }}

# Build a private notarized Developer ID tester DMG without installing or publishing it.
package-tester:
    {{ release }} {{ env }} python3 -m Scripts.Release.package_tester tester

# Set the app release version in Info.plist.
release-bump-version version:
    python3 -m Scripts.Release.bump_version {{ version }}

# Build, notarize, staple, and package a release DMG.
release-package *version:
    {{ release }} {{ env }} python3 -m Scripts.Release.package release {{ version }}

# Package the release app and install it locally.
release-local-install *version:
    {{ release }} {{ env }} python3 -m Scripts.Release.install_local {{ version }}

# Submit the release build for notarization.
release-notarize-submit:
    {{ release }} Scripts/Release/notarize.sh submit

# Check notarization status, optionally of one submission.
release-notarize-status *id:
    {{ release }} Scripts/Release/notarize.sh status {{ id }}

# Show the notarization history.
release-notarize-history:
    {{ release }} Scripts/Release/notarize.sh history

# Show the notarization log of a submission.
release-notarize-log id:
    {{ release }} Scripts/Release/notarize.sh log {{ id }}

# Store the notarization credentials in the Keychain.
release-notarize-store-credentials *profile:
    {{ release }} Scripts/Release/notarize.sh store-credentials {{ profile }}

# Run ruff and shellcheck over the scripts.
project-lint:
    ruff check Scripts Tests/RepositoryScripts
    find Scripts -type f -name '*.sh' -print0 | xargs -0 shellcheck --external-sources --source-path=SCRIPTDIR

project-format:
    ruff format Scripts Tests/RepositoryScripts

project-format-check:
    ruff format --check Scripts Tests/RepositoryScripts

project-test: schema-env
    {{ schema_python }} -m unittest discover -s Tests/RepositoryScripts

# The checks CI runs beyond the Swift ones.
project-verify: project-format-check project-lint project-test check-schemas check-whitespace (catalog-regenerate "--check") (errors-regenerate "--check") (vocabulary-regenerate "--check") check-profiles driverkit-check test-parsers-macos14 snapshots-check check-tools
    python3 Scripts/Quality/check_localization_keys.py
    python3 Scripts/Quality/check_text_styles.py
    python3 -m Scripts.Quality.check_glossary_terms

project-pre-commit: project-format-check project-lint

project-setup:
    if ! command -v ruff >/dev/null; then brew install ruff; fi
    if ! command -v shellcheck >/dev/null; then brew install shellcheck; fi
