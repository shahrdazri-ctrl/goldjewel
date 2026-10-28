#!/usr/bin/env python3
"""Golden vectors and IL provenance for the recovered head-shape slice.

This is a second, independent implementation of the formulas ported to Swift
(`CSHeadShape.HeadShape`, `GetDrop`, `ProngInterpCurve`). It is written from the
decompiled source and the IL corpus, not from the Swift code, so comparing the
two catches transcription errors rather than confirming them.

  python Tools/head_geometry_vectors.py           write vectors + test fixture
  python Tools/head_geometry_vectors.py --check   recompute and compare

Every literal used by the slice is listed in the package resource
`head-geometry-provenance.json`; both modes verify each (method, offset, value)
against `05-evidence/corpus/v1/head-builder.il.json`.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CORPUS = os.path.join(ROOT, "05-evidence", "corpus", "v1", "head-builder.il.json")
PROVENANCE = os.path.join(
    ROOT, "07-ios-handoff", "JewelryKit", "Sources", "JewelryKit", "Resources",
    "head-geometry-provenance.json",
)
VECTORS = os.path.join(ROOT, "05-evidence", "vectors", "head-geometry.json")
FIXTURE = os.path.join(
    ROOT, "07-ios-handoff", "JewelryKit", "Tests", "JewelryKitTests", "Fixtures",
    "head-geometry.json",
)

PARAMETERS = {
    "gemXSizeMM": 6.5,
    "gemYSizeMM": 6.5,
    "headHeightMM": -2.4,
    "baseOffsetMM": 0.0,
    "prongHeightMM": 1.6,
    "angleXDegrees": 12.0,
    "angleYDegrees": 10.0,
    "topAngleDegrees": 2.0,
    "baseAngleDegrees": 4.0,
    "baseAnglePosition": 0.5,
    "bezelParameter": 0.5,
    "prongs": [
        {"angleDegrees": 45.0, "topX": 1.0, "topY": 0.75, "topNudge": 0.0,
         "baseX": 1.1, "baseY": 0.8, "baseNudge": 0.0},
        {"angleDegrees": 135.0, "topX": 1.0, "topY": 0.75, "topNudge": 0.0,
         "baseX": 1.1, "baseY": 0.8, "baseNudge": 0.0},
        {"angleDegrees": 225.0, "topX": 1.0, "topY": 0.75, "topNudge": 0.0,
         "baseX": 1.1, "baseY": 0.8, "baseNudge": 0.0},
        {"angleDegrees": 315.0, "topX": 1.0, "topY": 0.75, "topNudge": 0.0,
         "baseX": 1.1, "baseY": 0.8, "baseNudge": 0.0},
    ],
}

RING_SAMPLES = 128
RAIL_SAMPLES = 32


def radians(degrees: float) -> float:
    return degrees * math.pi / 180.0


class Spline:
    """Natural cubic spline with chord-length knots."""

    def __init__(self, points):
        self.points = points
        if len(points) < 3:
            self.knots = [0.0, 1.0]
            self.second = [0.0] * len(points)
            return
        knots = [0.0]
        for index in range(1, len(points)):
            knots.append(knots[-1] + max(dist(points[index], points[index - 1]), 1e-9))
        total = knots[-1]
        self.knots = [knot / total for knot in knots]

        count = len(points)
        lower = [0.0] * count
        diagonal = [1.0] * count
        upper = [0.0] * count
        rhs = [[0.0, 0.0, 0.0] for _ in range(count)]
        for index in range(1, count - 1):
            h0 = self.knots[index] - self.knots[index - 1]
            h1 = self.knots[index + 1] - self.knots[index]
            lower[index] = h0
            diagonal[index] = 2 * (h0 + h1)
            upper[index] = h1
            slope0 = [(points[index][k] - points[index - 1][k]) / h0 for k in range(3)]
            slope1 = [(points[index + 1][k] - points[index][k]) / h1 for k in range(3)]
            rhs[index] = [(slope1[k] - slope0[k]) * 6 for k in range(3)]

        def solve(values):
            c = [0.0] * count
            d = [0.0] * count
            result = [0.0] * count
            c[1] = upper[1] / diagonal[1]
            d[1] = values[1] / diagonal[1]
            for index in range(2, count - 1):
                denominator = diagonal[index] - lower[index] * c[index - 1]
                c[index] = upper[index] / denominator
                d[index] = (values[index] - lower[index] * d[index - 1]) / denominator
            result[count - 2] = d[count - 2]
            for index in range(count - 3, 0, -1):
                result[index] = d[index] - c[index] * result[index + 1]
            return result

        mx = solve([row[0] for row in rhs])
        my = solve([row[1] for row in rhs])
        mz = solve([row[2] for row in rhs])
        self.second = [[mx[i], my[i], mz[i]] for i in range(count)]

    def point(self, parameter: float):
        points = self.points
        if len(points) < 2:
            return points[0] if points else (0.0, 0.0, 0.0)
        if len(points) == 2:
            t = min(max(parameter, 0.0), 1.0)
            return lerp(points[0], points[1], t)
        u = min(max(parameter, 0.0), 1.0)
        segment = 0
        while segment < len(points) - 2 and u > self.knots[segment + 1]:
            segment += 1
        t0 = self.knots[segment]
        t1 = self.knots[segment + 1]
        h = t1 - t0
        a = (t1 - u) / h
        b = (u - t0) / h
        base = lerp(points[segment], points[segment + 1], b)
        ma = self.second[segment]
        mb = self.second[segment + 1]
        correction = [
            (ma[k] * (a ** 3 - a) + mb[k] * (b ** 3 - b)) * (h * h / 6) for k in range(3)
        ]
        return tuple(base[k] + correction[k] for k in range(3))

    def samples(self, count):
        return [list(self.point(i / (count - 1))) for i in range(count)]


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def lerp(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def interpolated_rail(points):
    points = [list(p) for p in points]
    index = 0
    while index < len(points) - 1:
        if dist(points[index], points[index + 1]) < 0.01:
            points.pop(index)
            index = max(index - 1, 0)
        else:
            index += 1
    if len(points) < 2:
        return []
    if len(points) == 2:
        points = [points[0], lerp(points[0], points[1], 0.1), points[1]]
    return Spline([tuple(p) for p in points]).samples(RAIL_SAMPLES)


def build(parameters):
    gem_x = parameters["gemXSizeMM"]
    gem_y = parameters["gemYSizeMM"]
    prong_height = max(parameters["prongHeightMM"], 0.01)
    drop = parameters["headHeightMM"] + parameters["baseOffsetMM"]

    offset_x = drop * math.tan(radians(parameters["angleXDegrees"]))
    offset_y = drop * math.tan(radians(parameters["angleYDegrees"]))
    base_x_size = gem_x + offset_x * 2
    base_y_size = gem_y + offset_y * 2
    scale_base = [base_x_size / gem_x, base_y_size / gem_y, 1.0]

    position = min(max(parameters["baseAnglePosition"], 0.0), 1.0)
    extra_x = -drop * position * math.tan(radians(parameters["angleXDegrees"] + parameters["baseAngleDegrees"]))
    extra_y = -drop * position * math.tan(radians(parameters["angleYDegrees"] + parameters["baseAngleDegrees"]))
    scale_middle = [
        (base_x_size + extra_x * 2) / gem_x,
        (base_y_size + extra_y * 2) / gem_y,
        1.0,
    ]
    middle_z = drop * (1 - position)

    top_x_offset = prong_height * math.tan(radians(parameters["angleXDegrees"] + parameters["topAngleDegrees"]))
    top_y_offset = prong_height * math.tan(radians(parameters["angleYDegrees"] + parameters["topAngleDegrees"]))
    scale_top = [
        (gem_x + top_x_offset * 2) / gem_x,
        (gem_y + top_y_offset * 2) / gem_y,
        1.0,
    ]

    def ring(scale, z):
        points = []
        for index in range(RING_SAMPLES):
            angle = 2 * math.pi * index / RING_SAMPLES
            points.append([
                (gem_x / 2) * math.cos(angle) * scale[0],
                (gem_y / 2) * math.sin(angle) * scale[1],
                z,
            ])
        return points

    def ellipse_point(polar):
        cosine = math.cos(polar)
        sine = math.sin(polar)
        denominator = math.sqrt((cosine / (gem_x / 2)) ** 2 + (sine / (gem_y / 2)) ** 2)
        radius = 1 / denominator
        return (radius * cosine, radius * sine, 0.0)

    def rail(polar):
        point = ellipse_point(polar)
        return interpolated_rail([
            [point[0] * scale_top[0], point[1] * scale_top[1], prong_height],
            [point[0], point[1], 0.0],
            [point[0] * scale_middle[0], point[1] * scale_middle[1], middle_z],
            [point[0] * scale_base[0], point[1] * scale_base[1], drop],
        ])

    return {
        "dropMM": drop,
        "scaleBase": scale_base,
        "scaleMiddle": scale_middle,
        "scaleTop": scale_top,
        "girdle": ring([1.0, 1.0, 1.0], 0.0),
        "rails": [rail(radians(prong["angleDegrees"])) for prong in parameters["prongs"]],
        "bezelRail": rail(parameters["bezelParameter"] * 2 * math.pi),
        "mesh": {
            "ringSamples": RING_SAMPLES,
            "railSamples": RAIL_SAMPLES,
            "basketVertices": RING_SAMPLES * 4 + 2,
            "basketTriangles": (4 - 1) * RING_SAMPLES * 2 + 2 * RING_SAMPLES,
            "prongVertices": RAIL_SAMPLES * 36 + 2,
            "prongTriangles": (RAIL_SAMPLES - 1) * 36 * 2 + 2 * 36,
        },
    }


def verify_provenance():
    corpus = json.load(open(CORPUS, encoding="utf-8"))
    methods = {}
    for type_record in corpus["types"]:
        for method in type_record["methods"]:
            methods[f"{type_record['full_name']}.{method['name']}"] = method
    entries = json.load(open(PROVENANCE, encoding="utf-8"))["constants"]

    failures = []
    for entry in entries:
        method = methods.get(entry["method"])
        if method is None:
            failures.append(f"unknown method {entry['method']}")
            continue
        body = method.get("body") or {}
        matches = [c for c in body.get("constants", []) if c["offset"] == entry["il_offset"]]
        if not matches:
            failures.append(f"{entry['name']}: no constant at {entry['method']} IL_{entry['il_offset']}")
            continue
        if float(matches[0]["value"]) != float(entry["value"]):
            failures.append(
                f"{entry['name']}: IL_{entry['il_offset']} is {matches[0]['value']}, "
                f"provenance says {entry['value']}"
            )
    if len(entries) < 5:
        failures.append("provenance table is implausibly small")
    return entries, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    if not os.path.exists(CORPUS):
        print("missing corpus v1", file=sys.stderr)
        return 2

    payload = {
        "schema": "goldjewel.head-geometry.golden/1",
        "comment": (
            "Recomputed from the decompiled head-shape formulas and corpus v1; "
            "compared against the Swift port in CI."
        ),
        "parameters": PARAMETERS,
        "expected": build(PARAMETERS),
    }
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"

    entries, failures = verify_provenance()
    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1

    if args.check:
        for path in (VECTORS, FIXTURE):
            if not os.path.exists(path):
                failures.append(f"missing {os.path.relpath(path, ROOT)}")
                continue
            if open(path, encoding="utf-8").read() != text:
                failures.append(f"{os.path.relpath(path, ROOT)} is stale; regenerate")
        if failures:
            for failure in failures:
                print(f"FAIL {failure}", file=sys.stderr)
            return 1
        print(f"golden vectors match; {len(entries)} constants traced to IL")
        return 0

    for path in (VECTORS, FIXTURE):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
        print(f"wrote {os.path.relpath(path, ROOT)}")
    print(f"{len(entries)} constants traced to IL")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
