# The Swift checks. Each Swift command runs through Scripts/with-env.sh, which selects one
# toolchain and SDK for the checkout: Xcode's when Xcode is installed, a swift.org toolchain
# otherwise. Project recipes go in project.just.

set shell := ["bash", "-euo", "pipefail", "-c"]
set working-directory := ".."

env := "Scripts/with-env.sh"
derived := ".build/xcode"

# With Xcode, SwiftPM builds the test targets for the testing frameworks' minimum macOS, so the tests
# use Swift Testing's `.timeLimit`, which needs macOS 13. A swift.org toolchain without Xcode keeps
# them at the macOS 12 floor, and its triple applies to every target, so the build there targets
# macOS 13: the lowest that has `.timeLimit`, and below the macOS 14 deprecations warnings would fail.
test_triple := `if [[ -x "${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null)}/usr/bin/xcodebuild" ]]; then :; else echo "--triple $(uname -m)-apple-macosx13.0"; fi`

# The C++ interop compiler warns about its own module map once compilation caching is on, and
# warnings fail the build, so Xcode builds the package targets uncached.
xcode_settings := "COMPILATION_CACHE_ENABLE_CACHING=NO"

# Install the Swift toolchain from .swift-version and SwiftLint.
setup:
    if command -v swiftly >/dev/null; then swiftly install; fi
    if ! command -v swiftlint >/dev/null; then brew install swiftlint; fi

# Format the Swift code.
format:
    just swift::files | xargs -0 -r {{ env }} swift format format --in-place --parallel

# Fail if the Swift code is not formatted.
format-check:
    just swift::files | xargs -0 -r {{ env }} swift format lint --strict --parallel

# Build the package, its tests, and each shared Xcode scheme, without running them.
typecheck:
    {{ env }} swift build --build-tests {{ test_triple }}
    just swift::xcode build-for-testing

# Run SwiftLint.
lint:
    swiftlint lint --strict --quiet

# Apply SwiftLint's and swift-format's fixes.
lint-fix:
    swiftlint lint --fix --quiet
    just swift::format

# Run the Swift Testing tests, then each shared Xcode scheme's tests.
test:
    {{ env }} swift test --parallel {{ test_triple }}
    just swift::xcode test

# Report XCTest outside UI tests, file-wide suppressions, foreign tools, and manifest or Xcode
# settings that leave Swift 6 strictness.
guard:
    {{ env }} python3 Scripts/Quality/swift_guard.py

# Run every Swift check CI runs.
verify: format-check typecheck lint guard test

# The Swift checks the pre-commit hook runs.
pre-commit: format-check lint guard

# Delete the git-ignored .build folder of each other worktree with no build running in it.
clean-worktrees:
    #!/usr/bin/env bash
    set -euo pipefail
    here=$(pwd -P)
    busy=$(lsof -a -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'; ps -axo command=)
    git worktree list --porcelain | sed -n 's/^worktree //p' | while IFS= read -r tree; do
        build="$tree/.build"
        if [[ "$tree" == "$here" || ! -d "$build" ]] || ! git -C "$tree" check-ignore -q .build; then
            continue
        fi
        if grep -qF -- "$tree" <<<"$busy"; then
            echo "Kept $build: a process is running in $tree"
        else
            echo "Deleting $build ($(du -sh "$build" | cut -f1))"
            rm -rf -- "$build"
        fi
    done

[private]
files:
    git ls-files -z --cached --others --exclude-standard -- '*.swift'

# Runs an xcodebuild action for each shared scheme. Without Xcode there is no xcodebuild, and the
# SwiftPM build and tests cover the package.
[private]
xcode action:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    source Scripts/Platform/environment.sh
    if (( ! OJD_HAS_XCODE )); then
        echo "Skipped the Xcode schemes: xcodebuild ships only with Xcode."
        exit 0
    fi
    for project in *.xcodeproj; do
        for scheme in "$project"/xcshareddata/xcschemes/*.xcscheme; do
            xcodebuild {{ action }} -quiet -project "$project" -scheme "$(basename "$scheme" .xcscheme)" \
                -destination "platform=macOS" -derivedDataPath {{ derived }} {{ xcode_settings }}
        done
    done
