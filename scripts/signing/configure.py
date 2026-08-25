import os
import pathlib
import plistlib
import re
import subprocess
import sys

project_dir = pathlib.Path(os.environ.get("PROJECT_DIR", "."))
script_dir = pathlib.Path(os.environ.get("SCRIPT_DIR", "scripts"))

dev_env = pathlib.Path(os.environ.get("DEV_ENV", str(script_dir / ".env.dev")))
rel_env = pathlib.Path(os.environ.get("REL_ENV", str(script_dir / ".env.release")))

gui_dev_profile = os.path.expanduser(os.environ.get("GUI_DEV_PROFILE", ""))
gui_devid_profile = os.path.expanduser(os.environ.get("GUI_DEVID_PROFILE", ""))
dext_profile = os.path.expanduser(os.environ.get("DEXT_PROFILE", ""))
dext_devid_profile = os.path.expanduser(os.environ.get("DEXT_DEVID_PROFILE", ""))
signing_mode = os.environ.get("OJD_SIGNING_MODE", "all")
if signing_mode not in {"all", "development", "release"}:
    raise SystemExit("ERROR: OJD_SIGNING_MODE must be all, development, or release")


def run(args, *, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check)


def must_exist(path: str, label: str):
    if not os.path.isfile(path):
        raise SystemExit(f"ERROR: {label} not found: {path}")


def decode_profile(path: str) -> dict:
    # Prefer Apple tooling when it works, but keep an OpenSSL fallback because
    # `security cms -D` can fail on some machines for `.provisionprofile`.
    p = subprocess.run(
        ["security", "cms", "-D", "-i", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=False,
    )
    raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        p = subprocess.run(
            ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=False,
        )
        raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        raise SystemExit(
            "ERROR: Could not decode provisioning profile.\n"
            f"  profile: {path}\n"
            "Fix: reinstall/regenerate the profile and re-run `./scripts/ojd signing install-profiles`.\n"
            'Debug (safe): `./scripts/ojd signing audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile`'
        )
    if b"<?xml" in raw:
        raw = raw[raw.index(b"<?xml") :]
    try:
        return plistlib.loads(raw)
    except Exception:
        raise SystemExit(
            "ERROR: Provisioning profile decoded, but plist parsing failed.\n"
            f"  profile: {path}\n"
            "Fix: regenerate the profile in the Developer portal and reinstall it."
        )


def sha1_fingerprint(der_bytes: bytes) -> str:
    p = subprocess.run(
        ["openssl", "x509", "-inform", "DER", "-noout", "-fingerprint", "-sha1"],
        input=der_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=True,
    )
    # output: SHA1 Fingerprint=AA:BB:...
    s = p.stdout.decode("utf-8", "replace").strip()
    if "=" not in s:
        raise RuntimeError("unexpected openssl fingerprint output")
    return s.split("=", 1)[1].replace(":", "").lower()


def embedded_cert_sha1_from_profile(path: str) -> str:
    obj = decode_profile(path)
    certs = obj.get("DeveloperCertificates") or []
    if not certs or not isinstance(certs[0], (bytes, bytearray)):
        raise SystemExit(
            f"ERROR: Could not extract DeveloperCertificates from profile: {path}"
        )
    return sha1_fingerprint(certs[0])


def pick_identity(prefix: str) -> str:
    override = os.environ.get(
        "APPLE_DEV_IDENTITY" if prefix == "Apple Development" else "DEVID_APP_IDENTITY",
        "",
    )
    if override:
        return override
    out = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    matches: list[str] = []
    for line in out.splitlines():
        m = re.search(r'"(' + re.escape(prefix) + r':[^\"]+)"', line)
        if m:
            matches.append(m.group(1))
    if not matches:
        raise SystemExit(
            f"ERROR: Missing Keychain identity: {prefix} (run `security find-identity -v -p codesigning`)"
        )
    return matches[0]


def team_id_from_profile(path: str) -> str:
    obj = decode_profile(path)
    team_ids = obj.get("TeamIdentifier") or []
    if team_ids and isinstance(team_ids[0], str) and team_ids[0]:
        return team_ids[0]
    ent = obj.get("Entitlements") or {}
    tid = ent.get("com.apple.developer.team-identifier")
    if isinstance(tid, str) and tid:
        return tid
    raise SystemExit(f"ERROR: Could not read TeamIdentifier from profile: {path}")


def profile_name(path: str) -> str:
    obj = decode_profile(path)
    name = obj.get("Name")
    return name if isinstance(name, str) else ""


dext_bundle_id = "com.openjoystickdriver.XboxUSBDevice"


# Prefer exact certificate match with provisioning profiles (handles multiple teams/idents cleanly).
def pick_identity_matching_profile(prefix: str, profile_path: str) -> str:
    override = os.environ.get(
        "APPLE_DEV_IDENTITY" if prefix == "Apple Development" else "DEVID_APP_IDENTITY",
        "",
    )
    if override:
        return override
    want = embedded_cert_sha1_from_profile(profile_path)
    out = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    if "0 valid identities found" in out:
        # In some environments `security` cannot read the keychain (sandbox, SSH, locked keychain).
        # We can still proceed by writing the identity as the embedded certificate SHA1.
        #
        # This keeps the scripts non-blocking, while the actual build will still fail
        # if the private key is missing or the keychain is inaccessible.
        print(
            "WARN: macOS reports 0 valid code-signing identities in Keychain.\n"
            "      Proceeding by using the provisioning profile's embedded certificate SHA1.\n"
            "      (The build will still fail if the matching private key isn't available.)\n"
            "Check the login keychain:\n"
            "  1) Unlock the 'login' keychain.\n"
            "  2) Ensure signing certs appear under 'My Certificates' with a private key underneath.\n"
            "  3) If needed, fix keychain permissions then log out/in:\n"
            '       chmod 700 "$HOME/Library/Keychains"\n'
            '       chmod 600 "$HOME/Library/Keychains/login.keychain-db"\n'
            "  4) Import Apple intermediates (WWDR + DeveloperIDG2CA) if certs show untrusted.\n",
            file=sys.stderr,
        )
        return want
    available_sha1s: list[str] = []
    for line in out.splitlines():
        # Format:  1) <sha1> "<identity>"
        m = re.search(
            r"^\s*\d+\)\s+([0-9A-Fa-f]{40})\s+\"(" + re.escape(prefix) + r":[^\"]+)\"",
            line,
        )
        if not m:
            continue
        got = m.group(1).lower()
        available_sha1s.append(got)
        if got == want:
            # Use the SHA1 identity instead of the display name.
            # This avoids confusing cases where the certificate's Subject CN
            # (and thus the Keychain display name) contains a stale/incorrect
            # suffix, while the certificate Subject OU and provisioning profile
            # TeamIdentifier are correct.
            return got
    profile_team = team_id_from_profile(profile_path)
    sha1_str = ", ".join(available_sha1s) if available_sha1s else "UNKNOWN"
    profile_base = os.path.basename(profile_path)
    raise SystemExit(
        f"ERROR: No {prefix} identity matches the certificate embedded in provisioning profile.\n"
        f"  profile: {profile_path}\n"
        f"  profile_team: {profile_team}\n"
        f"  profile_embedded_cert_sha1: {want}\n"
        f"  keychain_{prefix.replace(' ', '_').lower()}_sha1s: {sha1_str}\n"
        "\n"
        "Required identity:\n"
        f"  A Keychain identity named '{prefix}: ...' with SHA1 profile_embedded_cert_sha1.\n"
        "  The certificate must have its private key. Matching the Team ID alone is insufficient.\n"
        "  Apple Development identities do not satisfy Developer ID Application profiles.\n"
        "\n"
        "Check the profile and Keychain:\n"
        f"  1) Print the certificate embedded in the profile:\n"
        f'       ./scripts/ojd signing profile-info --full "$HOME/Library/MobileDevice/Provisioning Profiles/{profile_base}"\n'
        "  2) List identities that have private keys:\n"
        "       security find-identity -v -p codesigning\n"
        "  3) If the private key is already in Keychain, import the profile's embedded certificate:\n"
        f'       ./scripts/ojd signing import-embedded "$HOME/Library/MobileDevice/Provisioning Profiles/{profile_base}"\n'
        "  4) Otherwise, regenerate the profile in the Apple Developer portal and select an installed certificate.\n"
        '  5) Reinstall profiles: ./scripts/ojd signing install-profiles "$HOME/Documents/Profiles"\n'
    )


def shell_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def update_env_file(
    path: pathlib.Path,
    header: str,
    values: dict[str, str],
) -> None:
    existing = path.read_text(encoding="utf-8") if path.exists() else ""
    lines = existing.splitlines()
    seen: set[str] = set()
    next_lines: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        matched_key = None
        for key in values:
            if stripped.startswith((f"{key}=", f"export {key}=")):
                matched_key = key
                break
        if matched_key is None:
            next_lines.append(line)
            continue
        next_lines.append(f"{matched_key}={shell_quote(values[matched_key])}")
        seen.add(matched_key)
    missing = [key for key in values if key not in seen]
    if missing:
        if next_lines and next_lines[-1] != "":
            next_lines.append("")
        if header and header not in next_lines:
            next_lines.append(header)
        for key in missing:
            next_lines.append(f"{key}={shell_quote(values[key])}")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(next_lines).rstrip() + "\n", encoding="utf-8")


hid_entitlement = "com.apple.developer.hid.virtual.device"
production_usb = [
    {"idVendor": 1118, "idProduct": 721},
    {"idVendor": 1118, "idProduct": 746},
    {"idVendor": 1118, "idProduct": 2834},
    {"idVendor": 1118, "idProduct": 2816},
    {"idVendor": 1118, "idProduct": 739},
    {"idVendor": 1118, "idProduct": 2826},
    {"idVendor": 1118, "idProduct": 733},
]


def require_host_profile(path: str, label: str) -> None:
    entitlements = decode_profile(path).get("Entitlements") or {}
    expected = {
        "com.apple.developer.system-extension.install": True,
        hid_entitlement: True,
        "com.apple.developer.driverkit.userclient-access": [dext_bundle_id],
    }
    for key, value in expected.items():
        if entitlements.get(key) != value:
            raise SystemExit(
                f"ERROR: {label} entitlement mismatch for {key}: "
                f"expected {value!r}, got {entitlements.get(key)!r}"
            )
    if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
        raise SystemExit(f"ERROR: {label} grants allow-any DriverKit user-client access")


def require_dext_profile(path: str, label: str) -> None:
    entitlements = decode_profile(path).get("Entitlements") or {}
    if entitlements.get("com.apple.developer.driverkit") is not True:
        raise SystemExit(f"ERROR: {label} is missing the DriverKit base entitlement")
    actual_usb = entitlements.get("com.apple.developer.driverkit.transport.usb")
    if actual_usb != production_usb:
        raise SystemExit(
            f"ERROR: {label} USB entitlement does not match Apple's issued configuration: "
            f"{actual_usb!r}"
        )
    forbidden = (
        hid_entitlement,
        "com.apple.developer.driverkit.family.hid.device",
        "com.apple.developer.driverkit.transport.hid",
        "com.apple.developer.driverkit.family.hid.eventservice",
        "com.apple.developer.driverkit.allow-any-userclient-access",
    )
    for key in forbidden:
        if key in entitlements:
            raise SystemExit(f"ERROR: {label} contains forbidden entitlement {key}")


def configure_development() -> None:
    must_exist(gui_dev_profile, "GUI development provisioning profile")
    must_exist(dext_profile, "DriverKit development provisioning profile")
    require_host_profile(gui_dev_profile, "GUI development profile")
    require_dext_profile(dext_profile, "DriverKit development profile")
    dev_team = team_id_from_profile(gui_dev_profile)
    if team_id_from_profile(dext_profile) != dev_team:
        raise SystemExit("ERROR: development host and DEXT profiles use different teams")
    apple_dev_identity = pick_identity_matching_profile("Apple Development", dext_profile)
    if pick_identity_matching_profile("Apple Development", gui_dev_profile) != apple_dev_identity:
        raise SystemExit("ERROR: development host and DEXT profiles use different certificates")
    update_env_file(
        dev_env,
        "# Development signing (managed by ./scripts/ojd signing configure)",
        {
            "CODESIGN_IDENTITY": apple_dev_identity,
            "DEVELOPMENT_TEAM": dev_team,
            "DEXT_BUILD_IDENTITY": apple_dev_identity,
            "DEXT_BUILD_PROFILE": profile_name(dext_profile),
            "DEXT_PROVISIONING_PROFILE": dext_profile,
            "GUI_PROVISIONING_PROFILE": gui_dev_profile,
        },
    )
    print(f"Updated {dev_env}")


def configure_release(*, optional: bool) -> None:
    if optional and (not os.path.isfile(gui_devid_profile) or not os.path.isfile(dext_devid_profile)):
        print(
            "WARN: Publisher release signing was not configured because both Developer ID "
            "profiles are required. Development signing remains configured.",
            file=sys.stderr,
        )
        return
    must_exist(gui_devid_profile, "GUI Developer ID provisioning profile")
    must_exist(dext_devid_profile, "DriverKit Developer ID provisioning profile")
    require_host_profile(gui_devid_profile, "GUI Developer ID profile")
    require_dext_profile(dext_devid_profile, "DriverKit Developer ID profile")
    rel_team = team_id_from_profile(gui_devid_profile)
    if team_id_from_profile(dext_devid_profile) != rel_team:
        raise SystemExit("ERROR: Developer ID host and DEXT profiles use different teams")
    gui_devid_identity = pick_identity_matching_profile(
        "Developer ID Application", gui_devid_profile
    )
    dext_devid_identity = pick_identity_matching_profile(
        "Developer ID Application", dext_devid_profile
    )
    update_env_file(
        rel_env,
        "# Release signing (managed by ./scripts/ojd signing configure)",
        {
            "CODESIGN_IDENTITY": gui_devid_identity,
            "GUI_CODESIGN_IDENTITY": gui_devid_identity,
            "DEVELOPMENT_TEAM": rel_team,
            "DEXT_BUILD_IDENTITY": dext_devid_identity,
            "DEXT_BUILD_PROFILE": profile_name(dext_devid_profile),
            "DEXT_PROVISIONING_PROFILE": dext_devid_profile,
            "GUI_PROVISIONING_PROFILE": gui_devid_profile,
        },
    )
    print(f"Updated {rel_env}")


if signing_mode in {"all", "development"}:
    configure_development()
if signing_mode in {"all", "release"}:
    configure_release(optional=signing_mode == "all")
