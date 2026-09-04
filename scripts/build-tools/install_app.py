"""Replace the installed app only after retiring stale instances, then verify RPC readiness."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import NoReturn

APP_PROCESS_NAME = "OpenJoystickDriver"
DRIVERKIT_PROCESS_NAME = "XboxUSBDevice"
DEFAULT_DESTINATION = Path("/Applications/OpenJoystickDriver.app")
APPLICATION_JOB_PATTERN = re.compile(
    r"application\.com\.openjoystickdriver\.[A-Za-z0-9.-]+"
)


class InstallFailure(RuntimeError):
    pass


def die(message: str) -> NoReturn:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def run(
    command: list[str],
    *,
    capture: bool = False,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        command,
        check=False,
        text=True,
        capture_output=capture,
    )
    if check and result.returncode:
        detail = (result.stderr or result.stdout or "").strip()
        suffix = f": {detail}" if detail else ""
        raise InstallFailure(
            f"command failed ({result.returncode}): {' '.join(command)}{suffix}"
        )
    return result


def application_job_labels() -> list[str]:
    domain = f"gui/{os.getuid()}"
    result = run(["/bin/launchctl", "print", domain], capture=True, check=False)
    return sorted(set(APPLICATION_JOB_PATTERN.findall(result.stdout)))


def application_job_is_running(label: str) -> bool:
    result = run(
        ["/bin/launchctl", "print", f"gui/{os.getuid()}/{label}"],
        capture=True,
        check=False,
    )
    if result.returncode:
        return False
    pid_match = re.search(r"^\s*pid = ([0-9]+)\s*$", result.stdout, re.MULTILINE)
    if pid_match:
        process_identifier = int(pid_match.group(1))
        # launchd can keep state=running on a zombie until bootout reaps it.
        return process_identifier > 0 and process_is_alive(process_identifier)
    return bool(re.search(r"^\s*state = running\s*$", result.stdout, re.MULTILINE))


def process_is_alive(process_identifier: int) -> bool:
    """True when the PID is a live process (zombies / exiting leftovers are not)."""
    result = run(
        ["/bin/ps", "-p", str(process_identifier), "-o", "state=,rss="],
        capture=True,
        check=False,
    )
    parts = (result.stdout or "").split()
    if result.returncode or len(parts) < 2:
        return False
    state = parts[0].upper()
    # macOS reports exiting leftovers as Z, E, or ?E with rss 0.
    if "Z" in state or "E" in state:
        return False
    try:
        return int(parts[1]) > 0
    except ValueError:
        return False


def application_process_identifiers() -> list[int]:
    result = run(
        ["/usr/bin/pgrep", "-x", APP_PROCESS_NAME],
        capture=True,
        check=False,
    )
    if result.returncode:
        return []
    return [
        int(value)
        for value in result.stdout.split()
        if value.isdigit() and process_is_alive(int(value))
    ]


def signal_processes(
    process_identifiers: list[int], signal_number: signal.Signals
) -> None:
    for process_identifier in process_identifiers:
        try:
            os.kill(process_identifier, signal_number)
        except ProcessLookupError:
            continue


def wait_until_retired(labels: list[str], timeout_seconds: float) -> bool:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if not application_process_identifiers() and not any(
            application_job_is_running(label) for label in labels
        ):
            return True
        time.sleep(0.1)
    return False


def retire_application_instances() -> None:
    labels = application_job_labels()
    domain = f"gui/{os.getuid()}"
    if labels:
        print(f"Retiring {len(labels)} OpenJoystickDriver LaunchServices job(s)")
    for label in labels:
        run(
            ["/bin/launchctl", "kill", "SIGTERM", f"{domain}/{label}"],
            check=False,
        )
    signal_processes(application_process_identifiers(), signal.SIGTERM)

    if wait_until_retired(labels, 5):
        if application_process_identifiers():
            raise InstallFailure(
                "stale OpenJoystickDriver processes remain after retirement"
            )
        return

    print("OpenJoystickDriver did not stop after SIGTERM; forcing termination")
    for label in labels:
        run(
            ["/bin/launchctl", "kill", "SIGKILL", f"{domain}/{label}"],
            check=False,
        )
    signal_processes(application_process_identifiers(), signal.SIGKILL)
    if wait_until_retired(labels, 2):
        return

    # Last resort only: bootout clears a zombie PID stuck on an LS job.
    # Do not bootout on the happy path — that breaks the next LaunchServices
    # open of the replacement bundle (error -600).
    print("OpenJoystickDriver LaunchServices job survived SIGKILL; booting out")
    for label in labels:
        run(["/bin/launchctl", "bootout", f"{domain}/{label}"], check=False)
    if wait_until_retired(labels, 2):
        return
    if not application_process_identifiers():
        print(
            "LaunchServices still lists a retired OpenJoystickDriver job "
            "with no live process; continuing install"
        )
        return
    raise InstallFailure(
        "macOS left an unkillable OpenJoystickDriver application job. "
        "Reboot once, then rerun the install."
    )


def retire_driverkit_instances() -> None:
    process_identifiers = driverkit_process_identifiers()
    if not process_identifiers:
        return
    print(f"Retiring {len(process_identifiers)} stale XboxUSBDevice process(es)")
    for process_identifier in process_identifiers:
        try:
            os.kill(process_identifier, signal.SIGKILL)
        except ProcessLookupError:
            continue
        except PermissionError:
            run(
                ["/usr/bin/sudo", "/bin/kill", "-9", str(process_identifier)],
                check=False,
            )
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        if not driverkit_process_identifiers():
            return
        time.sleep(0.1)
    raise InstallFailure(
        "A stale XboxUSBDevice process survived termination. Reboot once, then rerun the install."
    )


def driverkit_process_identifiers() -> list[int]:
    result = run(
        ["/usr/bin/pgrep", "-x", DRIVERKIT_PROCESS_NAME],
        capture=True,
        check=False,
    )
    if result.returncode:
        return []
    return [int(value) for value in result.stdout.split() if value.isdigit()]


def verify_signature(application: Path) -> None:
    executable = application / "Contents/MacOS/OpenJoystickDriver"
    if not executable.is_file():
        raise InstallFailure(f"application executable is missing: {executable}")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(application)])


def launch_application(application: Path) -> None:
    """Start the installed GUI by spawning the signed executable.

    Install replaces a just-stopped instance. ``open`` talks to LaunchServices /
    RunningBoard and races that teardown (often error -600). Spawning the
    verified Mach-O registers a fresh application job and is what install
    readiness actually needs.
    """
    executable = application / "Contents/MacOS/OpenJoystickDriver"
    if not executable.is_file():
        raise InstallFailure(f"application executable is missing: {executable}")
    subprocess.Popen(  # noqa: S603 — verified signed install path only
        [str(executable)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def launch_and_wait(application: Path, timeout_seconds: float) -> None:
    launch_application(application)
    executable = application / "Contents/MacOS/OpenJoystickDriver"
    deadline = time.monotonic() + timeout_seconds
    last_error = ""
    while time.monotonic() < deadline:
        if not application_process_identifiers():
            # First spawn can exit immediately on a broken bundle; surface that.
            time.sleep(0.2)
            if not application_process_identifiers():
                launch_application(application)
        result = run(
            [str(executable), "--headless", "app", "ready"],
            capture=True,
            check=False,
        )
        if result.returncode == 0:
            print(
                "Launched OpenJoystickDriver and verified authenticated RPC readiness"
            )
            return
        last_error = (result.stderr or result.stdout or "").strip()
        time.sleep(0.2)
    detail = f": {last_error}" if last_error else ""
    raise InstallFailure(
        f"installed application service did not become ready within {timeout_seconds:g}s{detail}"
    )


def remove_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def install(
    source: Path,
    destination: Path,
    timeout_seconds: float,
    retire_driverkit: bool,
) -> None:
    source = source.resolve()
    if not source.is_dir():
        raise InstallFailure(f"application bundle not found: {source}")
    verify_signature(source)

    destination_parent = destination.parent
    staged = destination_parent / f".{destination.name}.staged.{os.getpid()}"
    backup = destination_parent / f".{destination.name}.backup.{os.getpid()}"
    remove_path(staged)
    remove_path(backup)

    print(f"Staging verified application from {source}")
    run(["/usr/bin/ditto", str(source), str(staged)])
    verify_signature(staged)

    previous_installation = destination.exists()
    backup_created = False
    replacement_installed = False
    installation_succeeded = False
    try:
        if retire_driverkit:
            retire_driverkit_instances()
        retire_application_instances()
        if previous_installation:
            destination.rename(backup)
            backup_created = True
        staged.rename(destination)
        replacement_installed = True
        run(
            ["/usr/bin/xattr", "-dr", "com.apple.quarantine", str(destination)],
            check=False,
        )
        verify_signature(destination)
        launch_and_wait(destination, timeout_seconds)
        installation_succeeded = True
    except (InstallFailure, OSError) as install_error:
        rollback_error: InstallFailure | OSError | None = None
        if replacement_installed and not backup_created:
            try:
                retire_application_instances()
            except (InstallFailure, OSError) as error:
                rollback_error = error
            if rollback_error:
                raise InstallFailure(
                    f"installation failed ({install_error}); the verified candidate remains at "
                    f"{destination}, but its process could not be retired ({rollback_error})"
                ) from rollback_error
            raise InstallFailure(
                f"installation failed ({install_error}); the verified candidate remains at "
                f"{destination} for inspection or manual relaunch"
            ) from install_error
        if backup_created:
            try:
                retire_application_instances()
                if replacement_installed:
                    remove_path(destination)
                if backup.exists():
                    backup.rename(destination)
                    print(
                        "Restored the previous OpenJoystickDriver installation",
                        file=sys.stderr,
                    )
            except (InstallFailure, OSError) as error:
                rollback_error = error
        if rollback_error:
            raise InstallFailure(
                f"installation failed ({install_error}); rollback also failed ({rollback_error}); "
                f"preserved backup: {backup}"
            ) from rollback_error
        raise
    finally:
        remove_path(staged)
        if installation_succeeded:
            remove_path(backup)

    print(f"Installed OpenJoystickDriver at {destination}")


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--destination", type=Path, default=DEFAULT_DESTINATION)
    parser.add_argument("--timeout-seconds", type=float, default=10)
    parser.add_argument("--retire-driverkit", action="store_true")
    arguments = parser.parse_args(argv)
    if arguments.timeout_seconds <= 0:
        parser.error("--timeout-seconds must be positive")
    return arguments


def main(argv: list[str]) -> int:
    arguments = parse_arguments(argv)
    try:
        install(
            arguments.source,
            arguments.destination,
            arguments.timeout_seconds,
            arguments.retire_driverkit,
        )
    except (InstallFailure, OSError) as error:
        die(str(error))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
