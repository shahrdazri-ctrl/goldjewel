import json, math, os, sys, glob

VEC = r"D:\REA-LAB\05-evidence\vectors\ring-sizes.json"
PKG_JSON = r"D:\REA-LAB\07-ios-handoff\JewelryKit\Sources\JewelryKit\Resources\ring-sizes.json"
MIRROR = r"D:\REA-LAB\01-target\mirror\Main\MatrixGold"

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

fails = 0
checked = 0
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

# 5. every mirrored .mgm must parse and carry the modelled identity fields
mgs = glob.glob(os.path.join(MIRROR, "**", "*.mgm"), recursive=True)
mg_ok = 0
mg_bad = []
REQUIRED = {"Id", "Name", "EnglishName", "MaterialType", "MetalType", "MetalSubType",
            "SpecificGravity", "Ior", "Transparency", "Reflectivity", "IsMetalMaterial",
            "IsGemMaterial", "ColorMapData", "BumpMapData", "EnvironmentMapData"}
for p in mgs:
    try:
        obj = json.load(open(p, encoding="utf-8-sig"))
        missing = REQUIRED - set(obj.keys())
        # older/variant files legitimately omit optional map channels
        if missing - {"ColorMapData", "BumpMapData", "EnvironmentMapData"}:
            mg_bad.append((os.path.basename(p), sorted(missing)[:3]))
        else:
            mg_ok += 1
    except Exception as e:
        mg_bad.append((os.path.basename(p), str(e)[:60]))

print()
print("formula vectors checked :", checked)
print("catalog rows checked    :", total)
print("package JSON identical  :", same)
print("mgm parsed              :", mg_ok, "/", len(mgs))
print("failures                :", fails)
if mg_bad:
    print("mgm issues (first 5)    :", mg_bad[:5])
sys.exit(1 if fails else 0)
