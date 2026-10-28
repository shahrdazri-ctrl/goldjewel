import base64
import collections
import glob
import json
import math
import os
import re
import sys

# Paths resolve from this file, so the same validator runs in the lab (D:) and
# from a git checkout in CI. R() keeps the historical Windows-style literals
# readable while joining with the host separator.
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def R(path):
    return os.path.join(ROOT, *path.split("\\"))


def J(base, *fragments):
    parts = []
    for fragment in fragments:
        parts.extend(fragment.split("\\"))
    return os.path.join(base, *parts)


VEC = R(r"05-evidence\vectors\ring-sizes.json")
PKG_JSON = R(r"07-ios-handoff\JewelryKit\Sources\JewelryKit\Resources\ring-sizes.json")
MIRROR = R(r"01-target\mirror\Main\MatrixGold")
HAS_MIRROR = os.path.isdir(MIRROR)
HAS_DECOMPILED = os.path.isdir(R(r"03-decompiled"))
SWIFT = R(r"07-ios-handoff\JewelryKit\Sources\JewelryKit")
SWIFT_TESTS = R(r"07-ios-handoff\JewelryKit\Tests\JewelryKitTests")
REAL_FIXTURES = [
    R(r"07-ios-handoff\JewelryKit\Tests\JewelryKitTests\Fixtures\real-groundplane.mgm"),
    R(r"07-ios-handoff\JewelryKit\Tests\JewelryKitTests\Fixtures\real-metal.mgm"),
]
CS_REGION = R(r"03-decompiled\raw\CSRingSizes\CSRingSizes.Enumerations\RingSizeRegion.cs")
CS_ENUMS = {
    "MaterialOwner": "MaterialOwner.cs",
    "MaterialType": "MaterialType.cs",
    "MetalType": "MetalType.cs",
    "MetalSubType": "MetalSubType.cs",
    "MetalQuality": "MetalQuality.cs",
    "MaterialSubType": "MaterialSubType.cs",
    "RenderTextureType": "RenderTextureType.cs",
}
CS_ENUM_DIR = R(r"03-decompiled\raw\Common\Common.CyclesModels")

d = json.load(open(VEC, encoding="utf-8"))
regions = {r["region"]: r for r in d["regions"]}

def r2(x):  # .NET Math.Round(x, 2) == banker's rounding
    return round(x, 2)

FORMULA = {
    "Uk": lambda i: ((i / 2.0) * 1.25 + 37.55) / math.pi,
    "Jp": lambda i: (i + 38.0) / 3.0,
    "Eu": lambda i: (i + 41) / math.pi,
    "Fr": lambda i: (i / 4.0 + 41.0) / math.pi,
    "Ch": lambda i: (i / 4.0 + 41.0) / math.pi,
    "De": lambda i: (i + 53) / 4.0,
    "Us": lambda i: ((i / 4.0) * 0.102 + 1.43) / math.pi * 25.4,
}

def size_name(region, i):
    fraction = {1: " 1/4", 2: " 1/2", 3: " 3/4"}.get(i % 4, "")
    if region == "Us":
        return f"{i // 4}" + fraction
    if region == "Uk":
        value = f"Z+{(i - 50) // 2}" if i >= 52 else chr(65 + i // 2)
        return value + (" 1/2" if i % 2 else "")
    if region == "Eu":
        return str(i + 41)
    if region == "Jp":
        return str(i)
    if region == "Fr":
        return f"{i // 4 + 41}" + fraction
    if region == "De":
        n = i + 53
        return f"{n // 4}" + {1: " 1/4", 2: " 1/2", 3: " 3/4"}.get(n % 4, "")
    if region == "Ch":
        return f"{i // 4 + 1}" + fraction
    raise KeyError(region)

fails = 0
checked = 0
skipped = []
if not HAS_DECOMPILED:
    skipped.append("C# enum sources (03-decompiled absent from this checkout)")
if not HAS_MIRROR:
    skipped.append("257-file .mgm corpus (01-target absent from this checkout)")
# 1. formula regions must match every vector exactly
for region, fn in FORMULA.items():
    for row in regions[region]["sizes"]:
        checked += 1
        expect = r2(fn(row["index"]))
        if abs(expect - row["diameterMM"]) > 1e-9:
            fails += 1
            print("DIAM MISMATCH", region, row["index"], expect, row["diameterMM"])
        if abs(r2(fn(row["index"]) / 2.0) - row["radiusMM"]) > 1e-9:
            fails += 1
            print("RADIUS MISMATCH", region, row["index"], row["radiusMM"])
        expect_name = size_name(region, row["index"])
        if row["name"] != expect_name:
            fails += 1
            print("NAME MISMATCH", region, row["index"], expect_name, row["name"])

# 2. structural invariants for all regions
total = 0
for name, reg in regions.items():
    assert reg["count"] == len(reg["sizes"]), (name, reg["count"], len(reg["sizes"]))
    for i, row in enumerate(reg["sizes"]):
        total += 1
        if row["index"] != i:
            fails += 1
            print("INDEX NOT SEQUENTIAL", name, i, row["index"])
        if not isinstance(row["name"], str) or not row["name"]:
            fails += 1
            print("EMPTY NAME", name, i)
        if not (5.0 < row["diameterMM"] < 40.0):
            fails += 1
            print("IMPLAUSIBLE DIAMETER", name, i, row["diameterMM"])

# 3. formulas must be monotonic where defined
for region, fn in FORMULA.items():
    ds = [r["diameterMM"] for r in regions[region]["sizes"]]
    if any(b <= a for a, b in zip(ds, ds[1:])):
        fails += 1
        print("NON MONOTONIC", region)

# 4. package resource must be identical to the evidence vectors
a = open(VEC, "rb").read()
b = open(PKG_JSON, "rb").read()
same = a == b
if not same:
    fails += 1
    print("PACKAGE JSON DIFFERS", len(a), len(b))

# ---------------------------------------------------------------------------
# 5. Mechanical Swift conformance harness
#
# The package has no local Swift toolchain, so this checks the two things a
# compiler cannot check without running the decoder: whether every CodingKey
# and declared type can accept the real JSON, and whether every enum raw value
# exists in the shipped evidence. It deliberately fails on unknown JSON keys,
# because JSONDecoder silently drops them.
# ---------------------------------------------------------------------------

def read_text(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def decl_body(text, keyword, name):
    """Return the brace-balanced body of a struct/enum declaration."""
    match = re.search(r"\b" + keyword + r"\s+" + re.escape(name) + r"\b[^{]*\{", text)
    if not match:
        return None
    start = match.end() - 1
    depth = 0
    for index in range(start, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    return None


def parse_props(body):
    props = {}
    for line in body.splitlines():
        match = re.match(r"\s*public\s+var\s+([A-Za-z_]\w*)\s*:\s*([^{]+?)\s*$", line)
        if match:
            props[match.group(1)] = match.group(2).strip()
    return props


def parse_coding_keys(body):
    block = decl_body(body, "enum", "CodingKeys")
    if block is None:
        return {}
    return {
        json_key: swift_name
        for swift_name, json_key in re.findall(
            r'\bcase\s+([A-Za-z_]\w*)\s*=\s*"([^"]+)"', block
        )
    }


def parse_enum(text, name):
    header = re.search(r"\benum\s+" + re.escape(name) + r"\b\s*:\s*([A-Za-z_]\w*)", text)
    body = decl_body(text, "enum", name)
    if header is None or body is None:
        raise RuntimeError("cannot parse enum " + name)
    raw_type = header.group(1)
    if name == "RingSizeRegion":
        body = body.split("public enum Kind", 1)[0]

    cases = []
    next_int = 0
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("case "):
            continue
        for token in line[5:].split(","):
            token = token.strip()
            if not token:
                continue
            match = re.match(r"^([A-Za-z_]\w*)(?:\s*=\s*(.+))?$", token)
            if not match:
                raise RuntimeError("cannot parse enum case " + name + "." + token)
            case_name, raw = match.group(1), match.group(2)
            if raw_type == "Int":
                if raw is None:
                    value = next_int
                else:
                    value = int(raw.strip())
                next_int = value + 1
            elif raw_type == "String":
                if raw is None or not raw.strip().startswith('"'):
                    raise RuntimeError("String enum case without a literal: " + name + "." + case_name)
                value = raw.strip()[1:-1]
            else:
                raise RuntimeError("unsupported enum raw type " + raw_type)
            cases.append((case_name, value))
    if not cases:
        raise RuntimeError("no cases parsed for enum " + name)
    return {"raw": raw_type, "cases": cases}


def make_schema(text, struct_name):
    body = decl_body(text, "struct", struct_name)
    if body is None:
        raise RuntimeError("cannot parse struct " + struct_name)
    props = parse_props(body)
    keys = parse_coding_keys(body)
    by_json = {}
    for json_key, swift_name in keys.items():
        if swift_name not in props:
            raise RuntimeError(
                struct_name + ".CodingKeys." + swift_name + " has no stored property"
            )
        by_json[json_key] = (swift_name, props[swift_name])
    return {"props": props, "by_json": by_json}


material_text = strip_comments(read_text(J(SWIFT, r"MaterialIO\MGMaterial.swift")))
ring_text = strip_comments(read_text(J(SWIFT, r"RingSizing\RingSizeRegion.swift")))
math_text = strip_comments(read_text(J(SWIFT, r"RingSizing\RingSizeMath.swift")))

material_schema = make_schema(material_text, "MGMaterial")
map_schema = make_schema(material_text, "MaterialMapData")
schemas = {"MGMaterial": material_schema, "MaterialMapData": map_schema}

enums = {}
for enum_name in [
    "MaterialOwner",
    "MaterialType",
    "MetalType",
    "MetalSubType",
    "MetalQuality",
    "MaterialSubType",
    "RenderTextureType",
]:
    enums[enum_name] = parse_enum(material_text, enum_name)

region_enum = parse_enum(ring_text, "RingSizeRegion")
kind_enum = parse_enum(ring_text, "Kind")
region_raw = {name: value for name, value in region_enum["cases"]}

swift_fails = 0
issue_seen = set()
issues = []

def issue(message, count=1):
    global swift_fails
    swift_fails += count
    if message not in issue_seen:
        issue_seen.add(message)
        issues.append(message)

# C# enums have no explicit initializers here, so declaration order is the raw
# value. This also covers values absent from the 257-file corpus (MaterialOwner
# User/Public, for example), which a purely data-driven check cannot see.
for enum_name, filename in CS_ENUMS.items():
    if not HAS_DECOMPILED:
        break
    path = os.path.join(CS_ENUM_DIR, filename)
    if not os.path.exists(path):
        issue(f"{enum_name}: missing assembly source {path}")
        continue
    cs_body = decl_body(read_text(path), "enum", enum_name)
    cs_names = re.findall(r"(?m)^\s*([A-Za-z_]\w*),?\s*$", cs_body or "")
    if not cs_names:
        issue(f"{enum_name}: no cases parsed from {path}")
        continue
    swift_values = [value for _, value in enums[enum_name]["cases"]]
    if swift_values != list(range(len(cs_names))):
        issue(
            f"{enum_name}: Swift raw values {swift_values} do not match assembly "
            f"ordinals {list(range(len(cs_names)))} ({cs_names})"
        )

def is_int(value):
    return isinstance(value, int) and not isinstance(value, bool)


def json_kind(value):
    if isinstance(value, bool):
        return "bool"
    if isinstance(value, int):
        return "int"
    if isinstance(value, float):
        return "float"
    if isinstance(value, str):
        return "string"
    if value is None:
        return "null"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    return type(value).__name__


def check_value(value, declared_type, path, source, counts=None):
    optional = declared_type.strip().endswith("?")
    base = declared_type.strip()[:-1].strip() if optional else declared_type.strip()

    if value is None:
        if not optional:
            issue(f"{source}: {path}: null cannot decode into non-optional {base}")
        return

    if base in schemas:
        if not isinstance(value, dict):
            issue(
                f"{source}: {path}: expected object for {base}, got {json_kind(value)}"
            )
        else:
            check_object(value, base, source, counts)
        return

    if base in enums:
        allowed = {raw for _, raw in enums[base]["cases"]}
        if enums[base]["raw"] == "Int":
            if not is_int(value) or value not in allowed:
                issue(
                    f"{source}: {path}: {base} raw value {value!r} is not one of "
                    f"{sorted(allowed)}"
                )
        else:
            if not isinstance(value, str) or value not in allowed:
                issue(
                    f"{source}: {path}: {base} raw value {value!r} is not one of "
                    f"{sorted(allowed)}"
                )
        return

    if base in ("Int", "Int32", "Int64", "UInt", "UInt32", "UInt64"):
        if not is_int(value):
            issue(f"{source}: {path}: expected {base}, got {json_kind(value)} {value!r}")
    elif base in ("Double", "Float", "CGFloat"):
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            issue(f"{source}: {path}: expected {base}, got {json_kind(value)} {value!r}")
    elif base == "String":
        if not isinstance(value, str):
            issue(f"{source}: {path}: expected String, got {json_kind(value)} {value!r}")
    elif base == "Bool":
        if not isinstance(value, bool):
            issue(f"{source}: {path}: expected Bool, got {json_kind(value)} {value!r}")
    elif base == "Data":
        if not isinstance(value, str):
            issue(f"{source}: {path}: expected base64 String for Data, got {json_kind(value)}")
        else:
            try:
                base64.b64decode(value, validate=True)
            except Exception:
                issue(f"{source}: {path}: invalid base64 for Data")
    elif base.startswith("[") and base.endswith("]"):
        if not isinstance(value, list):
            issue(f"{source}: {path}: expected array, got {json_kind(value)}")
    else:
        issue(f"{source}: {path}: cannot mechanically check declared type {base!r}")


def check_object(obj, struct_name, source, counts=None):
    by_json = schemas[struct_name]["by_json"]
    for key, value in obj.items():
        if key not in by_json:
            issue(
                f"{source}: JSON key {key!r} is not in {struct_name}.CodingKeys; "
                "JSONDecoder would silently drop it"
            )
            continue
        swift_name, declared_type = by_json[key]
        if counts is not None:
            counts[key] += 1
        check_value(value, declared_type, f"{struct_name}.{swift_name}", source, counts)


mg_files = sorted(glob.glob(os.path.join(MIRROR, "**", "*.mgm"), recursive=True))
if HAS_MIRROR and len(mg_files) != 257:
    issue(f"MGM CORPUS: expected 257 files, found {len(mg_files)}")

top_counts = collections.Counter()
nested_counts = collections.Counter()
mg_ok = 0
mg_bad = []
REQUIRED = {
    "Id", "Name", "EnglishName", "MaterialType", "MetalType", "MetalSubType",
    "SpecificGravity", "Ior", "Transparency", "Reflectivity", "IsMetalMaterial",
    "IsGemMaterial", "ColorMapData", "BumpMapData", "EnvironmentMapData",
}

for path in mg_files:
    source = os.path.basename(path)
    try:
        obj = json.load(open(path, encoding="utf-8-sig"))
    except Exception as exc:
        mg_bad.append((source, str(exc)[:60]))
        issue(f"{source}: JSON parse failed: {exc}")
        continue

    check_object(obj, "MGMaterial", source, top_counts)

    missing = REQUIRED - set(obj.keys())
    if missing - {"ColorMapData", "BumpMapData", "EnvironmentMapData"}:
        mg_bad.append((source, sorted(missing)[:3]))
    else:
        mg_ok += 1

# Every declared top-level key must be observed at least once; a declared key
# that never appears in the 257-file corpus is a schema ghost, not a decode path.
for json_key in material_schema["by_json"]:
    if not mg_files:
        break
    if top_counts[json_key] == 0:
        issue(
            f"MGMaterial: declared key {json_key!r} is not present in any of the "
            f"{len(mg_files)} material files"
        )

# Nested map records are null in the real corpus; the synthetic fixture is the
# only object-bearing sample, so check it separately rather than calling every
# real-file absence a failure.
for path in REAL_FIXTURES + [J(SWIFT_TESTS, r"Fixtures\sample.mgm")]:
    if not os.path.exists(path):
        issue(f"FIXTURE: missing {os.path.basename(path)}")
        continue
    try:
        obj = json.load(open(path, encoding="utf-8-sig"))
    except Exception as exc:
        issue(f"{os.path.basename(path)}: JSON parse failed: {exc}")
        continue
    check_object(obj, "MGMaterial", os.path.basename(path), nested_counts)

# ---------------------------------------------------------------------------
# 6. Ring-size enum, catalog and test invariants
# ---------------------------------------------------------------------------
vector_raw = set(regions)
enum_raw = set(region_raw.values())
if vector_raw != enum_raw:
    issue(
        "RingSizeRegion: enum/vector region sets differ; "
        f"extra in Swift={sorted(enum_raw - vector_raw)}, "
        f"missing in Swift={sorted(vector_raw - enum_raw)}"
    )
if len(region_raw) != len(regions):
    issue(
        f"RingSizeRegion: {len(region_raw)} cases but catalog has {len(regions)} regions"
    )

if not os.path.exists(CS_REGION) and HAS_DECOMPILED:
    issue(f"RingSizeRegion: missing assembly source {CS_REGION}")
elif not HAS_DECOMPILED:
    pass
else:
    cs_body = decl_body(read_text(CS_REGION), "enum", "RingSizeRegion")
    cs_cases = re.findall(r"(?m)^\s*([A-Za-z_]\w*),?\s*$", cs_body or "")
    if set(cs_cases) != enum_raw:
        issue(
            "RingSizeRegion: Swift enum does not match the assembly enum; "
            f"extra in Swift={sorted(enum_raw - set(cs_cases))}, "
            f"missing in Swift={sorted(set(cs_cases) - enum_raw)}"
        )
    if len(cs_cases) != len(region_raw):
        issue(
            f"RingSizeRegion: assembly has {len(cs_cases)} cases, "
            f"Swift has {len(region_raw)}"
        )

kind_values = {raw for _, raw in kind_enum["cases"]}
for name, reg in regions.items():
    if reg.get("kind") not in kind_values:
        issue(f"{name}: kind {reg.get('kind')!r} is not in RingSizeRegion.Kind")

math_body = decl_body(math_text, "enum", "RingSizeMath")
if math_body is None:
    issue("RingSizeMath: cannot parse enum body")
else:
    for case_name, literal in re.findall(r"case \.(\w+): return (\d+)", math_body):
        raw = region_raw.get(case_name)
        if raw is None:
            issue(f"RingSizeMath: case .{case_name} has no RingSizeRegion case")
        elif int(literal) != regions[raw]["count"]:
            issue(
                f"RingSizeMath.{case_name}: returns {literal}, "
                f"catalog has {regions[raw]['count']}"
            )

tests_text = read_text(os.path.join(SWIFT_TESTS, "RingSizingTests.swift"))
match = re.search(r"catalog\.regions\.count,\s*(\d+)", tests_text)
if not match:
    issue("RingSizingTests: no regions.count assertion found")
elif int(match.group(1)) != len(regions):
    issue(
        f"RingSizingTests: asserts {match.group(1)} regions, catalog has {len(regions)}"
    )

match = re.search(r"catalog\.totalSizeCount,\s*(\d+)", tests_text)
expected_total = sum(reg["count"] for reg in regions.values())
if not match:
    issue("RingSizingTests: no totalSizeCount assertion found")
elif int(match.group(1)) != expected_total:
    issue(
        f"RingSizingTests: asserts {match.group(1)} sizes, catalog has {expected_total}"
    )

for match in re.finditer(
    r"catalog\.table\(for: \.(\w+)\)\?\.count,\s*(\d+)\)", tests_text
):
    case_name, literal = match.group(1), int(match.group(2))
    raw = region_raw.get(case_name)
    if raw is None:
        issue(f"RingSizingTests: table(for: .{case_name}) has no enum case")
    elif regions[raw]["count"] != literal:
        issue(
            f"RingSizingTests: table(for: .{case_name}) asserts {literal}, "
            f"catalog has {regions[raw]['count']}"
        )

material_tests_text = read_text(os.path.join(SWIFT_TESTS, "MaterialTests.swift"))
for fixture_name in ("real-groundplane", "real-metal"):
    if fixture_name not in material_tests_text:
        issue(f"MaterialTests: does not reference real fixture {fixture_name}")

# ---------------------------------------------------------------------------
# 7. Report
# ---------------------------------------------------------------------------
print()
print("formula vectors checked :", checked)
print("catalog rows checked    :", total)
print("package JSON identical  :", same)
print("mgm parsed              :", mg_ok, "/", len(mg_files) if HAS_MIRROR else "skipped")
print("swift material sources  :", len(glob.glob(os.path.join(SWIFT, "MaterialIO", "*.swift"))))
print("swift material keys     :", len(material_schema["by_json"]))
print("swift map keys          :", len(map_schema["by_json"]))
print("swift region cases      :", len(region_raw), "/ catalog", len(regions))
print("swift conformance       :", "clean" if swift_fails == 0 else f"{swift_fails} failures")
print("failures                :", fails + swift_fails)
if mg_bad:
    print("mgm issues (first 5)    :", mg_bad[:5])
if skipped:
    print("skipped                 :", "; ".join(skipped))
if issues:
    print("swift issues (first 12) :")
    for message in issues[:12]:
        print("  -", message)
sys.exit(1 if (fails or swift_fails) else 0)
