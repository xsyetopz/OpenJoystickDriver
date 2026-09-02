from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from jsonschema import Draft202012Validator, FormatChecker
    from jsonschema.exceptions import SchemaError, ValidationError
    from referencing import Registry, Resource
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r scripts/quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = Path(__file__).resolve().parents[2]
SCHEMAS = ROOT / "Resources" / "Schemas"
GENERATED_RECORDS = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
CONTROLLER_OVERRIDES = ROOT / "Resources" / "ControllerOverrides"
SCHEMA_PATHS = (
    SCHEMAS / "controller.schema.json",
    SCHEMAS / "controller-override.schema.json",
    SCHEMAS / "report.schema.json",
)


def load_json(path: Path) -> object:
    with path.open(encoding="utf-8") as source:
        return json.load(source)


def validate_schema_documents() -> dict[str, dict[str, object]]:
    documents: dict[str, dict[str, object]] = {}
    for path in SCHEMA_PATHS:
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


def validate_documents(
    schema: dict[str, object],
    registry: Registry,
    paths: list[Path],
) -> None:
    validator = Draft202012Validator(schema, registry=registry)
    for path in paths:
        try:
            validator.validate(load_json(path))
        except ValidationError as error:
            location = ".".join(str(component) for component in error.absolute_path)
            suffix = f" at {location}" if location else ""
            raise ValidationError(
                f"{path.relative_to(ROOT)}{suffix}: {error.message}"
            ) from error


def swift_binary_path() -> Path:
    subprocess.run(
        ["swift", "build", "--product", "OpenJoystickDriver"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    bin_path = subprocess.run(
        ["swift", "build", "--show-bin-path"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return Path(bin_path.stdout.strip()) / "OpenJoystickDriver"


def validate_live_support_report(schema: dict[str, object], registry: Registry) -> None:
    with tempfile.TemporaryDirectory(prefix="ojd-schema-") as directory:
        report_path = Path(directory) / "support-report.json"
        subprocess.run(
            [
                str(swift_binary_path()),
                "--headless",
                "diagnose",
                "report",
                "--output",
                str(report_path),
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).validate(load_json(report_path))


def main() -> int:
    try:
        documents = validate_schema_documents()
        registry = schema_registry(documents)
        controller_records = sorted(GENERATED_RECORDS.glob("*/*.json"))
        overrides = sorted(CONTROLLER_OVERRIDES.glob("*/*.json"))
        validate_documents(documents["controller.schema.json"], registry, controller_records)
        validate_documents(documents["controller-override.schema.json"], registry, overrides)
        validate_live_support_report(documents["report.schema.json"], registry)
    except (OSError, json.JSONDecodeError, SchemaError, ValidationError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        print(f"error: {detail}", file=sys.stderr)
        return 1
    print(
        "Validated 3 schema documents, "
        f"{len(controller_records)} controller records, {len(overrides)} overrides, "
        "and one live support report."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
