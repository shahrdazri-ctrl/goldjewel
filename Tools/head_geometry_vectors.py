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
CORPORA = [
    os.path.join(ROOT, "05-evidence", "corpus", "v1", "head-builder.il.json"),
    os.path.join(ROOT, "05-evidence", "corpus", "v2", "csblockutil.il.json"),
    os.path.join(ROOT, "05-evidence", "corpus", "v2", "csblocks-families.il.json"),
]
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
DOME_SAMPLES = 8
DOME = {
    "height": 0.7,
    "settingDistance": 0.0,
    "settingAngle": 0.0,
    "planar": False,
    "samples": DOME_SAMPLES,
}

BEZEL = {
    "enabled": True,
    "seatHeight": 0.55,
    "seatLength": 0.45,
    "seatAngle": 10.0,
    "samples": 128,
}

HALO = {
    "enabled": True,
    "gemDiameter": 1.25,
    "spacing": 0.18,
    "offsetRailX": 0.75,
    "offsetRailZ": 0.05,
    "even": False,
    "fixPosition": 0.0,
    "samples": 256,
    "bandSamples": 128,
    "proxyFacets": 6,
}


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


def sub(a, b):
    return [a[i] - b[i] for i in range(3)]


def dot(a, b):
    return sum(a[i] * b[i] for i in range(3))


def cross(a, b):
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def norm(a):
    length = math.sqrt(dot(a, a)) or 1.0
    return [value / length for value in a]


def dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def lerp(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


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


def section_profile():
    half, radius = 0.5, 0.5
    centers = [
        [half - radius, half - radius], [-half + radius, half - radius],
        [-half + radius, -half + radius], [half - radius, -half + radius],
    ]
    starts = [0.0, math.pi / 2, math.pi, 3 * math.pi / 2]
    points = []
    for corner in range(4):
        for step in range(9):
            angle = starts[corner] + (math.pi / 2) * step / 8
            points.append((centers[corner][0] + radius * math.cos(angle),
                           centers[corner][1] + radius * math.sin(angle)))
    return points


def section_ring(rail, prong, index):
    """The prong section, mirroring ProngSweeper.section."""
    tangent = norm(sub(rail[1], rail[0]))
    angle = math.acos(max(min(dot([-tangent[0], -tangent[1], -tangent[2]], [0, 0, 1]), 1), -1))
    cosine = math.cos(angle)
    secant = 1 / cosine if cosine > 1e-6 else 1
    top_scale = [prong["topX"], prong["topY"] * secant]
    base_scale = [prong["baseX"], prong["baseY"]]
    top_offset = -prong["topY"] * prong["topNudge"]
    base_offset = -prong["baseY"] * prong["baseNudge"]
    origin = rail[index]
    previous = rail[max(index - 1, 0)]
    nxt = rail[min(index + 1, len(rail) - 1)]
    rail_tangent = norm(sub(nxt, previous))
    radial = norm([origin[0], origin[1], 0.0])
    side = norm(cross(rail_tangent, radial))
    normal = norm(cross(side, rail_tangent))
    t = index / (len(rail) - 1)
    scale = [top_scale[0] + (base_scale[0] - top_scale[0]) * t,
             top_scale[1] + (base_scale[1] - top_scale[1]) * t]
    offset = top_offset + (base_offset - top_offset) * t
    return [[origin[i] + side[i] * (u * scale[0]) + normal[i] * (v * scale[1] + offset)
             for i in range(3)] for u, v in section_profile()]


def bezier(controls, t):
    """De Casteljau evaluation, matching the Swift sampler."""
    points = [list(p) for p in controls]
    for level in range(len(points) - 1, 0, -1):
        for index in range(level):
            points[index] = lerp(points[index], points[index + 1], t)
    return points[0]


def rotate(value, axis, angle):
    unit = norm(axis)
    cosine = math.cos(angle)
    sine = math.sin(angle)
    return [value[i] * cosine + cross(unit, value)[i] * sine
            + unit[i] * dot(unit, value) * (1 - cosine) for i in range(3)]


def blend_controls(start, end, outward, axis):
    """`CSUtilCurves.BlendCurve` with the default unit blend amounts."""
    length = dist(start, end)
    return [
        start,
        [start[i] + outward[i] * length * 0.2 for i in range(3)],
        [start[i] + outward[i] * length * 0.4 for i in range(3)],
        [end[i] - axis[i] * length * 0.4 for i in range(3)],
        [end[i] - axis[i] * length * 0.2 for i in range(3)],
        end,
    ]


def build_dome(rail, prong):
    base = section_ring(rail, prong, 0)
    center = [sum(p[i] for p in base) / len(base) for i in range(3)]
    tangent = norm(sub(rail[1], rail[0]))
    axis = [-tangent[0], -tangent[1], -tangent[2]]
    tangential = cross(axis, [0, 0, 1])
    if sum(abs(v) for v in tangential) < 1e-9:
        tangential = [1.0, 0.0, 0.0]
    else:
        tangential = norm(tangential)
    height = DOME["height"]
    apex = [center[i] + axis[i] * height + tangential[i] * DOME["settingDistance"]
            for i in range(3)]
    if DOME["settingAngle"] != 0:
        rotated = rotate(sub(apex, center), tangential, radians(DOME["settingAngle"]))
        apex = [center[i] + rotated[i] for i in range(3)]

    def meridian(point):
        outward = norm(sub(point, center))
        if sum(abs(v) for v in outward) < 1e-9:
            outward = axis
        return blend_controls(point, apex, outward, axis)

    controls = meridian(base[0])
    mid_first = bezier(controls, 0.5)
    rings = [base]
    for step in range(1, DOME_SAMPLES):
        u = step / DOME_SAMPLES
        rings.append([bezier(meridian(point), u) for point in base])
    return {
        "parameters": DOME,
        "apex": apex,
        "baseCenter": center,
        "baseFirst": base[0],
        "midFirst": mid_first,
        "mesh": {
            "vertices": DOME_SAMPLES * len(base) + 1,
            "triangles": (DOME_SAMPLES - 1) * len(base) * 2 + len(base),
        },
    }


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

    side_x = rail(0.0)
    side_y = rail(math.pi / 2)
    prong_rails = [rail(radians(prong["angleDegrees"])) for prong in parameters["prongs"]]
    girdle = ring([1.0, 1.0, 1.0], 0.0)
    return {
        "dropMM": drop,
        "scaleBase": scale_base,
        "scaleMiddle": scale_middle,
        "scaleTop": scale_top,
        "girdle": girdle,
        "bezel": build_bezel(girdle),
        "halo": build_halo(parameters),
        "rails": prong_rails,
        "bezelRail": rail(parameters["bezelParameter"] * 2 * math.pi),
        "dome": build_dome(prong_rails[0], parameters["prongs"][0]),
        "sideX": side_x,
        "sideY": side_y,
        "gallery": build_gallery(drop, side_x, side_y),
        "mesh": {
            "ringSamples": RING_SAMPLES,
            "railSamples": RAIL_SAMPLES,
            "basketVertices": RING_SAMPLES * 4,
            "basketTriangles": (4 - 1) * RING_SAMPLES * 2,
            "prongVertices": RAIL_SAMPLES * 36 + 2,
            "prongTriangles": (RAIL_SAMPLES - 1) * 36 * 2 + 2 * 36,
            "galleryVertices": GALLERY["samples"] * 4,
            "galleryTriangles": GALLERY["samples"] * 8,
        },
    }


GALLERY = {
    "position": 0.85,
    "width": 0.55,
    "height": 0.35,
    "offset": 0.15,
    "samples": 128,
}


def build_gallery(drop, side_x, side_y):
    """`GalleryRail_V1` placement with the profile replaced by a band.

    The IL fixes the height (`end.z * (1 - RailPos)`), the ray intersections,
    and the two offsets. The horizontal intersection here interpolates the
    sampled spline; the ellipse offset adds to both radii. Both are recorded
    as inferred in the dossier.
    """
    position = GALLERY["position"]
    width = GALLERY["width"]
    height = GALLERY["height"]
    offset = GALLERY["offset"]
    samples = GALLERY["samples"]
    z = side_x[-1][2] * (1.0 - position)

    def intersect(curve, axis):
        for index in range(len(curve) - 1):
            a = curve[index]
            b = curve[index + 1]
            span = b[2] - a[2]
            if abs(span) < 1e-12:
                continue
            t = (z - a[2]) / span
            if 0.0 <= t <= 1.0:
                return a[axis] + (b[axis] - a[axis]) * t
        raise ValueError("rail outside head")

    gem_x_max = PARAMETERS["gemXSizeMM"] / 2.0
    gem_y_max = PARAMETERS["gemYSizeMM"] / 2.0
    x = intersect(side_x, 0)
    y = intersect(side_y, 1)
    scale_x = x / gem_x_max
    scale_y = y / gem_y_max
    outer_x = gem_x_max * scale_x + offset
    outer_y = gem_y_max * scale_y + offset
    inner_x = outer_x - width
    inner_y = outer_y - width
    outer = []
    inner = []
    for index in range(samples):
        angle = 2.0 * math.pi * index / samples
        outer.append([outer_x * math.cos(angle), outer_y * math.sin(angle), z])
        inner.append([inner_x * math.cos(angle), inner_y * math.sin(angle), z])
    return {
        "parameters": {
            "position": position,
            "width": width,
            "height": height,
            "offset": offset,
            "samples": samples,
        },
        "z": z,
        "scale": [scale_x, scale_y],
        "outerFirst": outer[0],
        "innerFirst": inner[0],
        "mesh": {
            "vertices": samples * 4,
            "triangles": samples * 8,
        },
    }


def build_bezel(girdle):
    """`BezelProfile` seat construction applied to the recovered girdle."""
    height = BEZEL["seatHeight"]
    length = BEZEL["seatLength"]
    angle = radians(BEZEL["seatAngle"] + 180.0)
    samples = BEZEL["samples"]
    points = []
    for index in range(samples):
        position = girdle[index % len(girdle)]
        radial = norm([position[0], position[1], 0.0])
        top = [position[0], position[1], 0.0]
        lip = [
            top[0] + radial[0] * length * math.cos(angle),
            top[1] + radial[1] * length * math.cos(angle),
            top[2] - (height + length * math.sin(angle)),
        ]
        wall_bottom = [
            top[0] + radial[0] * length,
            top[1] + radial[1] * length,
            top[2] - height,
        ]
        wall_top = [
            top[0] + radial[0] * length,
            top[1] + radial[1] * length,
            top[2],
        ]
        points.append((top, lip, wall_bottom, wall_top))
    return {
        "parameters": BEZEL,
        "topZ": points[0][0][2],
        "lipZ": points[0][1][2],
        "seatTopFirst": points[0][0],
        "seatLipFirst": points[0][1],
        "wallBottomFirst": points[0][2],
        "mesh": {
            "vertices": samples * 4,
            "triangles": samples * 8,
        },
    }


def build_halo(parameters):
    """`CSClusterGemRound.PlaceGems` plus the modelled band and proxy stones."""
    count_samples = HALO["samples"]
    gem_diameter = HALO["gemDiameter"]
    spacing = HALO["spacing"]
    radius_x = parameters["gemXSizeMM"] / 2 + HALO["offsetRailX"]
    radius_y = parameters["gemYSizeMM"] / 2 + HALO["offsetRailX"]
    z = HALO["offsetRailZ"]
    curve = []
    for index in range(count_samples):
        angle = 2 * math.pi * index / count_samples
        curve.append([radius_x * math.cos(angle), radius_y * math.sin(angle), z])
    cumulative = [0.0]
    for index in range(1, count_samples + 1):
        a = curve[index - 1]
        b = curve[index % count_samples]
        cumulative.append(cumulative[-1] + dist(a, b))
    total = cumulative[-1]
    count = int(total / (gem_diameter + spacing))
    if HALO["even"] and count % 2 == 1:
        count -= 1
    count = max(count, 3)
    step = 1.0 / count
    phase = HALO["fixPosition"] % step
    parameters_on_curve = []
    for index in range(count):
        u = phase + index * step
        if u > 1:
            u -= 1
        parameters_on_curve.append(u)
    parameters_on_curve.sort()

    def point_at(u):
        target = min(max(u, 0.0), 1.0) * cumulative[-1]
        low = 0
        high = len(cumulative) - 1
        while low < high - 1:
            middle = (low + high) // 2
            if cumulative[middle] <= target:
                low = middle
            else:
                high = middle
        span = cumulative[high] - cumulative[low]
        t = (target - cumulative[low]) / span if span > 1e-12 else 0.0
        return lerp(curve[low], curve[high % len(curve)], t)

    centers = [point_at(u) for u in parameters_on_curve]
    band_samples = HALO["bandSamples"]
    facets = HALO["proxyFacets"]
    return {
        "parameters": HALO,
        "count": count,
        "centers": centers,
        "firstCenter": centers[0],
        "mesh": {
            "bandVertices": band_samples * 4,
            "bandTriangles": band_samples * 8,
            "gemVertices": count * (facets * 2 + 2),
            "gemTriangles": count * facets * 4,
            "vertices": band_samples * 4 + count * (facets * 2 + 2),
            "triangles": band_samples * 8 + count * facets * 4,
        },
    }


def first_difference(expected, actual, path=""):
    """Structural comparison with the same 1e-9 tolerance the Swift tests use.

    libm differs between Windows and Linux in the last bits, so exact float
    equality would make the gate depend on the runner's C library.
    """
    if isinstance(expected, dict) and isinstance(actual, dict):
        if set(expected) != set(actual):
            return f"{path or 'root'}: keys differ"
        for key in expected:
            found = first_difference(expected[key], actual[key], f"{path}.{key}" if path else key)
            if found:
                return found
        return None
    if isinstance(expected, list) and isinstance(actual, list):
        if len(expected) != len(actual):
            return f"{path}: length {len(actual)} != {len(expected)}"
        for index, (left, right) in enumerate(zip(expected, actual)):
            found = first_difference(left, right, f"{path}[{index}]")
            if found:
                return found
        return None
    if isinstance(expected, bool) or isinstance(actual, bool):
        return None if expected == actual else f"{path}: {actual!r} != {expected!r}"
    if isinstance(expected, (int, float)) and isinstance(actual, (int, float)):
        if abs(float(expected) - float(actual)) > 1e-9:
            return f"{path}: {actual!r} != {expected!r}"
        return None
    return None if expected == actual else f"{path}: {actual!r} != {expected!r}"


def verify_provenance():
    methods = {}
    for path in CORPORA:
        corpus = json.load(open(path, encoding="utf-8"))
        for type_record in corpus["types"]:
            for method in type_record["methods"]:
                key = f"{type_record['full_name']}.{method['name']}"
                methods.setdefault(key, []).append(method)
    payload = json.load(open(PROVENANCE, encoding="utf-8"))
    entries = payload["constants"]
    claims = payload.get("claims", [])

    failures = []
    for entry in entries:
        candidates = methods.get(entry["method"], [])
        if not candidates:
            failures.append(f"unknown method {entry['method']}")
            continue
        matches = [
            constant
            for method in candidates
            for constant in (method.get("body") or {}).get("constants", [])
            if constant["offset"] == entry["il_offset"]
        ]
        if not matches:
            failures.append(f"{entry['name']}: no constant at {entry['method']} IL_{entry['il_offset']}")
            continue
        if not any(float(match["value"]) == float(entry["value"]) for match in matches):
            failures.append(
                f"{entry['name']}: IL_{entry['il_offset']} is "
                f"{[m['value'] for m in matches]}, provenance says {entry['value']}"
            )
        if entry.get("tier") != "recovered":
            failures.append(f"{entry['name']}: an IL literal must be graded recovered")

    tiers = {claim.get("tier") for claim in claims}
    for required in ("recovered", "reconstructed", "inferred"):
        if required not in tiers:
            failures.append(f"provenance has no {required} claim")
    for claim in claims:
        tier = claim.get("tier")
        name = claim.get("id", "<unnamed>")
        if tier == "recovered" and not (claim.get("method") and claim.get("il_offset") is not None):
            failures.append(f"{name}: recovered claim needs method and il_offset")
        if tier == "reconstructed" and not claim.get("documented_algorithm"):
            failures.append(f"{name}: reconstructed claim needs documented_algorithm")
        if tier == "inferred" and not claim.get("rationale"):
            failures.append(f"{name}: inferred claim needs rationale")
    if len(entries) < 5:
        failures.append("provenance table is implausibly small")
    return entries, failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    missing = [os.path.relpath(path, ROOT) for path in CORPORA if not os.path.exists(path)]
    if missing:
        print(f"missing corpus: {', '.join(missing)}", file=sys.stderr)
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
    text = json.dumps(payload, indent=2, sort_keys=True) + "\n"  # committed formatting


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
            # Compare data, not bytes: float formatting differs between the
            # Python that generated the file and the Python in CI, while the
            # values are identical. Swift decodes the same numbers either way.
            try:
                committed = json.load(open(path, encoding="utf-8"))
            except json.JSONDecodeError as error:
                failures.append(f"{os.path.relpath(path, ROOT)} is not JSON: {error}")
                continue
            difference = first_difference(payload, committed)
            if difference is not None:
                failures.append(f"{os.path.relpath(path, ROOT)} is stale: {difference}")
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
