# Release builds: version bumps, packaging, notarization, and the private tester DMG.

# Build a private notarized Developer ID tester DMG without installing or publishing it.
package-tester:
    {{ release }} {{ env }} python3 -m Scripts.Release.package_tester tester

# Set the app version in Info.plist: an exact SemVer, or major, minor, patch, release, prerelease, alpha, beta, or rc.
release-bump-version version:
    python3 -m Scripts.Release.bump_version {{ version }}

# Build, notarize, staple, and package a release DMG.
release-package *version:
    {{ release }} {{ env }} python3 -m Scripts.Release.package release {{ version }}

# Package the release app (the Info.plist version unless one is given) and install it locally.
release-local-install version="":
    #!/usr/bin/env bash
    set -euo pipefail
    version={{ quote(version) }}
    [[ -n "$version" ]] || version="$(plutil -extract CFBundleShortVersionString raw -o - Sources/OpenJoystickDriver/App/Info.plist)"
    {{ release }} {{ env }} python3 -m Scripts.Release.package release "$version"
    app=.build/debug/OpenJoystickDriver.app
    [[ -d "$app" ]] || { echo "ERROR: Release package did not produce $app" >&2; exit 2; }
    {{ release }} {{ env }} python3 -m Scripts.Build.install_app --retire-driverkit "$app"
    echo "Installed OpenJoystickDriver $version at /Applications/OpenJoystickDriver.app"

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
