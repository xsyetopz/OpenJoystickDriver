"""Count how many InputConfig library presets map to an OJD profile without loss.

Usage: python3 -I count_presets.py <path to InputConfig/Resources/ExamplePresets.swift>

The script only reads the file as text and parses the embedded JSON array
(`libraryJSON`). It runs no code from the clone.

Rule: a preset maps without loss when it has no blocker. A blocker is a
binding, modifier, or setting with no OJD profile equivalent (see the table
in the document). Descriptive text (subtitle, tips, row notes, category) is
not counted; the script prints how many presets carry it.
"""
import collections
import json
import sys

src = open(sys.argv[1], encoding="utf-8").read()
marker = 'static let libraryJSON = """'
start = src.index(marker) + len(marker)
presets = json.loads(src[start:src.index('"""', start)])

# Library input space: GCController extended-gamepad indices
# (ExamplePresets.swift header comment) -> OJD vocabulary controls.
BUTTONS = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13}  # South..TouchpadClick
STICK_AXES = {0, 1, 2, 3}          # LeftStickX/Y, RightStickX/Y, both directions
TRIGGER_AXES = {4, 5}              # LeftTrigger, RightTrigger, positive only
HAT_DIRS = {"U", "D", "L", "R"}    # hat 0 only -> DpadUp/Down/Left/Right

# HID usage codes the OJD Keyboard `key` enum covers (profile.schema.json).
OJD_KEY_USAGES = (
    set(range(4, 30)) | set(range(30, 40)) | {40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 51, 52, 53, 54, 55, 56, 57}
    | set(range(58, 70)) | {73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83}
    | set(range(84, 100)) | {100, 103, 117} | set(range(104, 112))
)  # 50 (Non-US #) and 101-102, 116, 112-115 have no OJD key name
MODIFIERS = {224: "Control", 225: "Shift", 226: "Alt", 227: "Meta",
             228: "Control", 229: "Shift", 230: "Alt", 231: "Meta"}
RIGHT_MODIFIERS = {228, 229, 230, 231}
MOUSE_BUTTONS = {0, 1, 2}  # Left, Right, Middle


def input_blockers(token):
    parts = token.split()
    if parts[0] == "btn" and int(parts[1]) in BUTTONS:
        return []
    if parts[0] == "axi":
        n, sign = int(parts[1]), parts[2]
        if n in STICK_AXES or (n in TRIGGER_AXES and sign == "+"):
            return []
        return ["input: axis with no OJD source (" + token + ")"]
    if parts[0] == "hat" and parts[1] == "0" and parts[2] in HAT_DIRS:
        return []
    return ["input: control outside the OJD vocabulary (" + token + ")"]


def output_blockers(outputs):
    """Blockers for one output list that fires together."""
    out = []
    keys, mods = [], []
    for o in outputs:
        t = o.split()
        kind = t[0]
        if kind == "key":
            code = int(t[1])
            if code in MODIFIERS:
                mods.append(code)
            elif code in OJD_KEY_USAGES:
                keys.append(code)
            else:
                out.append("output: key with no OJD key name")
        elif kind == "mbt":
            if int(t[1]) not in MOUSE_BUTTONS:
                out.append("output: mouse button beyond middle")
        elif kind in ("mou", "whe"):
            pass  # MouseMovement / Scroll, speed becomes axisTuning.gain
        elif kind == "whs":
            out.append("output: wheel step (one notch per press)")
        elif kind == "sys":
            out.append("output: system function " + t[1] + " (OJD systemKey/systemAction lacks it)")
        else:
            out.append("output: type " + kind + " with no OJD destination")
    if mods and not keys:
        out.append("output: modifier key alone (OJD keyboard destination needs a key)")
    if mods and len(keys) > 1:
        out.append("output: modifiers shared by several keys")
    if any(m in RIGHT_MODIFIERS for m in mods):
        out.append("output: right-hand modifier (OJD modifiers have no side)")
    return out


def row_blockers(b):
    out = input_blockers(b["input"])
    out += output_blockers(b["outputs"])
    if "hold" in b:
        if len(b["hold"]) != 1 or not 100 <= b.get("holdMs", 300) <= 5000:
            out.append("row: hold with several outputs or out-of-range time")
        out += output_blockers(b["hold"])
    if "double" in b:
        if len(b["double"]) != 1 or not 50 <= b.get("doubleMs", 300) <= 1000:
            out.append("row: double tap with several outputs or out-of-range time")
        out += output_blockers(b["double"])
    if "with" in b:
        out.append("row: chord (with)")
    for k in ("turbo", "deadzone", "outer", "curve", "variable", "ramp", "rumble", "speak"):
        if k in b:
            out.append("row: " + k)  # not present in this library; kept so a new field is not missed
    # repeatCount/repeatMs -> Macro (Tap, Wait, Tap); toggle -> behavior Toggle;
    # needs -> the source exists only on a model that has it. All three are mapped.
    return out


def preset_blockers(p):
    out = []
    if p["confineCursor"]:
        out.append("setting: confine cursor")
    if p["autoRecenter"]:
        out.append("setting: auto-recenter cursor")
    if p["hideCursor"]:
        out.append("setting: hide cursor")
    if p["appPath"]:
        out.append("setting: launch app on activation (appPath)")
    if p["launchURL"]:
        out.append("setting: launch URL on activation (launchURL)")
    if "drive" in p:
        out.append("setting: one-stick driving (drive)")
    seen = collections.Counter(b["input"] for b in p["bindings"])
    if any(n > 1 for n in seen.values()):
        out.append("row: one input bound twice")
    if len(p["displayName"]) > 80:
        out.append("name: longer than 80 characters")
    return out


print("presets read:", len(presets), "| distinct ids:", len({p["id"] for p in presets}))
cats = collections.Counter(p["category"] for p in presets)
print("categories:", dict(sorted(cats.items())))

rows_total = rows_clean = 0
by_feature = collections.Counter()      # presets blocked by each feature
only_feature = collections.Counter()    # presets whose single blocker is it
row_features = collections.Counter()    # rows blocked by each feature
clean_all = clean_rows = 0
for p in presets:
    feats = set(preset_blockers(p))
    row_feats = set()
    for b in p["bindings"]:
        rows_total += 1
        bl = set(row_blockers(b))
        # keep the feature class, not the token, so counts group
        bl = {x.split(" (")[0] if x.startswith("input:") else x for x in bl}
        if not bl:
            rows_clean += 1
        for x in bl:
            row_features[x] += 1
        row_feats |= bl
    feats_all = feats | row_feats
    for x in feats_all:
        by_feature[x] += 1
    if len(feats_all) == 1:
        only_feature[next(iter(feats_all))] += 1
    if not feats_all:
        clean_all += 1
    if not row_feats:
        clean_rows += 1

print("rows read:", rows_total, "| rows with no blocker:", rows_clean)
print("Presets that map without loss (all rules):", clean_all, "of", len(presets))
print("Presets whose bindings alone map without loss (preset settings ignored):", clean_rows, "of", len(presets))
print("Blocking feature -> presets blocked (sole blocker in brackets):")
for k, n in sorted(by_feature.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {n:4d} [{only_feature[k]:3d}]  {k}")
print("Blocking feature -> rows blocked:")
for k, n in sorted(row_features.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {n:4d}  {k}")

# Facts used by the document.
speeds = collections.Counter()
for p in presets:
    for b in p["bindings"]:
        for o in b["outputs"]:
            t = o.split()
            if t[0] in ("mou", "whe") and len(t) > 3:
                speeds[t[0]] += 1
print("rows with a mou/whe speed:", dict(speeds))
print("presets with at least one mou output:", sum(any(o.startswith("mou") for b in p["bindings"] for o in b["outputs"]) for p in presets))
print("presets with at least one whe output:", sum(any(o.startswith("whe") for b in p["bindings"] for o in b["outputs"]) for p in presets))
print("presets with repeatCount rows:", sum(any("repeatCount" in b for b in p["bindings"]) for p in presets))
print("presets with hold/double/toggle rows:", sum(any(k in b for b in p["bindings"] for k in ("hold", "double", "toggle")) for p in presets))
print("presets with btn 13 or a needs row:", sum(any(b["input"] == "btn 13" or "needs" in b for b in p["bindings"]) for p in presets))
print("presets with subtitle, tips, or notes (text OJD has no field for):",
      sum(1 for p in presets if p["subtitle"] or p["tips"] or any(b["note"] for b in p["bindings"])))
