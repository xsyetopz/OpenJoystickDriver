import argparse
import os
import pathlib
import plistlib
import subprocess
import sys

import profile_certs

profiles_dir = pathlib.Path.home() / "Library/MobileDevice/Provisioning Profiles"
gui_dev_profile = str(profiles_dir / "OpenJoystickDriver.provisionprofile")
gui_devid_profile = str(profiles_dir / "OpenJoystickDriver_DevID.provisionprofile")
dext_profile = str(profiles_dir / "OpenJoystickDriver_XboxUSBDevice.provisionprofile")
dext_devid_profile = str(
    profiles_dir / "OpenJoystickDriver_XboxUSBDevice_DevID.provisionprofile"
)


def run(args, *, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check)


def must_exist(path: str, label: str):
    if not os.path.isfile(path):
        raise SystemExit(f"ERROR: {label} not found: {path}")


def decode_profile(path: str) -> dict:
    p = subprocess.run(
        ["security", "cms", "-D", "-i", path],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=False,
        check=False,
    )
    raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        p = subprocess.run(
            ["openssl", "smime", "-inform", "der", "-verify", "-noverify", "-in", path],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=False,
            check=False,
        )
        raw = p.stdout if (p.returncode == 0 and p.stdout) else b""
    if not raw:
        raise SystemExit(
            "ERROR: Could not decode provisioning profile.\n"
            f"  profile: {path}\n"
            "Fix: reinstall/regenerate the profile and re-run `just signing-install-profiles`.\n"
            'Debug (safe): `just signing-audit "$HOME/Library/MobileDevice/Provisioning Profiles"/*.provisionprofile`'
        )
    if b"<?xml" in raw:
        raw = raw[raw.index(b"<?xml") :]
    try:
        return plistlib.loads(raw)
    except (ValueError, plistlib.InvalidFileException):
        raise SystemExit(
            "ERROR: Provisioning profile decoded, but plist parsing failed.\n"
            f"  profile: {path}\n"
            "Fix: regenerate the profile in the Developer portal and reinstall it."
        )


def embedded_cert_sha1s_from_profile(path: str) -> list[str]:
    sha1s = profile_certs.certificate_sha1_list(decode_profile(path))
    if not sha1s:
        raise SystemExit(
            f"ERROR: Could not extract DeveloperCertificates from profile: {path}"
        )
    return sha1s


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


dext_bundle_id = "com.openjoystickdriver.XboxUSBDevice"


def pick_identity_matching_profiles(
    prefix: str, profile_paths: list[str], chosen: str | None = None
) -> str:
    if chosen:
        return chosen
    embedded = {path: embedded_cert_sha1s_from_profile(path) for path in profile_paths}
    try:
        keychain = profile_certs.keychain_identities(prefix)
    except RuntimeError as error:
        raise SystemExit(f"ERROR: {error}")
    shared = profile_certs.shared_identity_sha1s(list(embedded.values()), keychain)
    if shared:
        chosen = shared[0]
        print(
            f"Selected {prefix} identity {chosen} ({keychain[chosen]}): the lowest SHA1 "
            f"of {len(shared)} Keychain identit{'y' if len(shared) == 1 else 'ies'} "
            f"embedded in all of: "
            + ", ".join(os.path.basename(path) for path in profile_paths)
            + (f" (qualifying: {', '.join(shared)})" if len(shared) > 1 else "")
        )
        return chosen
    profile_lines = "".join(
        f"  {os.path.basename(path)} embedded_cert_sha1s: {', '.join(sha1s)}\n"
        for path, sha1s in embedded.items()
    )
    keychain_sha1s = ", ".join(sorted(keychain)) if keychain else "NONE"
    first = os.path.basename(profile_paths[0])
    message = (
        f"ERROR: No {prefix} identity is embedded in all of these provisioning profiles.\n"
        f"{profile_lines}"
        f"  keychain_{prefix.replace(' ', '_').lower()}_sha1s: {keychain_sha1s}\n"
        "\n"
        "Required identity:\n"
        f"  A Keychain identity named '{prefix}: ...' whose SHA1 is embedded in every profile above.\n"
        "  The certificate must have its private key. Matching the Team ID alone is insufficient.\n"
        "  Apple Development identities do not satisfy Developer ID Application profiles.\n"
        "\n"
        "Check the profiles and Keychain:\n"
        "  1) List the certificates embedded in a profile:\n"
        f'       just signing-profile-info --full "$HOME/Library/MobileDevice/Provisioning Profiles/{first}"\n'
        "  2) List identities that have private keys:\n"
        "       security find-identity -v -p codesigning\n"
        "     If this reports 0 valid identities, unlock the login keychain and import the Apple\n"
        "     intermediates (WWDR, DeveloperIDG2CA) if certificates show as untrusted.\n"
        "  3) Otherwise, regenerate the profiles in the Apple Developer portal and select an installed certificate.\n"
        '  4) Reinstall profiles: just signing-install-profiles "$HOME/Documents/Profiles"\n'
    )
    raise SystemExit(message)


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
            if stripped.startswith(f"{key}="):
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


def userclient_ungranted(value: object) -> bool:
    if value is None:
        return True
    return (
        isinstance(value, list)
        and all(isinstance(item, str) for item in value)
        and dext_bundle_id not in value
    )


def includes_dext_grant(value: object) -> bool:
    return (
        isinstance(value, list)
        and all(isinstance(item, str) for item in value)
        and dext_bundle_id in value
    )


def require_host_profile(
    path: str, label: str, *, allow_ungranted_userclient: bool = False
) -> None:
    entitlements = decode_profile(path).get("Entitlements") or {}
    expected: dict[str, object] = {
        "com.apple.developer.system-extension.install": True,
        hid_entitlement: True,
    }
    for key, value in expected.items():
        if entitlements.get(key) != value:
            raise SystemExit(
                f"ERROR: {label} entitlement mismatch for {key}: "
                f"expected {value!r}, got {entitlements.get(key)!r}"
            )
    userclient = "com.apple.developer.driverkit.userclient-access"
    granted = entitlements.get(userclient)
    if not includes_dext_grant(granted) and not (
        allow_ungranted_userclient and userclient_ungranted(granted)
    ):
        raise SystemExit(
            f"ERROR: {label} entitlement mismatch for {userclient}: "
            f"expected a list of bundle IDs that includes {dext_bundle_id!r}, "
            f"got {granted!r}"
        )
    if entitlements.get("com.apple.developer.driverkit.allow-any-userclient-access"):
        raise SystemExit(
            f"ERROR: {label} grants allow-any DriverKit user-client access"
        )


def require_dext_profile(path: str, label: str) -> None:
    entitlements = decode_profile(path).get("Entitlements") or {}
    if entitlements.get("com.apple.developer.driverkit") is not True:
        raise SystemExit(f"ERROR: {label} is missing com.apple.developer.driverkit")
    actual_usb = entitlements.get("com.apple.developer.driverkit.transport.usb")
    if actual_usb != production_usb:
        raise SystemExit(
            f"ERROR: {label} com.apple.developer.driverkit.transport.usb is "
            f"{actual_usb!r}; expected Apple's exact seven-device grant for VID 1118"
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


def configure_development(dev_env: pathlib.Path, chosen_identity: str | None) -> None:
    must_exist(gui_dev_profile, "GUI development provisioning profile")
    must_exist(dext_profile, "DriverKit development provisioning profile")
    require_host_profile(
        gui_dev_profile, "GUI development profile", allow_ungranted_userclient=True
    )
    require_dext_profile(dext_profile, "DriverKit development profile")
    dev_team = team_id_from_profile(gui_dev_profile)
    if team_id_from_profile(dext_profile) != dev_team:
        raise SystemExit(
            "ERROR: development host and DEXT profiles use different teams"
        )
    apple_dev_identity = pick_identity_matching_profiles(
        "Apple Development", [gui_dev_profile, dext_profile], chosen_identity
    )
    update_env_file(
        dev_env,
        "# Development signing (managed by just signing-configure)",
        {
            "CODESIGN_IDENTITY": apple_dev_identity,
            "DEVELOPMENT_TEAM": dev_team,
            "DEXT_PROVISIONING_PROFILE": dext_profile,
            "GUI_PROVISIONING_PROFILE": gui_dev_profile,
        },
    )
    print(f"Updated {dev_env}")


def configure_release(
    rel_env: pathlib.Path, chosen_identity: str | None, *, optional: bool
) -> None:
    if optional and (
        not os.path.isfile(gui_devid_profile) or not os.path.isfile(dext_devid_profile)
    ):
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
        raise SystemExit(
            "ERROR: Developer ID host and DEXT profiles use different teams"
        )
    devid_identity = pick_identity_matching_profiles(
        "Developer ID Application",
        [gui_devid_profile, dext_devid_profile],
        chosen_identity,
    )
    update_env_file(
        rel_env,
        "# Release signing (managed by just signing-configure)",
        {
            "CODESIGN_IDENTITY": devid_identity,
            "DEVELOPMENT_TEAM": rel_team,
            "DEXT_PROVISIONING_PROFILE": dext_devid_profile,
            "GUI_PROVISIONING_PROFILE": gui_devid_profile,
        },
    )
    print(f"Updated {rel_env}")


def main(argv: list[str]) -> None:
    parser = argparse.ArgumentParser(prog="just signing-configure")
    parser.add_argument("--project-dir", type=pathlib.Path, required=True)
    parser.add_argument(
        "--mode", choices=("all", "development", "release"), default="all"
    )
    parser.add_argument("--development-identity")
    parser.add_argument("--release-identity")
    arguments = parser.parse_args(argv)
    if arguments.mode in {"all", "development"}:
        configure_development(
            arguments.project_dir / ".env.dev", arguments.development_identity
        )
    if arguments.mode in {"all", "release"}:
        configure_release(
            arguments.project_dir / ".env.release",
            arguments.release_identity,
            optional=arguments.mode == "all",
        )


if __name__ == "__main__":
    main(sys.argv[1:])
