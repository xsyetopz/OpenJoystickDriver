"""Naming rule for every schema in Resources/Schemas.

Enum values, string constants and string defaults of an enum are UpperCamelCase. Property names, `$defs`
names and `required` entries are lowerCamelCase with acronyms upper case (`reportID`). Three lists describe
what the rule does not cover:

- EXCEPTIONS: names fixed by an external format.
- FIELD_NAME_ENUMS: values that name a field, so they follow the field rule and must be a field.
- `schema_naming_pending.json`: values that break the rule, grouped by schema. The list holds no
  entry; an entry that no longer matches fails.
"""

from __future__ import annotations

import json
import plistlib
import re
import unittest
from collections.abc import Iterator
from pathlib import Path
from typing import Any, NamedTuple, cast

from Scripts.Quality import validate_schemas

SCHEMAS = validate_schemas.ROOT / "Resources" / "Schemas"
PROTOCOLS = validate_schemas.ROOT / "Resources" / "Protocols"
PENDING_FILE = Path(__file__).resolve().parent / "schema_naming_pending.json"

VALUE = re.compile(r"^[A-Z][A-Za-z0-9]*$")
FIELD = re.compile(r"^[a-z][A-Za-z0-9]*$")
FIELD_PATH = re.compile(r"^[a-z][A-Za-z0-9]*(\.[a-z][A-Za-z0-9]*)*$")

# Keywords whose value maps a name to a schema.
SCHEMA_MAPS = ("properties", "$defs", "patternProperties", "dependentSchemas")
# Keywords whose value is data, not a schema to descend into.
DATA_KEYWORDS = (
    "enum",
    "const",
    "default",
    "examples",
    "required",
    "dependentRequired",
)


class Hit(NamedTuple):
    """One checked string. `kind` is `value` or `name`; `pointer` locates the keyword that holds it.

    A property name is reported at the pointer of the `properties` map that declares it.
    """

    kind: str
    pointer: str
    value: str


def escape(name: str) -> str:
    return name.replace("~", "~0").replace("/", "~1")


def checked_strings(node: Any, pointer: str = "") -> Iterator[Hit]:
    """Yield every string the rule applies to, in the schema `node` and below."""
    if isinstance(node, list):
        for index, item in enumerate(cast("list[Any]", node)):
            yield from checked_strings(item, f"{pointer}/{index}")
        return
    if not isinstance(node, dict):
        return
    keywords = cast("dict[str, Any]", node)
    enum = keywords.get("enum")
    if isinstance(enum, list):
        for value in cast("list[Any]", enum):
            if isinstance(value, str):
                yield Hit("value", f"{pointer}/enum", value)
    default = keywords.get("default")
    if isinstance(default, str) and ("enum" in keywords or "$ref" in keywords):
        yield Hit("value", f"{pointer}/default", default)
    constant = keywords.get("const")
    if isinstance(constant, str):
        yield Hit("value", f"{pointer}/const", constant)
    required = keywords.get("required")
    if isinstance(required, list):
        for name in cast("list[Any]", required):
            if isinstance(name, str):
                yield Hit("name", f"{pointer}/required", name)
    dependent = keywords.get("dependentRequired")
    if isinstance(dependent, dict):
        for name, names in cast("dict[str, Any]", dependent).items():
            yield Hit("name", f"{pointer}/dependentRequired", name)
            for listed in cast("list[Any]", names):
                if isinstance(listed, str):
                    yield Hit(
                        "name", f"{pointer}/dependentRequired/{escape(name)}", listed
                    )
    for keyword, child in keywords.items():
        if keyword in SCHEMA_MAPS and isinstance(child, dict):
            for name, schema in cast("dict[str, Any]", child).items():
                if keyword in ("properties", "$defs"):
                    yield Hit("name", f"{pointer}/{keyword}", name)
                yield from checked_strings(
                    schema, f"{pointer}/{keyword}/{escape(name)}"
                )
        elif keyword not in DATA_KEYWORDS:
            yield from checked_strings(child, f"{pointer}/{keyword}")


# Acronyms that stay upper case inside a value. A value spelling one as a word (`Sdl`, `Hid`)
# breaks the rule; a longer word that merely starts with the letters (`Hidden`) does not.
ACRONYMS = (
    "API",
    "CLI",
    "GATT",
    "GIP",
    "HD",
    "HDR",
    "HID",
    "ID",
    "JSON",
    "LE",
    "NVIDIA",
    "OJD",
    "PID",
    "PS3",
    "SDL",
    "SPI",
    "URL",
    "USB",
    "UUID",
    "VID",
    "W3C",
    "XID",
    "XUSB",
)
ACRONYM_AS_WORD = re.compile(
    "|".join(f"{acronym[0]}{acronym[1:].lower()}(?![a-z])" for acronym in ACRONYMS)
)


# A field name starts with a lower case word, so only an acronym after the first word is checked.
# A plural takes a lower case `s` after the acronym (`reportIDs`).
ACRONYM_IN_NAME = re.compile(
    "(?<=[a-z0-9])(?:"
    + "|".join(f"{acronym[0]}{acronym[1:].lower()}" for acronym in ACRONYMS)
    + ")s?(?![a-z])"
)


def breaks_rule(hit: Hit) -> bool:
    if hit.kind == "name":
        return not FIELD.match(hit.value) or bool(ACRONYM_IN_NAME.search(hit.value))
    return not VALUE.match(hit.value) or bool(ACRONYM_AS_WORD.search(hit.value))


def violations(document: Any) -> list[Hit]:
    return [hit for hit in checked_strings(document) if breaks_rule(hit)]


def resolve(document: Any, pointer: str) -> Any:
    """The JSON value at `pointer`; raises KeyError or IndexError when it does not exist."""
    node = document
    for token in pointer.split("/")[1:]:
        token = token.replace("~1", "/").replace("~0", "~")
        node = node[int(token)] if isinstance(node, list) else node[token]
    return node


def schemas() -> dict[str, Any]:
    result: dict[str, Any] = {}
    for path in sorted(SCHEMAS.glob("*.schema.json")):
        with path.open(encoding="utf-8") as source:
            result[path.name.removesuffix(".schema.json")] = json.load(source)
    return result


API_VERSION = "the apiVersion value `group/version` (Kubernetes grammar)"
CLOUD_EVENTS = "CloudEvents 1.0 envelope attribute"
HID_PAGE = "HID Usage Table page name used as a property name"
REPORT_DATA_SCHEMA = (
    "https://xsyetopz.github.io/OpenJoystickDriver/schemas/v1alpha3/"
    "report.schema.json#/$defs/supportDiagnosticData"
)
MODE_ID = "a mode id is a name with an RFC 1123 label pattern, not an enum value"

# (schema, pointer) -> (values excused at that pointer, reason).
EXCEPTIONS: dict[tuple[str, str], tuple[tuple[str, ...], str]] = {
    **{
        (schema, pointer): (("openjoystickdriver/v1alpha3",), API_VERSION)
        for schema, pointer in (
            ("access-grants", "/properties/apiVersion/const"),
            ("cli-output", "/$defs/sharedAPIVersion/const"),
            ("controller", "/properties/apiVersion/const"),
            ("controller-patch", "/properties/apiVersion/const"),
            ("crosswalk", "/properties/apiVersion/const"),
            ("error-codes", "/properties/apiVersion/const"),
            ("mod-package", "/properties/apiVersion/const"),
            ("profile", "/properties/apiVersion/const"),
            ("protocol-description", "/properties/apiVersion/const"),
            ("report", "/$defs/supportDiagnosticData/properties/apiVersion/const"),
            ("service-listener-failure", "/properties/apiVersion/const"),
            ("settings", "/properties/apiVersion/const"),
            ("virtual-device", "/properties/apiVersion/const"),
        )
    },
    ("report", "/properties/specversion/const"): (("1.0",), CLOUD_EVENTS),
    ("report", "/properties/source/const"): (
        ("urn:openjoystickdriver:support",),
        CLOUD_EVENTS,
    ),
    ("report", "/properties/type/const"): (
        ("com.openjoystickdriver.support.diagnostic",),
        CLOUD_EVENTS,
    ),
    ("report", "/properties/datacontenttype/const"): (
        ("application/json",),
        CLOUD_EVENTS,
    ),
    ("report", "/properties/dataschema/const"): (
        (REPORT_DATA_SCHEMA,),
        CLOUD_EVENTS,
    ),
    ("crosswalk", "/$defs/source/properties/pages/properties"): (
        ("GenericDesktop", "Simulation", "Button", "Telephony", "Consumer"),
        HID_PAGE,
    ),
    ("crosswalk", "/$defs/source/properties/pages/required"): (
        ("GenericDesktop", "Simulation", "Button", "Telephony", "Consumer"),
        HID_PAGE,
    ),
    ("controller", "/$defs/modes/contains/properties/id/const"): (
        ("default",),
        MODE_ID,
    ),
    ("controller", "/$defs/mode/if/properties/id/const"): (("default",), MODE_ID),
    ("settings", "/properties/pauseShortcut/properties/key/enum"): (
        tuple("0123456789"),
        "a key is named by the character it types, and a digit key types a digit",
    ),
}

# Property-name maps a field-name enum is checked against. A source is a list of
# (schema, pointer to a `properties` map); `SETTING_PATHS` and `PROTOCOL_PARAMETERS` are computed.
TUNING = [("controller", "/$defs/tuning/properties")]
RECORD = [("controller", "/properties")]
SESSION = [("controller", "/$defs/session/properties")]
PROTOCOL = [("controller", "/$defs/protocol/properties")]
HID_INPUT = [("controller", "/$defs/hidInput/properties")]
SETTING_PATHS = "dotted paths through the properties of settings"
PROTOCOL_PARAMETERS = "the keys of `parameters` in Resources/Protocols/*.plist"

# Settings the command line names that the settings document does not store.
UNSTORED_SETTINGS = {
    "launchAtLogin": (
        "the login-item state belongs to the operating system's login-item service, so the "
        "settings document has no property for it; only `launchAtLoginOptOut` is stored"
    )
}


# (schema, pointer, source): the values at `pointer` name fields, so they are lowerCamelCase
# (dotted for nested settings) and each is a property name found at `source`.
FIELD_NAME_ENUMS: list[tuple[str, str, Any]] = [
    ("protocol-description", "/properties/tuningKeys/items/enum", TUNING),
    ("protocol-description", "/properties/rawUSBTuningKeys/items/enum", TUNING),
    (
        "protocol-description",
        "/$defs/descriptionKeepAliveHIDWrite/properties/resendTuning/enum",
        TUNING,
    ),
    (
        "protocol-description",
        "/$defs/descriptionKeepAliveUSBWrite/properties/resendTuning/enum",
        TUNING,
    ),
    (
        "protocol-description",
        "/properties/recordSections/items/enum",
        RECORD + SESSION + PROTOCOL + HID_INPUT,
    ),
    (
        "protocol-description",
        "/allOf/2/if/not/anyOf/0/properties/recordSections/contains/const",
        RECORD,
    ),
    (
        "protocol-description",
        "/allOf/2/if/not/anyOf/1/properties/recordSections/contains/const",
        HID_INPUT,
    ),
    (
        "protocol-description",
        "/allOf/3/if/not/properties/recordSections/contains/const",
        SESSION,
    ),
    (
        "protocol-description",
        "/allOf/0/if/properties/recordSections/contains/const",
        RECORD,
    ),
    (
        "protocol-description",
        "/allOf/1/if/properties/recordSections/contains/const",
        HID_INPUT,
    ),
    ("protocol-description", "/properties/sessionKeys/items/enum", SESSION),
    (
        "protocol-description",
        "/$defs/startupWhen/properties/parameter/enum",
        PROTOCOL_PARAMETERS,
    ),
    (
        "protocol-description",
        "/properties/parameters/propertyNames/enum",
        PROTOCOL_PARAMETERS,
    ),
    ("controller-patch", "/then/properties/patch/propertyNames/const", RECORD),
    (
        "cli-output",
        "/$defs/sharedTuningKey/enum",
        TUNING,
    ),
    ("cli-output", "/$defs/sharedSettingKey/enum", SETTING_PATHS),
    ("cli-output", "/$defs/sharedSetting/properties/key/anyOf/1/enum", SETTING_PATHS),
    ("cli-output", "/$defs/recordDraft/properties/missingSections/items/enum", RECORD),
]


def pending() -> dict[str, dict[str, list[str]]]:
    with PENDING_FILE.open(encoding="utf-8") as source:
        return json.load(source)


def property_names(
    documents: dict[str, Any], source: list[tuple[str, str]]
) -> set[str]:
    names: set[str] = set()
    for schema, pointer in source:
        names.update(cast("dict[str, Any]", resolve(documents[schema], pointer)))
    return names


def setting_paths(node: Any, prefix: str = "") -> set[str]:
    paths: set[str] = set()
    for name, child in cast("dict[str, Any]", node.get("properties", {})).items():
        paths.add(prefix + name)
        paths |= setting_paths(child, f"{prefix}{name}.")
    return paths


def protocol_parameters() -> set[str]:
    names: set[str] = set()
    for path in sorted(PROTOCOLS.glob("*.plist")):
        names.update(plistlib.loads(path.read_bytes()).get("parameters", {}))
    return names


def values_at(document: Any, pointer: str) -> list[str]:
    node = resolve(document, pointer)
    return cast("list[str]", node if isinstance(node, list) else [node])


def unexplained(documents: dict[str, Any]) -> list[tuple[str, Hit]]:
    """Every rule break not covered by EXCEPTIONS, FIELD_NAME_ENUMS or the pending list."""
    field_pointers = {(schema, pointer) for schema, pointer, _ in FIELD_NAME_ENUMS}
    allowed = pending()
    found: list[tuple[str, Hit]] = []
    for schema, document in documents.items():
        for hit in violations(document):
            if (schema, hit.pointer) in field_pointers:
                continue
            excused, _ = EXCEPTIONS.get((schema, hit.pointer), ((), ""))
            if hit.value in excused:
                continue
            if hit.value in allowed.get(schema, {}).get(hit.pointer, []):
                continue
            found.append((schema, hit))
    return found


class NameRuleTests(unittest.TestCase):
    def test_an_acronym_in_a_name_is_upper_case_also_in_a_plural(self) -> None:
        for name in ("reportId", "reportIds", "vendorId", "sharedVirtualSdl", "usbIds"):
            with self.subTest(name=name):
                self.assertTrue(breaks_rule(Hit("name", "/properties", name)))
        for name in ("reportID", "reportIDs", "vendorIDs", "sharedVirtualSDL", "idle"):
            with self.subTest(name=name):
                self.assertFalse(breaks_rule(Hit("name", "/properties", name)))

    def test_a_defs_name_is_checked_like_a_property_name(self) -> None:
        document = {"$defs": {"sharedVirtualSdl": {}, "sharedVirtualSDL": {}}}
        self.assertEqual(
            [hit.value for hit in violations(document)], ["sharedVirtualSdl"]
        )


class SchemaNamingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.documents = schemas()

    def test_every_schema_is_walked(self) -> None:
        self.assertEqual(
            sorted(self.documents),
            sorted(
                path.name.removesuffix(".schema.json")
                for path in SCHEMAS.glob("*.schema.json")
            ),
        )
        self.assertGreater(len(self.documents), 10)

    def test_nothing_breaks_the_rule_outside_the_three_lists(self) -> None:
        self.assertEqual(unexplained(self.documents), [])

    def test_each_exception_points_at_a_value_that_breaks_the_rule(self) -> None:
        for (schema, pointer), (values, reason) in EXCEPTIONS.items():
            with self.subTest(schema=schema, pointer=pointer):
                self.assertTrue(reason)
                found = {
                    hit.value
                    for hit in violations(self.documents[schema])
                    if hit.pointer == pointer
                }
                self.assertEqual(found, set(values))

    def test_each_field_name_list_resolves_and_names_fields(self) -> None:
        settings = setting_paths(self.documents["settings"])
        parameters = protocol_parameters()
        self.assertTrue(parameters)
        for schema, pointer, source in FIELD_NAME_ENUMS:
            with self.subTest(schema=schema, pointer=pointer):
                values = values_at(self.documents[schema], pointer)
                self.assertTrue(values)
                if source == SETTING_PATHS:
                    known = settings | set(UNSTORED_SETTINGS)
                elif source == PROTOCOL_PARAMETERS:
                    known = parameters
                else:
                    known = property_names(self.documents, source)
                for value in values:
                    self.assertRegex(value, FIELD_PATH)
                    self.assertIn(value, known)

    def test_unstored_settings_are_not_settings_properties(self) -> None:
        settings = setting_paths(self.documents["settings"])
        for name, reason in UNSTORED_SETTINGS.items():
            self.assertNotIn(name, settings)
            self.assertTrue(reason)
            values = values_at(
                self.documents["cli-output"], "/$defs/sharedSettingKey/enum"
            )
            self.assertIn(name, values)

    def test_no_field_name_list_overlaps_the_other_lists(self) -> None:
        field_pointers = {(schema, pointer) for schema, pointer, _ in FIELD_NAME_ENUMS}
        self.assertEqual(len(field_pointers), len(FIELD_NAME_ENUMS))
        self.assertEqual(field_pointers & set(EXCEPTIONS), set())
        for schema, pointers in pending().items():
            self.assertEqual(
                {(schema, pointer) for pointer in pointers} & field_pointers, set()
            )
            self.assertEqual(
                {(schema, pointer) for pointer in pointers} & set(EXCEPTIONS), set()
            )

    def test_the_pending_list_is_empty(self) -> None:
        self.assertEqual({schema: p for schema, p in pending().items() if p}, {})

    def test_every_pending_entry_still_breaks_the_rule(self) -> None:
        for schema, pointers in pending().items():
            self.assertIn(schema, self.documents)
            current: dict[str, list[str]] = {}
            for hit in violations(self.documents[schema]):
                current.setdefault(hit.pointer, []).append(hit.value)
            for pointer, values in pointers.items():
                with self.subTest(schema=schema, pointer=pointer):
                    self.assertTrue(values)
                    self.assertEqual(len(values), len(set(values)))
                    self.assertFalse(set(values) - set(current.get(pointer, [])))


class NamingRuleTests(unittest.TestCase):
    def test_accepts_conforming_names(self) -> None:
        schema = {
            "properties": {
                "kind": {"enum": ["XboxGIP", "HIDDescriptor"], "default": "XboxGIP"},
                "mode": {"const": "Read"},
            },
            "required": ["kind"],
        }
        self.assertEqual(violations(schema), [])

    def test_rejects_a_lowercase_value_and_a_snake_case_property(self) -> None:
        schema = {
            "properties": {
                "kind": {"enum": ["Fine", "notFine"], "default": "notFine"},
                "tap_on_press": {"const": "kebab-case"},
                "Upper": {"type": "string"},
            },
            "required": ["tap_on_press"],
        }
        self.assertCountEqual(
            violations(schema),
            [
                Hit("value", "/properties/kind/enum", "notFine"),
                Hit("value", "/properties/kind/default", "notFine"),
                Hit("name", "/properties", "tap_on_press"),
                Hit("name", "/properties", "Upper"),
                Hit("value", "/properties/tap_on_press/const", "kebab-case"),
                Hit("name", "/required", "tap_on_press"),
            ],
        )

    def test_rejects_an_acronym_spelled_as_a_word(self) -> None:
        for value in (
            "SdlCompatible",
            "ExtensionOwnedUsb",
            "SystemHidVisible",
            "BluetoothLe",
            "Ps3",
        ):
            with self.subTest(value=value):
                self.assertTrue(breaks_rule(Hit("value", "/enum", value)))

    def test_accepts_acronyms_and_words_that_start_like_one(self) -> None:
        for value in (
            "SDLCompatible",
            "Hidden",
            "HIDDescriptor",
            "Identity",
            "Leaf",
            "Usbx",
            "Idle",
        ):
            with self.subTest(value=value):
                self.assertFalse(breaks_rule(Hit("value", "/enum", value)))

    def test_checks_a_default_beside_a_reference_and_dependent_required_names(
        self,
    ) -> None:
        schema = {
            "properties": {"mode": {"$ref": "#/$defs/mode", "default": "fast"}},
            "dependentRequired": {"snake_key": ["other_key", "fine"]},
        }
        self.assertCountEqual(
            violations(schema),
            [
                Hit("value", "/properties/mode/default", "fast"),
                Hit("name", "/dependentRequired", "snake_key"),
                Hit("name", "/dependentRequired/snake_key", "other_key"),
            ],
        )

    def test_a_default_without_an_enum_is_not_checked(self) -> None:
        self.assertEqual(
            violations({"properties": {"name": {"default": "free text"}}}), []
        )

    def test_an_unlisted_violation_is_reported(self) -> None:
        documents = {"planted": {"properties": {"kind": {"enum": ["notFine"]}}}}
        self.assertEqual(
            unexplained(documents),
            [("planted", Hit("value", "/properties/kind/enum", "notFine"))],
        )


if __name__ == "__main__":
    unittest.main()
