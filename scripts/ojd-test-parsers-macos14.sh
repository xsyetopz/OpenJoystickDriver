#!/usr/bin/env bash
# macOS 14-compatible focused parser regression harness.
#
# Swift Testing is currently unusable on the local Swift 6.2.4/Xcode 26 setup
# because _Testing_Foundation requires macOS 26 while package tests compile for
# macOS 14. This harness builds a plain executable instead.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SWIFTUSB_DIR="$PROJECT_DIR/../SwiftUSB"
HARNESS_DIR="${OJD_MACOS14_HARNESS_DIR:-/tmp/ojd-parser-harness}"
SCRATCH_DIR="${OJD_MACOS14_HARNESS_SCRATCH:-/tmp/ojd-parser-harness-build}"
CACHE_DIR="${OJD_MACOS14_HARNESS_CACHE:-/tmp/ojd-parser-harness-cache}"
MODULE_CACHE_DIR="${OJD_MACOS14_HARNESS_MODULE_CACHE:-/tmp/ojd-clang-module-cache}"

if [[ ! -d "$SWIFTUSB_DIR" ]]; then
  echo "ERROR: local SwiftUSB checkout not found at $PROJECT_DIR/../SwiftUSB" >&2
  echo "Set up the sibling SwiftUSB checkout before running the macOS 14 parser harness." >&2
  exit 2
fi
SWIFTUSB_DIR="$(cd "$SWIFTUSB_DIR" && pwd)"

mkdir -p "$HARNESS_DIR/Sources/OJDParserHarness"
mkdir -p "$SCRATCH_DIR"
mkdir -p "$CACHE_DIR"
mkdir -p "$MODULE_CACHE_DIR"

cat > "$HARNESS_DIR/Package.swift" << PACKAGE_SWIFT
// swift-tools-version:6.2
import PackageDescription

let package = Package(
  name: "OJDParserHarness",
  platforms: [.macOS(.v14)],
  dependencies: [
    .package(path: "$PROJECT_DIR")
  ],
  targets: [
    .executableTarget(
      name: "OJDParserHarness",
      dependencies: [.product(name: "OpenJoystickDriverKit", package: "OpenJoystickDriver")]
    )
  ]
)
PACKAGE_SWIFT

cp "$SCRIPT_DIR/ojd-parser-harness-main.swift" "$HARNESS_DIR/Sources/OJDParserHarness/main.swift"

SWIFT_TARGET="${OJD_MACOS14_SWIFT_TARGET:-$(uname -m)-apple-macosx14.0}"

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE_DIR"
export MACOSX_DEPLOYMENT_TARGET=14.0
export OJD_USE_LOCAL_SWIFTUSB=1
swift run \
  --disable-sandbox \
  --package-path "$HARNESS_DIR" \
  --scratch-path "$SCRATCH_DIR" \
  --cache-path "$CACHE_DIR" \
  --triple "$SWIFT_TARGET" \
  -Xswiftc -target \
  -Xswiftc "$SWIFT_TARGET" \
  OJDParserHarness
