#!/usr/bin/env python3
"""Extract XAML structure and binding facts for the MatrixGold UI dossier."""
import csv
import json
import os
import re
import xml.etree.ElementTree as ET

LAB = r"D:\REA-LAB"
ROOT = os.path.join(LAB, "03-decompiled", "xaml")
OUT = os.path.join(LAB, "04-index")

X = "{http://schemas.microsoft.com/winfx/2006/xaml}"
BINDING_RE = re.compile(r"\{Binding\s*([^}]*)\}")


def binding_path(value):
    m = BINDING_RE.search(value or "")
    if not m:
        return None
    args = m.group(1).strip()
    if not args:
        return ""
    if "Path=" in args:
        p = re.search(r"Path=([^,}]+)", args)
        return p.group(1).strip() if p else ""
    if "RelativeSource" in args or "ElementName" in args:
        return ""
    return args.split(",")[0].strip()


def main():
    rows = []
    classes = {}
    element_counts = {}
    binding_counts = {}
    command_counts = {}
    files = 0
    parse_fail = []

    for dirpath, _, filenames in os.walk(ROOT):
        for fn in filenames:
            if not fn.endswith(".xaml"):
                continue
            files += 1
            path = os.path.join(dirpath, fn)
            rel = os.path.relpath(path, ROOT)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
                text = re.sub(r'encoding="[^"]+"', 'encoding="utf-8"', text, count=1)
                if text.startswith("<?xml"):
                    with open(path, "w", encoding="utf-8") as fh:
                        fh.write(text)
                root = ET.fromstring(text)
            except Exception as exc:
                parse_fail.append((rel, str(exc)))
                continue
            cls = root.attrib.get(f"{X}Class", "")
            classes[rel] = cls
            for el in root.iter():
                tag = el.tag.split("}")[-1]
                element_counts[tag] = element_counts.get(tag, 0) + 1
                for attr, val in el.attrib.items():
                    if not isinstance(val, str):
                        continue
                    bp = binding_path(val)
                    if bp is not None:
                        binding_counts[bp] = binding_counts.get(bp, 0) + 1
                        rows.append({
                            "file": rel, "xclass": cls, "element": tag,
                            "attribute": attr.split("}")[-1], "value": val,
                            "binding_path": bp, "command": "",
                        })
                    if attr.endswith("Command") or "Command" in attr:
                        cmd = val
                        if cmd.startswith("{Binding") or cmd.startswith("{x:Static") or cmd.startswith("{StaticResource"):
                            command_counts[cmd] = command_counts.get(cmd, 0) + 1
                            rows.append({
                                "file": rel, "xclass": cls, "element": tag,
                                "attribute": attr.split("}")[-1], "value": val,
                                "binding_path": "", "command": cmd,
                            })

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "xaml-bindings.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["file", "xclass", "element", "attribute", "value", "binding_path", "command"])
        w.writeheader()
        w.writerows(rows)

    summary = {
        "xaml_files": files,
        "parse_failures": parse_fail,
        "classes": classes,
        "top_elements": sorted(element_counts.items(), key=lambda kv: -kv[1])[:60],
        "top_binding_paths": sorted(binding_counts.items(), key=lambda kv: -kv[1])[:120],
        "top_commands": sorted(command_counts.items(), key=lambda kv: -kv[1])[:80],
        "binding_rows": len(rows),
    }
    with open(os.path.join(OUT, "xaml-summary.json"), "w", encoding="utf-8") as fh:
        json.dump(summary, fh, indent=2)

    print(f"files={files} rows={len(rows)} bindings={len(binding_counts)} commands={len(command_counts)} parse_failures={len(parse_fail)}")
    print("top elements:", summary["top_elements"][:15])
    print("top bindings:", summary["top_binding_paths"][:15])


if __name__ == "__main__":
    main()
