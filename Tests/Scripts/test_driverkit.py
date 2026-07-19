import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DriverKitGenerationTests(unittest.TestCase):
    def test_generator_target_owns_swifterkit_generation(self):
        manifest = (ROOT / "Package.swift").read_text()
        generator = (ROOT / "Sources/DriverKitGenerator/main.swift").read_text()

        self.assertIn('name: "DriverKitGenerator"', manifest)
        self.assertIn('"OpenJoystickDriverRelay"', manifest)
        self.assertIn('.product(name: "SwifterKit"', manifest)
        self.assertIn("DriverExtensionGenerator.generate", generator)
        self.assertIn("OpenJoystickDriverRelayConfiguration.driver", generator)
        self.assertNotIn("OpenJoystickDriverKit", generator)

    def test_generated_metadata_and_entitlement_validation_is_exact(self):
        tooling = (ROOT / "scripts/build-tools/driverkit.sh").read_text()

        for value in (
            "com.openjoystickdriver.VirtualHIDDevice",
            "SwifterKitRuntimeService",
            "com.apple.developer.driverkit.family.hid.device",
            "com.apple.developer.driverkit.transport.hid",
            "com.apple.developer.driverkit.family.hid.eventservice",
            "com.apple.developer.driverkit.allow-any-userclient-access",
        ):
            self.assertIn(value, tooling)
        self.assertIn('PRODUCT_NAME="$DRIVERKIT_PRODUCT_NAME"', tooling)
        self.assertNotIn("plutil -replace CFBundleVersion", tooling)

    def test_host_entitlements_use_exact_userclient_allowlist(self):
        entitlements = plistlib.loads(
            (ROOT / "Sources/OpenJoystickDriver/App/Host.entitlements").read_bytes()
        )

        self.assertEqual(
            entitlements["com.apple.developer.driverkit.userclient-access"],
            ["com.openjoystickdriver.VirtualHIDDevice"],
        )
        self.assertNotIn(
            "com.apple.developer.driverkit.allow-any-userclient-access", entitlements
        )

    def test_cli_routes_generation_without_a_manual_project_fallback(self):
        dispatcher = (ROOT / "scripts/ojd").read_text()
        build = (ROOT / "scripts/build-tools/build.sh").read_text()
        bundles = (ROOT / "scripts/build-tools/bundles.sh").read_text()

        self.assertIn('"$SCRIPT_DIR/build-tools/driverkit.sh" generate', dispatcher)
        self.assertIn('source "$SCRIPT_DIR/driverkit.sh"', build)
        self.assertNotIn("DriverKitExtension", build + bundles)
        self.assertFalse((ROOT / "DriverKitExtension").exists())

    def test_version_source_is_generator_input_not_a_generated_plist_edit(self):
        tooling = (ROOT / "scripts/build-tools/driverkit.sh").read_text()
        bundles = (ROOT / "scripts/build-tools/bundles.sh").read_text()
        defaults = (ROOT / "scripts/platform/environment.sh").read_text()
        bump = (ROOT / "scripts/release/bump-version.sh").read_text()

        self.assertIn("OJD_BUNDLE_SHORT_VERSION", tooling)
        self.assertIn("OJD_BUNDLE_VERSION", tooling)
        self.assertIn("--short-version", tooling)
        self.assertIn("--build-version", tooling)
        self.assertIn("OJD_DEFAULT_BUNDLE_SHORT_VERSION", tooling)
        self.assertIn("OJD_DEFAULT_BUNDLE_SHORT_VERSION", bundles)
        self.assertEqual(defaults.count('OJD_DEFAULT_BUNDLE_SHORT_VERSION="'), 1)
        self.assertNotIn("0.5.0-alpha.5", tooling + bundles)
        self.assertIn("shared app and DriverKit default short version", bump)
        self.assertNotIn("DriverKitExtension/Info.plist", bump)
        self.assertNotIn("plutil -replace", tooling)

    def test_signing_checks_profiles_and_signed_bundles_without_allow_any(self):
        tooling = (ROOT / "scripts/build-tools/driverkit.sh").read_text()

        self.assertIn("_require_host_access_profile", tooling)
        self.assertIn("_require_driverkit_profile", tooling)
        self.assertIn("_require_signed_host_access", tooling)
        self.assertIn("_require_signed_driverkit_entitlements", tooling)
        self.assertGreaterEqual(tooling.count('decode_provisioning_profile "$profile"'), 2)
        self.assertNotIn("security cms -D -i", tooling)
        self.assertGreaterEqual(
            tooling.count("com.apple.developer.driverkit.allow-any-userclient-access"),
            4,
        )
        self.assertIn('verify_profile_cert "$profile" "$identity"', tooling)
        self.assertIn('--sign "$identity"', tooling)

    def test_swifterkit_branch_is_locked_to_reviewed_revision(self):
        import json

        manifest = (ROOT / "Package.swift").read_text()
        self.assertIn(
            '.package(url: "https://github.com/xsyetopz/SwifterKit.git", branch: "main")',
            manifest,
        )

        pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
        pin = next(item for item in pins if item["identity"] == "swifterkit")

        self.assertEqual(pin["location"], "https://github.com/xsyetopz/SwifterKit.git")
        self.assertEqual(pin["state"]["branch"], "main")
        self.assertEqual(
            pin["state"]["revision"],
            "564a77c050561c286ba81198ad56518dad069c17",
        )

    def test_swiftusb_release_pin_contains_lifetime_fix(self):
        import json

        manifest = (ROOT / "Package.swift").read_text()
        self.assertIn(
            '.package(url: "https://github.com/xsyetopz/SwiftUSB.git", exact: "0.1.2")',
            manifest,
        )

        pins = json.loads((ROOT / "Package.resolved").read_text())["pins"]
        pin = next(item for item in pins if item["identity"] == "swiftusb")
        self.assertEqual(pin["state"]["version"], "0.1.2")
        self.assertEqual(
            pin["state"]["revision"],
            "2bdafcba623e437c02b669eb9ddcb794d94ba1fb",
        )

    def test_swifterkit_imports_are_confined_to_relay_and_generator(self):
        imports = []
        for path in (ROOT / "Sources").rglob("*.swift"):
            if "import SwifterKit" in path.read_text():
                imports.append(path.relative_to(ROOT / "Sources").parts[0])

        self.assertEqual(set(imports), {"DriverKitGenerator", "OpenJoystickDriverRelay"})

    def test_local_override_is_development_only_and_rejected_by_validation(self):
        script = """
source scripts/platform/environment.sh
source scripts/build-tools/driverkit.sh
OJD_USE_LOCAL_SWIFTERKIT=1
OJD_ENV=dev
CI=false
_reject_local_swifterkit
if ( _require_pinned_swifterkit ) >/dev/null 2>&1; then exit 9; fi
CI=true
if ( _reject_local_swifterkit ) >/dev/null 2>&1; then exit 7; fi
OJD_ENV=release
if ( _reject_local_swifterkit ) >/dev/null 2>&1; then exit 8; fi
"""
        result = subprocess.run(
            ["bash", "-c", script], cwd=ROOT, check=False, capture_output=True, text=True
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_validation_allows_no_tracked_manual_or_generated_artifacts(self):
        script = """
PROJECT_DIR="$PWD"
OJD_BUNDLE_SHORT_VERSION=1.0.0
OJD_BUNDLE_VERSION=1
source scripts/build-tools/driverkit.sh
generate_driverkit_project() {
  [[ ! -e "$1" ]] || return 1
  mkdir -p "$1"
}
_validate_driverkit_metadata() { :; }
_validate_host_entitlement_source() { :; }
_driverkit_xcodebuild() {
  local configuration="$1"
  local product="$DRIVERKIT_DERIVED_DATA/Build/Products/${configuration}-driverkit/${DRIVERKIT_PRODUCT_NAME}.dext"
  mkdir -p "$product"
  touch "$product/$DRIVERKIT_PRODUCT_NAME"
}
_validate_driverkit_product() { :; }
lipo() { printf 'arm64 x86_64\\n'; }
validate_driverkit
"""
        result = subprocess.run(
            ["bash", "-c", script], cwd=ROOT, check=False, capture_output=True, text=True
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_legacy_profile_mode_omits_generated_userclient_access_and_rejects_release(self):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            profile = temporary / "host.plist"
            output = temporary / "resolved.plist"
            signed_legacy = temporary / "signed-legacy.plist"
            profile.write_bytes(
                plistlib.dumps(
                    {
                        "Entitlements": {
                            "com.apple.developer.driverkit.userclient-access": [
                                "com.openjoystickdriver.VirtualHIDDevice\n"
                                "com.openjoystickdriver.daemon"
                            ]
                        }
                    }
                )
            )
            script = f"""
PROJECT_DIR={ROOT!s}
OJD_ENV=dev
OJD_USE_LEGACY_DRIVERKIT_PROFILE=1
CI=false
DEVELOPMENT_TEAM=ABCDEF1234
die() {{ echo "ERROR: $*" >&2; exit 2; }}
decode_provisioning_profile() {{ cat "$1"; }}
resolve_entitlements() {{ sed "s/\\${{DEVELOPMENT_TEAM}}/$DEVELOPMENT_TEAM/g" "$1" > "$2"; }}
codesign() {{ cat "$SIGNED_ENTITLEMENTS"; }}
source scripts/build-tools/driverkit.sh
DRIVERKIT_ROOT={temporary!s}/driverkit
GUI_ENTITLEMENTS_TEMPLATE=Sources/OpenJoystickDriver/App/Host.entitlements
_resolve_host_entitlements {profile!s} {output!s}
python3 - {output!s} <<'PY'
import plistlib, sys
value = plistlib.loads(open(sys.argv[1], "rb").read())
assert "com.apple.developer.driverkit.userclient-access" not in value
assert value["com.apple.developer.hid.virtual.device"] is True
PY
SIGNED_ENTITLEMENTS={output!s}
_require_signed_host_access ignored.app {profile!s}
python3 - {output!s} {signed_legacy!s} <<'PY'
import plistlib, sys
value = plistlib.loads(open(sys.argv[1], "rb").read())
value["com.apple.developer.driverkit.userclient-access"] = [
    "com.openjoystickdriver.VirtualHIDDevice\\ncom.openjoystickdriver.daemon"
]
open(sys.argv[2], "wb").write(plistlib.dumps(value))
PY
SIGNED_ENTITLEMENTS={signed_legacy!s}
if ( _require_signed_host_access ignored.app {profile!s} ) >/dev/null 2>&1; then exit 7; fi
OJD_ENV=release
if ( _legacy_driverkit_profile_enabled ) >/dev/null 2>&1; then exit 9; fi
OJD_ENV=dev
CI=true
if ( _legacy_driverkit_profile_enabled ) >/dev/null 2>&1; then exit 8; fi
"""
            result = subprocess.run(
                ["bash", "-c", script],
                cwd=ROOT,
                check=False,
                capture_output=True,
                text=True,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Compatibility output remains available", result.stderr)
            self.assertIn("relay diagnostics are unavailable", result.stderr)

    def test_universal_binary_gate_uses_lipo_architecture_names(self):
        tooling = (ROOT / "scripts/build-tools/driverkit.sh").read_text()

        self.assertIn('lipo -archs "$product/$DRIVERKIT_PRODUCT_NAME"', tooling)
        self.assertIn('" arm64 "', tooling)
        self.assertIn('" x86_64 "', tooling)
        self.assertNotIn("universal binary with 2 architectures", tooling)

    def test_development_sparkle_signing_handles_empty_optional_arguments(self):
        bundles = (ROOT / "scripts/build-tools/bundles.sh").read_text()

        safe = '${sparkle_extra_args[@]+"${sparkle_extra_args[@]}"}'
        self.assertEqual(bundles.count(safe), 5)
        self.assertNotIn('"${sparkle_extra_args[@]}"', bundles.replace(safe, ""))

    def test_generator_cli_requires_versions_and_destination(self):
        generator = (ROOT / "Sources/DriverKitGenerator/main.swift").read_text()

        self.assertIn('case "--output"', generator)
        self.assertIn('case "--short-version"', generator)
        self.assertIn('case "--build-version"', generator)
        self.assertIn("throw ArgumentError.usage", generator)


if __name__ == "__main__":
    unittest.main()
