from __future__ import annotations

import json
import os
import plistlib
import subprocess
import sys
import tempfile
import xml.parsers.expat
from pathlib import Path

from ..Catalog.schema_header import (
    KINDS,
    SCHEMA_SUFFIX,
    schema_id,
)
from . import repository_tool

try:
    from jsonschema import Draft202012Validator, FormatChecker
    from jsonschema.exceptions import SchemaError, ValidationError
    from referencing import Registry, Resource
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r Scripts/Quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "Resources" / "Schemas"
GENERATED_RECORDS = (
    ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
)
AUTHORED_CONTROLLERS = ROOT / "Resources" / "Controllers"
AUTHORED_PATCHES = ROOT / "Resources" / "ControllerPatches"
ERROR_CODES = ROOT / "Resources" / "ErrorCodes.plist"
CROSSWALK = ROOT / "Resources" / "Vocabulary" / "crosswalk.plist"
PROTOCOL_DESCRIPTIONS = ROOT / "Resources" / "Protocols"
VIRTUAL_DEVICES = ROOT / "Resources" / "VirtualDevices"
SAMPLE_PACKAGE = ROOT / "docs" / "sdk" / "sample"
ACCESS_GRANT_FIXTURES = (
    ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "access_grants.json",
)
SETTINGS_FIXTURES = (
    ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "settings.json",
)
SERVICE_LISTENER_FAILURE_FIXTURES = (
    ROOT / "Tests" / "RepositoryScripts" / "fixtures" / "service_listener_failure.json",
)
# The schema of each kind of file in the sample mod package, by its folder. A `Controllers`
# file is a `ControllerPatch` or a `Controller`, which its `kind` tells apart.
SAMPLE_FOLDER_SCHEMAS = {
    "Controllers": "controller",
    "VirtualDevices": "virtual-device",
    "Profiles": "profile",
}


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def load_plist(path: Path) -> object:
    with path.open("rb") as source:
        return plistlib.load(source)


def validate_schema_documents() -> dict[str, dict[str, object]]:
    documents: dict[str, dict[str, object]] = {}
    paths = sorted(SCHEMAS.glob(f"*{SCHEMA_SUFFIX}"))
    if not paths:
        raise SchemaError(f"no schemas in {SCHEMAS.relative_to(ROOT)}")
    for path in paths:
        document = load_json(path)
        if not isinstance(document, dict):
            raise SchemaError(f"{path.relative_to(ROOT)} must contain a JSON object")
        Draft202012Validator.check_schema(document)
        documents[path.name] = document
    return documents


def schema_registry(documents: dict[str, dict[str, object]]) -> Registry:
    resources = []
    for name, document in documents.items():
        identifier = document.get("$id")
        if not isinstance(identifier, str) or not identifier:
            raise SchemaError(f"Resources/Schemas/{name} must declare a nonempty $id")
        resources.append((identifier, Resource.from_contents(document)))
    return Registry().with_resources(resources)


def api_version_group() -> str:
    """The group of the `apiVersion`, the part before the slash."""
    return repository_tool.api_version().partition("/")[0]


def api_version_consts(value: object, where: str = "") -> list[tuple[str, object]]:
    """Every `const` in `value` that names an OJD `apiVersion`, with where it is."""
    found: list[tuple[str, object]] = []
    if isinstance(value, dict):
        const = value.get("const")
        if isinstance(const, str) and const.startswith(f"{api_version_group()}/"):
            found.append((where, const))
        for key, child in value.items():
            found.extend(api_version_consts(child, f"{where}/{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            found.extend(api_version_consts(child, f"{where}/{index}"))
    return found


def validate_schema_identity(documents: dict[str, dict[str, object]]) -> None:
    """Check each `$id`, `apiVersion` const, and `kind` const against the one source."""
    api_version = repository_tool.api_version()
    for name, document in documents.items():
        stem = name[: -len(SCHEMA_SUFFIX)]
        if document.get("$id") != schema_id(stem):
            raise SchemaError(
                f"Resources/Schemas/{name}: $id must be {schema_id(stem)}, "
                f"found {document.get('$id')}"
            )
        for where, const in api_version_consts(document):
            if const != api_version:
                raise SchemaError(
                    f"Resources/Schemas/{name}{where}: apiVersion const must be "
                    f"{api_version}, found {const}"
                )
        kind = KINDS.get(stem)
        if kind is None:
            continue
        properties = document.get("properties")
        if not isinstance(properties, dict):
            properties = {}
            # A schema that declares the header in each oneOf branch.
            for branch in document.get("oneOf", []):  # type: ignore[attr-defined]
                properties = {**properties, **branch.get("properties", {})}
        header = {
            member: properties.get(member, {}).get("const")
            for member in ("apiVersion", "kind")
        }
        if header != {"apiVersion": api_version, "kind": kind}:
            raise SchemaError(
                f"Resources/Schemas/{name}: must require apiVersion {api_version} "
                f"and kind {kind}, found {header}"
            )


def sample_documents() -> list[tuple[str, Path]]:
    """The files of the sample mod package with the schema each is read as."""
    found: list[tuple[str, Path]] = [("mod-package", SAMPLE_PACKAGE / "mod.json")]
    for folder, stem in SAMPLE_FOLDER_SCHEMAS.items():
        for path in sorted((SAMPLE_PACKAGE / folder).glob("*.json")):
            kind = load_json(path)
            patch = (
                isinstance(kind, dict) and kind.get("kind") == KINDS["controller-patch"]
            )
            found.append(
                (
                    "controller-patch" if folder == "Controllers" and patch else stem,
                    path,
                )
            )
    known = {path for _, path in found}
    unknown = sorted(set(SAMPLE_PACKAGE.rglob("*.json")) - known)
    if unknown:
        raise SchemaError(
            f"{unknown[0].relative_to(ROOT)}: no schema is named for this sample file"
        )
    return found


def validate_documents(
    schema: dict[str, object],
    registry: Registry,
    paths: list[Path],
) -> None:
    """Validates documents against a schema; the rules a schema cannot state are Swift's."""
    validator = Draft202012Validator(schema, registry=registry)
    for path in paths:
        document = load_plist(path) if path.suffix == ".plist" else load_json(path)
        try:
            validator.validate(document)
        except ValidationError as error:
            location = ".".join(str(component) for component in error.absolute_path)
            suffix = f" at {location}" if location else ""
            raise ValidationError(
                f"{path.relative_to(ROOT)}{suffix}: {error.message}"
            ) from error


def validate_swift_rules(samples: list[tuple[str, Path]]) -> None:
    """Every rule a schema cannot state is Swift's: `OJDRepositoryTool` checks the authored
    controller records, the protocol descriptions and the sample profiles and virtual devices."""
    repository_tool.check(["validate", "controllers", str(AUTHORED_CONTROLLERS)])
    repository_tool.check(["validate", "descriptions", str(PROTOCOL_DESCRIPTIONS)])
    for stem, check in (
        ("profile", "profiles"),
        ("virtual-device", "virtual-devices"),
    ):
        paths = [str(path) for kind, path in samples if kind == stem]
        if paths:
            repository_tool.check(["validate", check, *paths])


def validate_live_support_report(schema: dict[str, object], registry: Registry) -> None:
    with tempfile.TemporaryDirectory(prefix="ojd-schema-") as directory:
        report_path = Path(directory) / "support-report.json"
        # argv[0] "ojd" selects the command line in the app executable. `diagnose` exits 1 when
        # a check fails, such as a missing extension on CI, and still writes the report.
        command = ["ojd", "diagnose", "--output", str(report_path)]
        result = subprocess.run(
            command,
            executable=repository_tool.build("OpenJoystickDriver"),
            cwd=ROOT,
            env={**os.environ, "OJD_RUN_REPOSITORY_CLI": "1"},
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode not in {0, 1} or not report_path.is_file():
            raise subprocess.CalledProcessError(
                result.returncode, command, result.stdout, result.stderr
            )
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).validate(load_json(report_path))


def main() -> int:
    try:
        documents = validate_schema_documents()
        validate_schema_identity(documents)
        registry = schema_registry(documents)
        controller_records = sorted(GENERATED_RECORDS.glob("*/*.plist"))
        authored = sorted(AUTHORED_CONTROLLERS.glob("*/*.plist"))
        patches = sorted(
            [*AUTHORED_PATCHES.glob("*.plist"), *AUTHORED_PATCHES.glob("*/*.plist")]
        )
        protocols = sorted(PROTOCOL_DESCRIPTIONS.glob("*.plist"))
        virtual_devices = sorted(VIRTUAL_DEVICES.glob("*.plist"))
        validate_documents(
            documents["controller.schema.json"], registry, controller_records
        )
        validate_documents(documents["controller.schema.json"], registry, authored)
        validate_documents(documents["controller-patch.schema.json"], registry, patches)
        validate_documents(
            documents["error-codes.schema.json"], registry, [ERROR_CODES]
        )
        validate_documents(documents["crosswalk.schema.json"], registry, [CROSSWALK])
        validate_documents(
            documents["protocol-description.schema.json"], registry, protocols
        )
        validate_documents(
            documents["virtual-device.schema.json"], registry, virtual_devices
        )
        samples = sample_documents()
        for stem, path in samples:
            validate_documents(documents[f"{stem}{SCHEMA_SUFFIX}"], registry, [path])
        validate_documents(
            documents["access-grants.schema.json"],
            registry,
            list(ACCESS_GRANT_FIXTURES),
        )
        validate_documents(
            documents["settings.schema.json"], registry, list(SETTINGS_FIXTURES)
        )
        validate_documents(
            documents["service-listener-failure.schema.json"],
            registry,
            list(SERVICE_LISTENER_FAILURE_FIXTURES),
        )
        validate_swift_rules(samples)
        validate_live_support_report(documents["report.schema.json"], registry)
    except (
        OSError,
        json.JSONDecodeError,
        plistlib.InvalidFileException,
        xml.parsers.expat.ExpatError,
        SchemaError,
        ValidationError,
        repository_tool.ToolError,
    ) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        print(f"error: {detail}", file=sys.stderr)
        return 1
    print(
        f"Validated {len(documents)} schema documents, "
        f"{len(controller_records)} controller records, {len(authored)} authored controllers, "
        f"{len(patches)} built-in patches, "
        f"{len(protocols)} protocol descriptions, "
        f"{len(virtual_devices)} virtual devices, {len(samples)} sample mod files, "
        f"{len(ACCESS_GRANT_FIXTURES)} access grant fixtures, "
        f"{len(SETTINGS_FIXTURES)} settings fixtures, "
        f"{len(SERVICE_LISTENER_FAILURE_FIXTURES)} service listener failure fixtures, "
        "the error code catalog, the control crosswalk, "
        "and one live support report."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
