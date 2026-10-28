#!/usr/bin/env python3
"""Validate closed-form ring-size formulas against vectors produced by the real assembly."""
import json
import math

VECTORS = r"D:\REA-LAB\05-evidence\vectors\ring-sizes.json"

COUNTS = {"Us": 65, "Uk": 66, "Eu": 39, "Jp": 37, "Fr": 160, "De": 38, "Ch": 160}


def round_even(value, digits):
    factor = 10.0 ** digits
    scaled = value * factor
    lower = math.floor(scaled)
    frac = scaled - lower
    if abs(abs(frac) - 0.5) < 1e-7:
        nearest = lower if lower % 2 == 0 else lower + 1
    else:
        nearest = round(scaled)
    return nearest / factor


def fraction(rem):
    return {1: " 1/4", 2: " 1/2", 3: " 3/4"}.get(rem, "")


def raw_diameter(region, i):
    if region == "Us":
        return ((i / 4.0 * 0.102 + 1.43) / math.pi) * 25.4
    if region == "Uk":
        return (i / 2.0 * 1.25 + 37.55) / math.pi
    if region == "Eu":
        return (i + 41) / math.pi
    if region == "Jp":
        return (i + 38.0) / 3.0
    if region in ("Fr", "Ch"):
        return (i / 4.0 + 41.0) / math.pi
    if region == "De":
        return (i + 53) / 4.0
    raise KeyError(region)


def name(region, i):
    if region == "Us":
        return f"{i // 4}" + fraction(i % 4)
    if region == "Uk":
        if i >= 52:
            value = f"Z+{(i - 50) // 2}"
        else:
            value = chr(65 + i // 2)
        if i % 2 == 1:
            value += " 1/2"
        return value
    if region == "Eu":
        return str(i + 41)
    if region == "Jp":
        return str(i)
    if region == "Fr":
        return f"{i // 4 + 41}" + fraction(i % 4)
    if region == "De":
        n = i + 53
        return f"{n // 4}" + fraction(n % 4)
    if region == "Ch":
        return f"{i // 4 + 1}" + fraction(i % 4)
    raise KeyError(region)


def main():
    data = json.load(open(VECTORS, encoding="utf-8"))
    tables = {r["region"]: r for r in data["regions"]}
    mismatches = []
    checked = 0
    for region, count in COUNTS.items():
        table = tables[region]
        assert table["count"] == count, (region, table["count"], count)
        for i in range(count):
            size = table["sizes"][i]
            checked += 1
            expected_name = name(region, i)
            expected_d = round_even(raw_diameter(region, i), 2)
            expected_r = round_even(raw_diameter(region, i) / 2.0, 2)
            if size["name"] != expected_name or abs(size["diameterMM"] - expected_d) > 1e-9 or abs(size["radiusMM"] - expected_r) > 1e-9:
                mismatches.append((region, i, size, expected_name, expected_d, expected_r))
                if len(mismatches) > 20:
                    break
    print(f"checked={checked} mismatches={len(mismatches)}")
    for m in mismatches[:10]:
        print(m)


if __name__ == "__main__":
    main()
