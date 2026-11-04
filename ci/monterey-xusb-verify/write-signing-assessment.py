#!/usr/bin/env python3
"""Emit a signing/capability assessment for CI artifacts. No secrets are read."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument("--output", required=True)
  parser.add_argument("--repo-root", required=True)
  args = parser.parse_args()

  root = Path(args.repo_root)
  host_ents = root / "Sources/OpenJoystickDriver/App/Host.entitlements"
  signing_doc = root / "docs/development/signing.md"
  host_text = host_ents.read_text(encoding="utf-8") if host_ents.is_file() else ""
  has_virtual = "com.apple.developer.hid.virtual.device" in host_text

  body = f"""# Signing assessment — Monterey XUSB verify

## Scope
This job verifies the Xbox 360 absolute-observation parser fix on
`macos-26-intel` with Swift ≥ 6.3 and `MACOSX_DEPLOYMENT_TARGET=12.0`.

It does **not** produce a Virtual HID-capable app binary.

## Required host entitlements (from project docs)
Source of truth: `docs/development/signing.md` and `Sources/OpenJoystickDriver/App/Host.entitlements`.

| Entitlement | Purpose | Present in Host.entitlements |
| --- | --- | --- |
| `com.apple.developer.hid.virtual.device` | CoreHID / IOKit virtual gamepad for consumers (GFN, SDL, browsers via virtual device) | {"yes" if has_virtual else "NO — unexpected"} |
| `com.apple.developer.system-extension.install` | Install XboxUSBDevice DEXT | authored |
| `com.apple.developer.driverkit.userclient-access` → `com.openjoystickdriver.XboxUSBDevice` | Talk to DEXT | authored |

Wired clone `045E:028E` uses **direct IOUSBHost** (XUSB). The USB DEXT entitlement
allowlist is for first-party Microsoft GIP pairs only and is **not** required to
claim this pad. Virtual HID still requires the **host** restricted entitlement.

## Options evaluated

### A. Maintainer Developer ID + notarized tester DMG (viable)
- Uses Apple-issued profiles that include `com.apple.developer.hid.virtual.device`.
- Project path: `just package-tester` / release workflow with org secrets.
- This is the only path that can honestly deliver Virtual HID on Monterey for GFN.
- CI here cannot do this without the maintainer's Developer ID material (must not be placed in a fork by contributors).

### B. Contributor Apple Development signing (not available here)
- Needs the contributor's Mac UDID in the development profile (macOS 15+ AMFI notes in signing.md; Monterey still needs a real profile for restricted entitlements).
- Requires Apple team membership for `com.openjoystickdriver` capabilities — contributors do not get the project's restricted entitlement grant by default.
- Not used in this workflow; no certificates uploaded.

### C. Ad-hoc / unsigned local build (insufficient for goal)
- Project evidence (`docs/external/OpenJoystickDriver/issue-23.md`, PR #27 comments): ad-hoc binaries log
  `Compatibility virtual gamepad unavailable: Missing entitlement: com.apple.developer.hid.virtual.device`.
- AMFI will not honour a forged restricted entitlement on a non-provisioned signature.
- **Not claimed as a GeForce NOW solution.**

### D. Disable SIP / AMFI / inject entitlements (forbidden)
- Explicitly out of scope for this work and for the user machine.

## CI secrets policy
This workflow reads **no** signing secrets (`OPENJOYSTICKDRIVER_*`, certificates, profiles, notary credentials).
Artifact contents are logs, patch text, and this assessment only.

## Conclusion
Parser unit tests + x86_64 / macOS 12 kit build can be proven in CI.
A working Virtual HID build for Monterey GFN requires a **maintainer-signed** tester or release that includes the Xbox360 absolute-observation patch.

See `MAINTAINER-REQUEST.md`.

Host entitlements path exists: `{host_ents.is_file()}`
Signing doc exists: `{signing_doc.is_file()}`
"""
  Path(args.output).write_text(body, encoding="utf-8")
  print(f"Wrote {args.output}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
