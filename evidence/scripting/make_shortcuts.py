"""Writes three unsigned .shortcut files for 6.17 into the folder given as the first argument."""

import plistlib
import sys
import uuid
from pathlib import Path

BUNDLE = "com.openjoystickdriver"
DESCRIPTOR = {
    "BundleIdentifier": BUNDLE,
    "Name": "OpenJoystickDriver",
    "TeamIdentifier": "9PQP6CDMQT",
}


def intent(name, uid, **parameters):
    return {
        "WFWorkflowActionIdentifier": f"{BUNDLE}.{name}",
        "WFWorkflowActionParameters": {
            "AppIntentDescriptor": {**DESCRIPTOR, "AppIntentIdentifier": name},
            "UUID": uid,
            **parameters,
        },
    }


def output(uid, name):
    return {
        "Value": {"OutputUUID": uid, "Type": "ActionOutput", "OutputName": name},
        "WFSerializationType": "WFTextTokenAttachment",
    }


def first_controller():
    listed, first = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
    actions = [
        intent("GetControllersIntent", listed),
        {
            "WFWorkflowActionIdentifier": "is.workflow.actions.getitemfromlist",
            "WFWorkflowActionParameters": {
                "UUID": first,
                "WFInput": output(listed, "Controllers"),
                "WFItemSpecifier": "First Item",
            },
        },
    ]
    return actions, output(first, "Item from List")


def shortcut(actions, questions=()):
    return {
        "WFWorkflowActions": actions,
        "WFWorkflowClientVersion": "2607.0.1",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": 4282601983,
            "WFWorkflowIconGlyphNumber": 59511,
        },
        "WFWorkflowImportQuestions": list(questions),
        "WFWorkflowInputContentItemClasses": [
            "WFStringContentItem",
            "WFGenericFileContentItem",
        ],
        "WFWorkflowTypes": [],
    }


def main(folder):
    folder = Path(folder)
    actions, controller = first_controller()
    rumble = actions + [
        intent(
            "RumbleControllerIntent", str(uuid.uuid4()).upper(), controller=controller
        )
    ]
    actions, controller = first_controller()
    player = actions + [
        intent(
            "SetPlayerIndicatorIntent",
            str(uuid.uuid4()).upper(),
            controller=controller,
            player=2,
        )
    ]
    value = {
        "Value": {
            "string": "￼",
            "attachmentsByRange": {"{0, 1}": {"Type": "ExtensionInput"}},
        },
        "WFSerializationType": "WFTextTokenString",
    }
    profile = [
        intent(
            "SetProfileValueIntent", str(uuid.uuid4()).upper(), key="name", value=value
        )
    ]
    question = {
        "ActionIndex": 0,
        "Category": "Parameter",
        "DefaultValue": "",
        "ParameterKey": "profile",
        "Text": "Choose the profile that this shortcut renames.",
    }
    for name, document in (
        ("OJD Rumble First Controller", shortcut(rumble)),
        ("OJD Set Player First Controller", shortcut(player)),
        ("OJD Set Profile Value", shortcut(profile, [question])),
    ):
        (folder / f"{name}.shortcut").write_bytes(
            plistlib.dumps(document, fmt=plistlib.FMT_BINARY)
        )


main(sys.argv[1])
