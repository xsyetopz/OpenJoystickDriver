# Monterey XUSB verify (CI package)

Local staging for GitHub Actions workflow `.github/workflows/monterey-xusb-verify.yml`.

| File | Role |
| --- | --- |
| `0001-xbox360-absolute-observation.patch` | Clean diff of parser + tests |
| `MAINTAINER-REQUEST.md` | Ask maintainers for a signed tester DMG |
| `write-signing-assessment.py` | CI script → `SIGNING-ASSESSMENT.md` artifact |
| `README.md` | This note |

## What CI can prove
- Swift ≥ 6.3 on `macos-26-intel`
- `swift test --filter Xbox360ParserTests`
- `swift build --arch x86_64` with `MACOSX_DEPLOYMENT_TARGET=12.0`

## What CI cannot prove
- Virtual HID / GeForce NOW on Monterey (needs `com.apple.developer.hid.virtual.device` on a maintainer-signed app)

## Publish / run (needs your confirmation)
1. Fork `xsyetopz/OpenJoystickDriver` to your GitHub account (do not push secrets).
2. Push branch `monterey-xusb-absolute-observation` with the patch + this CI package.
3. Run **Actions → Monterey XUSB verify → Run workflow**.
4. Download artifact `monterey-xusb-verify-*`.
5. Open a PR upstream using `MAINTAINER-REQUEST.md` and attach CI results.
