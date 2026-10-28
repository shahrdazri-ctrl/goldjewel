# M4 — gallery rail and the project shell

Two outcomes: one new recovered geometry family rendered in the app, and the
single preview replaced by a project-based iPhone/iPadOS shell with the 88 v1
operations exposed as entry points.

## Family order and what shipped

The capability matrix puts **Builders** first (22 of 88 v1 operations), so the
head families remain the critical path. Within the head builder the planned
order was prong domes, gallery, bezel, halo/cluster. Only the gallery rail
cleared the evidence bar.

| Family | Decision | Reason |
|---|---|---|
| Prong domes | **Stopped** | `CSHeadBezel.ProngDomeCurve` builds its surface with `CSUtilCurves.BlendCurve`, `Curve.Rebuild` and six caller-supplied blend parameters. Neither the helper's IL nor its blend solve is in corpus v1. A dome built from an invented blend would look plausible and be wrong. |
| Gallery rail | **Shipped** | `CSHeadGalleryRails.GalleryRail_V1` gives the height rule, the side-rail intersections, the gem scaling and both offsets as explicit IL. |
| Bezel | **Stopped** | `BezelProfile` blends a trimmed prong rail into a seat polyline and intersects `BrepSurface`; `RevolveBezel` then revolves that outline. The profile depends on the authored prong rail and Rhino blend/intersection behaviour that corpus v1 does not contain. |
| Halo / cluster | **Stopped** | Halo placement lives in `CSBlocks.GemClusters.CSHaloBuilder`, a different family that consumes gem-instance seats and positions not captured in corpus v1. Nothing was invented to fill the gap. |

Stopping a family is a result, not an omission: the report names the exact
missing evidence so the next capture pass can target it.

## What now renders

The app still shows the 6.5 mm round solitaire: basket plus 4–8 prongs. The
gallery rail is on by default and is user-toggleable.

| Part | Triangles (4 prongs, rail on) |
|---|---:|
| Basket (four recovered outlines) | 768 |
| Four prongs (32 rails × 36 profile points, capped) | 9,216 |
| Gallery rail (128 samples, rectangular band) | 1,024 |
| **Total** | **11,008** |

The rail is a closed band between the two recovered offset outlines. Its
height is `sideX.end.z * (1 − RailPos)`; at the default `RailPos = 0.85` for a
6.5 mm gem it sits at `z = −0.36 mm`, outer radius `3.3507 mm`, inner radius
`2.8007 mm`.

The offline renderer (`09-logs/render_check.py`) draws the same golden data
and was used to inspect the band in three views before the app build.

## What the numbers were checked against

* **Golden vectors** — `05-evidence/vectors/head-geometry.json` now contains
  both side rails (128 points each) and the gallery placement: height, scale,
  first outer/inner points and mesh counts. It is recomputed by
  `Tools/head_geometry_vectors.py` from the decompiled formulas, not from the
  Swift.
* **IL provenance** — the package resource now lists **12** literals. The three
  new ones are `1.0` at `GalleryRail_V1` IL_74 (height fraction), `100.0` at
  IL_178 (ray length) and `0.01` at IL_212 (intersection tolerance). The check
  resolves each `(method, offset, value)` in
  `05-evidence/corpus/v1/head-builder.il.json`.
* **Swift tests** — `testGalleryRailMatchesGoldenVectors` compares the rail
  height, both outlines and the band counts. The existing cage test now also
  compares `sideX`/`sideY`. **6** head-geometry tests, **29** tests in total.
* **CI** — all three gates on `4d11b6b`:

| Gate | Run | Result |
|---|---|---|
| linux (validator, M2, geometry/provenance, operation catalog) | 40639481304 | success |
| macos (package build + 29 tests) | 40639731199 | success |
| ios-simulator (iPhone + iPad app) | 40639481336 | success |

The macOS log records 29 tests with 0 failures, including 6
`HeadGeometryTests` cases; the Linux log records `12 constants traced to IL`
and `operation catalog matches the capability matrix`. The simulator gate
uploads the `.app`; it does **not** launch it. A bounded `simctl`
boot/install/launch/screenshot attempt stalled inside CoreSimulator on the
hosted runner and was removed rather than reported as a runtime pass.

## The app shell

`GoldJewel` is now a small document app rather than one preview screen:

* **Project model** — `JewelryProject` stores the gem, prong count, every head
  angle, metal, ring region/size and rail settings. Projects are written as
  pretty-printed JSON to `Application Support/GoldJewel/projects.json` and
  autosaved on edit.
* **Project list** — `NavigationSplitView` list with create, select and delete.
  It adapts to a stacked navigation on iPhone and a split view on iPad.
* **Editor** — orbitable preview, project name, prong count, gem diameter,
  head height, prong height, all five head angles, base position, metal, all 22
  ring regions with their real size tables, and gallery rail controls
  (position, width, thickness, offset).
* **Operation catalog** — `OperationCatalog.swift` is generated from
  `08-reports/capability-matrix.csv`; the sheet lists all **88** v1 operations
  grouped by cluster, with search and a detail view. **12** are wired to real
  actions in this shell (save, reload, document path, delete, rebuild, ring
  lookups, resize placeholder); the other 76 are explicit entry points that
  report they are pending rather than pretending to run.
* **Regeneration** — `python Tools/operation_catalog.py` writes the catalog;
  `--check` fails CI if it drifts from the matrix.

## What rests on inference

Recorded in `limitations.md` #17–#18:

1. The gallery's horizontal intersection is linearly interpolated between the
   32 sampled side-rail points, not solved on the NURBS curve.
2. The 2D offset of an ellipse is approximated by adding the offset to both
   radii; the exact `GemOffsetCurve.GemOffset` result is not reconstructed.
3. The rail band is rectangular; the vendor sweeps an authored profile, which
   is not in the corpus.
4. `RailShearMultiplier`, `RailMove` and `RailUpperToggle` are stored but the
   shear/focal-point moves are not applied; the default toggle is off.
5. The M3 boundary still applies: gem outline, prong section, natural spline
   and loft-instead-of-Sweep1 are reconstructions.
6. The shell has **compiled**, not been run on a simulator or device. There is
   no macOS host on this machine, so navigation, autosave and controls are
   build-verified only; no screenshot or interaction test exists.

## Reproduce

```
python Tools/head_geometry_vectors.py --check
python Tools/operation_catalog.py --check
python 04-index/validate_handoff.py
python Tools/m2.py --check
```

The app is generated by XcodeGen from `07-ios-handoff/App/project.yml`; CI
does that and builds for `generic/platform=iOS Simulator`.
