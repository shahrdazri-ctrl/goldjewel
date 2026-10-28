#!/usr/bin/env python3
"""Generate the method triage ledger for the first-party assemblies.

Every first-party method gets exactly one class:

  port-as-is               behaviour carries over without new geometry work
  port-with-new-geometry   behaviour depends on Rhino geometry and must be rebuilt
  drop                     desktop shell, interop, legacy or resource plumbing

Classification is rule-based and every row records the rule that decided it, so
the ledger can be audited and corrected rather than trusted.

Usage:
  python Tools/triage.py [--db 04-index/symbols.sqlite] [--out 08-reports/triage-ledger.csv]
"""
from __future__ import annotations

import argparse
import collections
import csv
import os
import sqlite3
import sys

FIRST_PARTY = (
    "MatrixGold",
    "SharedTypes",
    "MatrixCommon",
    "Common",
    "Localization",
    "CS",
    "GV",
    "Gemvision",
    "Stuller",
    "SuperView",
    "Viewport2D",
    "MeshAPI",
    "DebugDraw",
    "Toast",
    "EventSystem",
)

GEOMETRY_ASSEMBLIES = {
    "CS",
    "CSBlocks",
    "CSGemInstance",
    "GVBuilders",
    "GemvisionGeometry",
    "Viewport2D",
    "MeshAPI",
}

DATA_ASSEMBLIES = {
    "Common",
    "SharedTypes",
    "MatrixCommon",
    "CSRingSizes",
    "CSMaterials",
    "CSDatas",
    "LocalizationCore",
}

DROP_ASSEMBLIES = {
    "MatrixGold",
    "MatrixGoldPlugin",
    "MatrixGoldRenderPlugin",
    "Localization",
    "SuperView",
    "DebugDraw",
    "Toast",
    "EventSystem",
}

GEOMETRY_WORDS = (
    "Brep", "Mesh", "Surface", "Curve", "Sweep", "Loft", "Boolean", "Extrude",
    "Revolve", "Intersect", "Prong", "Bezel", "Halo", "Cutter", "Rail", "Dome",
    "Gem", "Transform", "Tolerance", "Nurbs", "Solid", "Polyline", "Vertex",
    "ControlPoint", "Profile", "Cap", "Offset", "Blend", "Project", "Intersection",
)
DATA_WORDS = (
    "Json", "Serialize", "Deserialize", "Parse", "Format", "Convert", "Round",
    "Clamp", "Weight", "Carat", "RingSize", "Material", "Metal", "Color", "Guid",
    "Settings", "Config", "Option", "Save", "Load", "Read", "Write", "Import",
    "Export", "Clone", "Copy", "Equals", "Hash", "ToString", "Validate",
)
DROP_WORDS = (
    "Legacy", "Obsolete", "Deprecated", "Render", "Print", "Report", "Animation",
    "Camera", "Wizard", "Form", "Window", "Dialog", "Control", "Command",
)
INTEROP_MARKERS = ("Rhino", "ServiceModel", "Interop", "Win32", "ComVisible", "Windows")


def classify(assembly: str, namespace: str, type_name: str, method: str) -> tuple[str, str, str]:
    type_full = f"{namespace}.{type_name}" if namespace else type_name
    haystack = f"{type_full}.{method}"

    if any(marker in haystack for marker in INTEROP_MARKERS):
        return "drop", "Rhino/WCF/Win32 interop has no iOS equivalent", "interop"
    if assembly.startswith("Localization") or namespace.startswith("Localization"):
        return "drop", "locale resources are replaced by the app's own copy", "resource"
    if any(word in method for word in ("Legacy", "Obsolete", "Deprecated")):
        return "drop", "explicitly legacy member", "legacy"
    if any(word in type_full for word in ("Legacy", "Obsolete", "Deprecated")):
        return "drop", "legacy type retained only for old documents", "legacy-type"

    # Method-level intent beats the assembly default.
    if any(word in method for word in GEOMETRY_WORDS):
        return "port-with-new-geometry", "operates on Rhino geometry", "method-geometry"
    if any(word in method for word in DATA_WORDS):
        return "port-as-is", "pure data/formatting behaviour", "method-data"

    if assembly in GEOMETRY_ASSEMBLIES:
        if any(word in type_full for word in DROP_WORDS):
            return "drop", "desktop presentation helper", "type-desktop"
        return "port-with-new-geometry", "engine assembly, geometry by default", "assembly-geometry"
    if assembly in DATA_ASSEMBLIES:
        return "port-as-is", "model/settings assembly, data by default", "assembly-data"
    if assembly in DROP_ASSEMBLIES:
        if any(word in type_full for word in GEOMETRY_WORDS):
            return "port-with-new-geometry", "geometry type hosted by the desktop shell", "shell-geometry"
        return "drop", "desktop shell, replaced by the iPad app", "assembly-shell"

    # Anything else first-party still has to be sorted; keep the default visible.
    return "port-as-is", "unmatched assembly default", "default"


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=os.path.join(root, "04-index", "symbols.sqlite"))
    parser.add_argument("--out", default=os.path.join(root, "08-reports", "triage-ledger.csv"))
    parser.add_argument("--summary", default=os.path.join(root, "08-reports", "triage-summary.md"))
    args = parser.parse_args()

    if not os.path.exists(args.db):
        print(f"missing symbol ledger: {args.db}", file=sys.stderr)
        return 2

    con = sqlite3.connect(args.db)
    rows = con.execute(
        """
        select a.assembly, t.namespace, t.name, m.name, m.signature
        from methods m
        join types t on t.id = m.type_id
        join assemblies a on a.id = t.asm_id
        where a.managed = 1
        """
    ).fetchall()

    selected = []
    for assembly, namespace, type_name, method, signature in rows:
        if not any(assembly.startswith(prefix) for prefix in FIRST_PARTY):
            continue
        selected.append((assembly, namespace or "", type_name or "", method or "", signature or ""))

    ledger = []
    for assembly, namespace, type_name, method, signature in selected:
        cls, reason, rule = classify(assembly, namespace, type_name, method)
        ledger.append(
            {
                "assembly": assembly,
                "type": f"{namespace}.{type_name}" if namespace else type_name,
                "method": method,
                "signature": signature,
                "class": cls,
                "rule": rule,
                "reason": reason,
            }
        )
    ledger.sort(key=lambda r: (r["assembly"], r["type"], r["method"]))

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["assembly", "type", "method", "signature", "class", "rule", "reason"])
        writer.writeheader()
        writer.writerows(ledger)

    per_class = collections.Counter(r["class"] for r in ledger)
    per_rule = collections.Counter(r["rule"] for r in ledger)
    per_assembly = collections.Counter(r["assembly"] for r in ledger)

    lines = [
        "# Method triage ledger",
        "",
        f"Every first-party method in `04-index/symbols.sqlite` is classified exactly once.",
        f"Generated by `Tools/triage.py`; the CSV beside this file is the ledger.",
        "",
        f"**Total methods:** {len(ledger):,}",
        "",
        "| Class | Methods | Share |",
        "|---|---:|---:|",
    ]
    for cls in ("port-as-is", "port-with-new-geometry", "drop"):
        count = per_class.get(cls, 0)
        share = (100.0 * count / len(ledger)) if ledger else 0.0
        lines.append(f"| `{cls}` | {count:,} | {share:.1f} % |")
    lines += ["", "| Rule | Methods |", "|---|---:|"]
    for rule, count in per_rule.most_common():
        lines.append(f"| `{rule}` | {count:,} |")
    lines += ["", "| Assembly | Methods |", "|---|---:|"]
    for assembly, count in per_assembly.most_common():
        lines.append(f"| `{assembly}` | {count:,} |")
    with open(args.summary, "w", encoding="utf-8", newline="") as fh:
        fh.write("\n".join(lines) + "\n")

    print(f"ledger_rows {len(ledger)}")
    for cls in ("port-as-is", "port-with-new-geometry", "drop"):
        print(f"{cls} {per_class.get(cls, 0)}")
    print("unmatched_default", per_rule.get("default", 0))
    print(f"wrote {args.out}")
    print(f"wrote {args.summary}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
