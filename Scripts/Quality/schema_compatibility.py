"""Compare `cli-output.schema.json` with its copy at the last release tag.

Within a major version, `ojd --json` output only gains keys and values,
so a program that reads one release's output keeps working with the next.
A change breaks such a program when it removes a command's output, a property, an enum or const value,
or a `oneOf`, `anyOf`, or `allOf` branch;
when a key that was always present becomes optional;
or when a value can take a type that it could not take before.
A new major version can make any of these changes.
The comparison follows `$ref`s on both sides, also into the other schema documents.
"""

from __future__ import annotations

import json
import plistlib
import subprocess
from pathlib import Path
from typing import Any, NamedTuple

ROOT_SCHEMA = "cli-output.schema.json"
SCHEMA_VERSION = "v1beta1"
# Where a tag keeps its schemas: the versioned directory, then the flat one that releases before
# the version segment used. This reads old tags only; OJD itself has no decoder for the flat layout.
SCHEMA_DIRECTORIES = (f"Resources/Schemas/{SCHEMA_VERSION}", "Resources/Schemas")
INFO_PLIST = Path("Sources/OpenJoystickDriver/App/Info.plist")

Documents = dict[str, dict[str, Any]]


class IncompatibleSchemaError(Exception):
    def __init__(self, tag: str, problems: list[str]) -> None:
        lines = "\n".join(f"  {problem}" for problem in problems)
        super().__init__(f"{ROOT_SCHEMA} breaks readers of the {tag} output:\n{lines}")


def git(root: Path, *args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, text=True
    ).stdout


def last_release_tag(root: Path) -> str:
    # Starting at HEAD^ skips a tag on HEAD, so a release commit is compared with the release
    # before it.
    return git(
        root, "describe", "--tags", "--abbrev=0", "--match", "[0-9]*", "HEAD^"
    ).strip()


def documents_at(root: Path, tag: str) -> Documents | None:
    """The schema documents at `tag`, or None when `tag` has no `cli-output.schema.json`."""
    for directory in SCHEMA_DIRECTORIES:
        try:
            names = git(root, "ls-tree", "--name-only", f"{tag}:{directory}").split()
        except subprocess.CalledProcessError:
            continue
        if ROOT_SCHEMA not in names:
            continue
        return {
            name: json.loads(git(root, "show", f"{tag}:{directory}/{name}"))
            for name in names
            if name.endswith(".schema.json")
        }
    return None


class Location(NamedTuple):
    document: str
    pointer: str
    schema: object

    def child(self, *tokens: str | int) -> Location:
        schema = self.schema
        pointer = self.pointer
        for token in tokens:
            assert isinstance(schema, (dict, list))
            schema = schema[token]  # type: ignore[index]
            pointer += "/" + str(token).replace("~", "~0").replace("/", "~1")
        return Location(self.document, pointer, schema)

    def __str__(self) -> str:
        return f"{self.document}#{self.pointer}"


def resolve(documents: Documents, location: Location) -> Location:
    while isinstance(location.schema, dict) and "$ref" in location.schema:
        target, _, fragment = str(location.schema["$ref"]).partition("#")
        location = Location(
            target or location.document, "", documents[target or location.document]
        )
        tokens = [
            token.replace("~1", "/").replace("~0", "~")
            for token in fragment.split("/")[1:]
        ]
        location = location.child(*tokens)
    return location


def json_type(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    return "array" if isinstance(value, list) else "object"


def values(schema: dict[str, Any]) -> list[object] | None:
    if "const" in schema:
        return [schema["const"]]
    return list(schema["enum"]) if "enum" in schema else None


def types(schema: dict[str, Any]) -> set[str] | None:
    """The types a value can take, or None when the schema does not limit them."""
    declared = schema.get("type")
    if isinstance(declared, str):
        return {declared}
    if isinstance(declared, list):
        return set(declared)
    allowed = values(schema)
    return None if allowed is None else {json_type(value) for value in allowed}


class Comparison:
    def __init__(self, old: Documents, new: Documents) -> None:
        self.old = old
        self.new = new
        self.problems: list[str] = []
        self.compared: set[tuple[str, str, str, str]] = set()

    def report(self, location: Location, problem: str) -> None:
        message = f"{location}: {problem}"
        if message not in self.problems:
            self.problems.append(message)

    def compare(self, old: Location, new: Location) -> None:
        old = resolve(self.old, old)
        new = resolve(self.new, new)
        key = (old.document, old.pointer, new.document, new.pointer)
        if key in self.compared:
            return
        self.compared.add(key)
        if not isinstance(old.schema, dict) or not isinstance(new.schema, dict):
            return
        old_schema: dict[str, Any] = old.schema
        new_schema: dict[str, Any] = new.schema

        old_types = types(old_schema)
        new_types = types(new_schema)
        if old_types is not None:
            if new_types is None:
                self.report(old, "can now be any type")
            else:
                added = sorted(
                    kind
                    for kind in new_types - old_types
                    if not (kind == "integer" and "number" in old_types)
                )
                if added:
                    self.report(old, "can now be " + " or ".join(added))

        old_values = values(old_schema)
        new_values = values(new_schema)
        if old_values is not None and new_values is not None:
            for value in old_values:
                if value not in new_values:
                    self.report(old, f"value {json.dumps(value)} removed")

        old_properties = old_schema.get("properties", {})
        new_properties = new_schema.get("properties", {})
        new_required = new_schema.get("required", [])
        for key in old_schema.get("required", []):
            removed = key in old_properties and key not in new_properties
            if key not in new_required and not removed:
                self.report(old, f'key "{key}" no longer required')
        for key in old_properties:
            if key in new_properties:
                self.compare(old.child("properties", key), new.child("properties", key))
            else:
                self.report(old.child("properties", key), "property removed")

        # An `if` is a condition on the output, not a shape of it,
        # so only its `then` and `else` are compared.
        for keyword in ("items", "additionalProperties", "then", "else"):
            if isinstance(old_schema.get(keyword), dict) and isinstance(
                new_schema.get(keyword), dict
            ):
                self.compare(old.child(keyword), new.child(keyword))
        for keyword in ("prefixItems", "oneOf", "anyOf", "allOf"):
            old_branches = old_schema.get(keyword, [])
            new_branches = new_schema.get(keyword, [])
            for index, branch in enumerate(old_branches):
                match = matching_branch(branch, index, new_branches)
                if match is None:
                    self.report(old.child(keyword, index), "branch removed")
                else:
                    self.compare(old.child(keyword, index), new.child(keyword, match))


def matching_branch(branch: object, index: int, branches: list[object]) -> int | None:
    """The index of the branch in `branches` that has `branch`'s `if`, or else the same index."""
    if isinstance(branch, dict) and "if" in branch:
        return next(
            (
                position
                for position, candidate in enumerate(branches)
                if isinstance(candidate, dict) and candidate.get("if") == branch["if"]
            ),
            None,
        )
    return index if index < len(branches) else None


def referenced_definitions(schema: object) -> set[str]:
    """The names of the `#/$defs/...` entries that `schema` refers to."""
    if isinstance(schema, dict):
        found = set().union(
            *(referenced_definitions(value) for value in schema.values())
        )
        reference = schema.get("$ref")
        if isinstance(reference, str) and reference.startswith("#/$defs/"):
            found.add(reference.removeprefix("#/$defs/").split("/")[0])
        return found
    if isinstance(schema, list):
        return set().union(*(referenced_definitions(value) for value in schema))
    return set()


def breaking_changes(old: Documents, new: Documents) -> list[str]:
    """Each change from `old` to `new` that breaks a reader of `old` output."""
    comparison = Comparison(old, new)
    old_root = Location(ROOT_SCHEMA, "", old[ROOT_SCHEMA])
    new_root = Location(ROOT_SCHEMA, "", new[ROOT_SCHEMA])
    old_definitions = old[ROOT_SCHEMA].get("$defs", {})
    new_definitions = new[ROOT_SCHEMA].get("$defs", {})
    # A command's output is a definition that no other definition refers to.
    # The shared definitions are checked where the command outputs refer to them,
    # so renaming one is fine.
    shared = referenced_definitions(old[ROOT_SCHEMA])
    for name in old_definitions:
        if name in new_definitions:
            comparison.compare(
                old_root.child("$defs", name), new_root.child("$defs", name)
            )
        elif name not in shared:
            comparison.report(old_root.child("$defs", name), "command output removed")
    return comparison.problems


def check(root: Path, current: Documents) -> str:
    """Compares `current` with the last release and returns a summary line.

    Raises `IncompatibleSchemaError` when a change breaks readers of the release's output.
    """
    tag = last_release_tag(root)
    with (root / INFO_PLIST).open("rb") as source:
        version = str(plistlib.load(source)["CFBundleShortVersionString"])
    if version.split(".")[0] != tag.split(".")[0]:
        return f"{version} is a new major version, so its output can drop keys and values of {tag}."
    released = documents_at(root, tag)
    if released is None:
        return f"{ROOT_SCHEMA} is new since {tag}, so no release output to stay compatible with."
    problems = breaking_changes(released, current)
    if problems:
        raise IncompatibleSchemaError(tag, problems)
    return f"{ROOT_SCHEMA} keeps every key and value of the {tag} output."
