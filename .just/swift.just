# Managed by swift-bedrock. Put project recipes in project.just.

set shell := ["bash", "-euo", "pipefail", "-c"]
set working-directory := ".."

bedrock := "swift run --quiet --package-path BuildTools swift-bedrock"
derived := ".build/xcode"

# SwiftPM 6.4 has no switch for the compiler's cache, so these flags turn it on, in a
# cache every checkout on the Mac shares. SwiftPM names the package after its folder,
# so worktrees reuse each other's results when their folders share a name. With C++
# interop, the 6.4 compiler warns about its own module map once caching is on, and
# warnings fail the build, so a repository with C++ builds uncached, in Xcode too.
cxx := path_exists(justfile_directory() / ".just" / "cpp.just")
cas := env("BEDROCK_SWIFT_CACHE", cache_directory() / "swift-bedrock" / "swiftpm")
cache_gib := env("BEDROCK_SWIFT_CACHE_GIB", "20")
cached := if os() != "macos" { "" } else if env("CI", "") != "" { "" } else if cxx == "true" { "" } else { "-Xswiftc -cache-compile-job -Xswiftc -cas-path -Xswiftc " + quote(cas) + " -Xswiftc -scanner-prefix-map-sdk -Xswiftc /^sdk -Xswiftc -scanner-prefix-map-toolchain -Xswiftc /^toolchain -Xswiftc -scanner-prefix-map-paths -Xswiftc " + quote(parent_directory(justfile_directory())) + " -Xswiftc /^src" }

# Xcode leaves Bedrock.xcconfig off Swift package targets, so the command line repeats its
# cache settings for them.
xcode_cache := if cxx == "true" { "COMPILATION_CACHE_ENABLE_CACHING=NO" } else { "COMPILATION_CACHE_ENABLE_CACHING=YES COMPILATION_CACHE_CAS_PATH=" + quote(cache_directory() / "swift-bedrock" / "xcode") + " SWIFT_ENABLE_PREFIX_MAPPING=YES SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES CLANG_ENABLE_PREFIX_MAPPING=YES CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES" }

# Install the Swift toolchain from .swift-version and SwiftLint, then build the tools.
setup:
    if command -v swiftly >/dev/null; then swiftly install; fi
    if ! command -v swiftlint >/dev/null; then brew install swiftlint; fi
    swift package --package-path BuildTools resolve

# Format the Swift code.
format:
    just swift::files | xargs -0 -r swift format format --in-place --parallel

# Fail if the Swift code is not formatted.
format-check:
    just swift::files | xargs -0 -r swift format lint --strict --parallel

# Build the package, its tests, and each shared Xcode scheme, without running them.
typecheck:
    just swift::trim-cache
    if [[ -f Package.swift ]]; then swift build --build-tests {{ cached }}; fi
    just swift::xcode build-for-testing

# Run SwiftLint.
lint:
    swiftlint lint --strict --quiet

# Convert XCTest unit tests and apply SwiftLint's and swift-format's fixes.
lint-fix:
    {{ bedrock }} guard --fix
    swiftlint lint --fix --quiet
    just swift::format

# Run the Swift Testing tests, then each shared Xcode scheme's tests. A package
# without a test target passes, as it does for Bun and Rust.
test:
    just swift::trim-cache
    if [[ -f Package.swift ]] && swift package dump-package | grep -q '"type" : "test"'; then swift test --parallel {{ cached }}; fi
    just swift::xcode test

# Report XCTest outside UI tests, settings the manifest loses, foreign tools, and drift.
guard:
    {{ bedrock }} guard

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
trim-cache:
    #!/usr/bin/env bash
    set -euo pipefail
    cas={{ quote(cas) }}
    # The 6.4 compiler sets no size limit, so a cache past it starts over. A build still
    # running keeps the files it has open.
    if [[ -n {{ quote(cached) }} && -d "$cas" ]] && (( $(du -sk "$cas" | cut -f1) > {{ cache_gib }} * 1024 * 1024 )); then
        # Another checkout may be trimming it too.
        old="$cas.old.$$"
        if mv "$cas" "$old" 2>/dev/null; then
            rm -rf -- "$old" &
        fi
    fi

[private]
files:
    git ls-files -z --cached --others --exclude-standard -- '*.swift'

[private]
xcode action:
    #!/usr/bin/env bash
    set -euo pipefail
    shopt -s nullglob
    for project in *.xcodeproj; do
        for scheme in "$project"/xcshareddata/xcschemes/*.xcscheme; do
            xcodebuild {{ action }} -quiet -project "$project" -scheme "$(basename "$scheme" .xcscheme)" \
                -destination "platform=macOS" -derivedDataPath {{ derived }} {{ xcode_cache }}
        done
    done
