# Environment files

Repository scripts load exactly one optional local file from the project root:

- `.env.dev` for development commands (the default);
- `.env.release` for publisher release, notarization, and packaging commands.

`OJD_ENV` selects `dev` or `release`. Other values fail immediately. Generic `.env` and `scripts/.env*` files are not loaded. Start from the matching `.example` file or run `./scripts/ojd signing configure`. Audit structure without exposing values:

```bash
./scripts/ojd env audit
```

The examples are annotated output templates, not a source for identities,
profiles, Team IDs, or credentials. Read [Signing assets](signing.md) before
creating either local file. Development configuration requires the two
development profiles and an Apple Development identity; publisher-only
Developer ID assets are optional and do not block `.env.dev` generation.

The signing configurator updates recognized signing keys in the central files while preserving unrelated recognized publisher keys such as notarization and Sparkle credentials. Never commit actual `.env.dev` or `.env.release` files.

## GitHub Actions secrets

`.github/workflows/release.yml` remains the source of truth for GitHub Secret names. Only inputs used by the single-app release remain:

- `APPLE_DEVELOPMENT_CERT_BASE64`
- `DEVELOPER_ID_APPLICATION_CERT_BASE64`
- `CERTIFICATE_SECRET`
- `KEYCHAIN_SECRET`
- `OPENJOYSTICKDRIVER_GUI_DEVID_PROFILE_BASE64`
- `OPENJOYSTICKDRIVER_DEXT_PROFILE_BASE64`
- `NOTARIZE_APPLE_ID`
- `NOTARIZE_PASSWORD`
- `SPARKLE_PUBLIC_ED_KEY`
- `SPARKLE_ED_PRIVATE_KEY`

Workflow secrets are injected directly by GitHub; CI does not create or depend on a local `.env` file.

The GUI provisioning profile must authorize the host app's exact
`com.apple.developer.driverkit.userclient-access` allowlist for
`com.openjoystickdriver.VirtualHIDDevice`. The DriverKit profile authorizes the
generated relay. The build rejects an allow-any user-client entitlement in either
artifact.

## Local migration backup

Before this consolidation, the existing local files were copied to the ignored, permission-restricted `.env-backup-20260712-164907/` directory. Filenames encode original paths using `scripts__` for the former `scripts/` prefix. Transfer only keys that remain in the appropriate root example; obsolete keys should stay archived.
