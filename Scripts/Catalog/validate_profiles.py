"""Validate canonical OpenJoystickDriver controller records."""

from __future__ import annotations

import json
import pathlib
import sys
from typing import Any

try:
    from jsonschema import Draft202012Validator
    from jsonschema.exceptions import ValidationError as JSONSchemaValidationError
except ImportError:
    print(
        "error: install schema validation dependencies with "
        "'python3 -m pip install -r Scripts/Quality/requirements.txt'",
        file=sys.stderr,
    )
    raise SystemExit(2)

ROOT = pathlib.Path(__file__).resolve().parents[2]
RECORD_DIR = ROOT / "Sources" / "OpenJoystickDriverKit" / "Resources" / "Controllers"
SCHEMA_PATH = ROOT / "Resources" / "Schemas" / "v1beta1" / "controller.schema.json"


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def expected_relative_path(vendor_id: int, product_id: int) -> pathlib.Path:
    return pathlib.Path(f"{vendor_id:04x}") / f"{vendor_id:04x}-{product_id:04x}.json"


def load_object(path: pathlib.Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text())
    except json.JSONDecodeError as error:
        raise ValidationError(f"{path}: invalid JSON: {error}") from error
    require(isinstance(value, dict), f"{path}: root must be an object")
    return value


def validator() -> Any:
    schema = load_object(SCHEMA_PATH)
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema)


def validate_record(
    path: pathlib.Path,
    *,
    enforce_path: bool = True,
    schema_validator: Any | None = None,
) -> tuple[int, int, str]:
    record = load_object(path)
    active_validator = schema_validator or validator()
    try:
        active_validator.validate(record)
    except JSONSchemaValidationError as error:
        location = ".".join(str(component) for component in error.absolute_path)
        suffix = f" at {location}" if location else ""
        raise ValidationError(f"{path}{suffix}: {error.message}") from error

    # JSON Schema cannot express disjoint arrays; the runtime decoder rejects overlap too.
    capabilities = record.get("capabilities", {})
    overlap = set(capabilities.get("absent", [])) & set(capabilities.get("present", []))
    require(
        not overlap, f"{path}: capabilities both absent and present: {sorted(overlap)}"
    )

    vendor_id = record["vendorID"]
    product_id = record["productID"]
    if enforce_path:
        relative = path.relative_to(RECORD_DIR)
        expected = expected_relative_path(vendor_id, product_id)
        require(relative == expected, f"{path}: path must be {expected}")

    return vendor_id, product_id, record["protocol"]["family"]


def validate_catalog(record_dir: pathlib.Path = RECORD_DIR) -> list[pathlib.Path]:
    records = sorted(record_dir.glob("*/*.json"))
    require(bool(records), f"no controller records found in {record_dir}")
    seen: dict[tuple[int, int], pathlib.Path] = {}
    schema_validator = validator()
    for path in records:
        vendor_id, product_id, _ = validate_record(
            path,
            enforce_path=record_dir == RECORD_DIR,
            schema_validator=schema_validator,
        )
        key = (vendor_id, product_id)
        require(key not in seen, f"{path}: duplicate identity also in {seen.get(key)}")
        seen[key] = path
    return records


def main() -> int:
    try:
        records = validate_catalog()
    except (OSError, ValidationError) as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1

    for path in records:
        print(f"[OK] {path.relative_to(ROOT)}")
    print(f"Validated {len(records)} canonical controller record(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
