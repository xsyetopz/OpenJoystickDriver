from __future__ import annotations

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from Scripts.Platform import swift_sdk
from Scripts.Platform.swift_sdk import (
    FOUNDATION_MODULE,
    SWIFTUI_MODULES,
    installed_sdks,
    interface_version,
    parse_version,
    select_sdk,
)


def make_sdk(root: Path, name: str, compiler: str) -> Path:
    sdk = root / name
    module = sdk / FOUNDATION_MODULE
    module.mkdir(parents=True)
    (module / "arm64e-apple-macos.swiftinterface").write_text(
        "// swift-interface-format-version: 1.0\n"
        f"// swift-compiler-version: Apple Swift version {compiler} effective-5.10\n"
        "import Swift\n",
        encoding="utf-8",
    )
    return sdk


def add_state_macro(sdk: Path) -> None:
    module = sdk / SWIFTUI_MODULES[0]
    module.mkdir(parents=True)
    (module / "arm64e-apple-macos.swiftinterface").write_text(
        'public macro State() = #externalMacro(module: "SwiftUIMacros", type: "StateMacro")\n',
        encoding="utf-8",
    )


class SwiftSDKTests(unittest.TestCase):
    def test_parses_apple_and_swift_org_versions(self) -> None:
        self.assertEqual(
            parse_version("Apple Swift version 6.4 (swiftlang-6.4.0.34.1)"), (6, 4)
        )
        self.assertEqual(
            parse_version("Apple Swift version 6.3.3 (swift-6.3.3-RELEASE)"), (6, 3)
        )
        self.assertIsNone(parse_version("no version here"))

    def test_reads_the_interface_compiler_version(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sdk = make_sdk(Path(directory), "MacOSX27.sdk", "6.4")
            self.assertEqual(interface_version(sdk), (6, 4))
            self.assertIsNone(interface_version(Path(directory) / "Missing.sdk"))

    def test_keeps_the_preferred_sdk_the_compiler_reads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            older = make_sdk(root, "MacOSX26.sdk", "6.3.2")
            newer = make_sdk(root, "MacOSX27.sdk", "6.4")
            self.assertEqual(select_sdk((6, 4), newer, [older, newer]), newer)
            self.assertEqual(select_sdk((6, 3), older, [older, newer]), older)

    def test_older_compiler_gets_the_newest_sdk_it_reads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            oldest = make_sdk(root, "MacOSX15.sdk", "6.1")
            older = make_sdk(root, "MacOSX26.sdk", "6.3.2")
            newer = make_sdk(root, "MacOSX27.sdk", "6.4")
            self.assertEqual(select_sdk((6, 3), newer, [oldest, older, newer]), older)

    def test_no_readable_sdk_selects_nothing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            newer = make_sdk(Path(directory), "MacOSX27.sdk", "6.4")
            self.assertIsNone(select_sdk((6, 3), newer, [newer]))

    def test_installed_sdks_resolve_symlinks_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            sdk = make_sdk(root, "MacOSX27.0.sdk", "6.4")
            (root / "MacOSX.sdk").symlink_to(sdk.name)
            self.assertEqual(installed_sdks([root]), [sdk.resolve()])

    def test_skips_an_sdk_whose_state_macro_has_no_plugin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # Arrange
            root = Path(directory)
            plugins = root / "toolchain-plugins"
            plugins.mkdir()
            older = make_sdk(root / "SDKs", "MacOSX26.sdk", "6.3.2")
            newer = make_sdk(root / "SDKs", "MacOSX27.sdk", "6.4")
            add_state_macro(newer)

            # Act
            selected = select_sdk((6, 4), newer, [older, newer], plugins)

            # Assert
            self.assertEqual(selected, older)

    def test_keeps_an_sdk_whose_platform_has_the_state_plugin(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # Arrange
            root = Path(directory)
            plugins = root / "toolchain-plugins"
            plugins.mkdir()
            sdks = root / "Platform" / "Developer" / "SDKs"
            newer = make_sdk(sdks, "MacOSX27.sdk", "6.4")
            add_state_macro(newer)
            platform_plugins = (
                sdks.parent / "usr" / "lib" / "swift" / "host" / "plugins"
            )
            platform_plugins.mkdir(parents=True)
            (platform_plugins / "libSwiftUIMacros.dylib").touch()

            # Act
            selected = select_sdk((6, 4), newer, [newer], plugins)

            # Assert
            self.assertEqual(selected, newer)

    def test_explicit_sdk_with_an_unexpandable_macro_is_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # Arrange
            root = Path(directory)
            sdk = make_sdk(root / "SDKs", "MacOSX27.sdk", "6.4")
            add_state_macro(sdk)
            errors = io.StringIO()

            # Act
            with (
                mock.patch.object(swift_sdk, "compiler_version", return_value=(6, 4)),
                mock.patch.object(swift_sdk, "toolchain_plugins", return_value=root),
                contextlib.redirect_stderr(errors),
            ):
                status = swift_sdk.main(["/stub/swift", str(sdk), "1"])

            # Assert
            self.assertEqual(status, 1)
            self.assertIn("declares SwiftUI macros State", errors.getvalue())

    def test_sdk_roots_argument_limits_the_search(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            # Arrange
            root = Path(directory)
            preferred = make_sdk(root / "Preferred", "MacOSX28.sdk", "6.5")
            limited = make_sdk(root / "Limited", "MacOSX26.sdk", "6.3.2")
            output = io.StringIO()

            # Act
            with (
                mock.patch.object(swift_sdk, "compiler_version", return_value=(6, 4)),
                mock.patch.object(swift_sdk, "toolchain_plugins", return_value=None),
                contextlib.redirect_stdout(output),
                contextlib.redirect_stderr(io.StringIO()),
            ):
                status = swift_sdk.main(
                    ["/stub/swift", str(preferred), "0", str(root / "Limited")]
                )

            # Assert
            self.assertEqual(status, 0)
            self.assertEqual(output.getvalue().strip(), str(limited.resolve()))

    def test_a_compiler_without_a_version_is_an_error(self) -> None:
        errors = io.StringIO()
        with (
            mock.patch.object(swift_sdk, "compiler_version", return_value=None),
            contextlib.redirect_stderr(errors),
        ):
            status = swift_sdk.main(["/stub/swift", "/stub/MacOSX.sdk", "0"])
        self.assertEqual(status, 1)
        self.assertIn("names no Swift version", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
