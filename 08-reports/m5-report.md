# M5 — corpus v2, grounded domes, bezels and halo seats

M5 fixes the evidence blocker first, then resumes the three families M4 stopped,
in the planned order: prong domes, bezel, halo/cluster. Every family is visible
in the app and carries a machine-checked provenance grade.

## Corpus v2

`Tools/build_corpus_v2.py` captured five assemblies (268 types, 2,242 methods,
18.6 MB of JSON) from the shipped IL:

| Assembly | Types | Methods | What it adds |
|---|---:|---:|---|
| CSBlockUtil | 8 | 236 | `CSUtilCurves`, `CSUtilSweepRC`, `CSUtilGeometry`, `CSUtilMath` |
| CSBlockDataUtils | 19 | 51 | `GemOffsetCurve` and the shape offsets |
| CSBlocks (families) | 87 | 859 | head builder, `GemClusters`, `CSClusterProngPlacer` |
| CSGemInstance | 99 | 484 | gem instances and `ProngPosition` seat data |
| CSDatas | 55 | 612 | `CSGemData` and the gem-data model |

The manifest records SHA-256 over canonical LF text and over the raw bytes,
the exact assembly hashes, and `mode: il-static-no-execution`. No vendor method
is executed: `CSBlocks` is a Rhino assembly and still fails to load outside
Rhino with `ERROR_DLL_INIT_FAILED`. RhinoCommon itself is not in the mirrored
product, so `Brep`/`NurbsSurface` calls remain call edges, not captured bodies.

**D: only.** Every corpus and cache path resolves under `D:\REA-LAB`. The
harness attempts one write to `C:\REA-LAB-v2-guard-test.json` as a guard; the
tool refuses it with exit 3 and the file is never created. The refusal is
recorded in the manifest (`d_only.guard`). During this milestone the volume
dropped out twice (`No such device` / `Invalid argument`); both reads were
retried after five seconds and verified by re-reading the files on disk.

## Families and grades

| Family | Grade | What is recovered | What is reconstructed or inferred | Triangles |
|---|---|---|---|---:|
| Prong domes | **reconstructed** | `CSUtilCurves.BlendCurve` control fractions 0.2/0.4 at IL_72/IL_119; apex height and setting offset | Meridian start tangent is radial (`inferred`); the Bezier is captured | 1,920 / prong |
| Bezel | **reconstructed** | `BezelProfile` seat polyline; `seatAngle + 180°` at IL_2436; seat height/length | Collar wall swept around the girdle (`reconstructed` from `RevolveBezel` ruling); radial ellipse normal (`inferred`) | 1,024 |
| Halo seats | **recovered** | `PlaceGems` count, even adjustment, phase, wrap, sort at IL_130/168/181 | — | — |
| Halo band | **reconstructed** | seat path from the offset girdle | rectangular band, not the authored `MakeHaloProfile` | 1,024 |
| Halo melee | **inferred** | seat positions and yaw | octagonal proxy crowns, not `CSGemInstance` faceting | 408 (17 stones) |

The full default assembly (4 prongs, dome on, gallery on, bezel off, halo off)
is **18,688 triangles**. Turning the bezel on adds 1,024; the 17-stone halo adds
1,432, for **21,144 triangles** with every family enabled.

## Provenance enforcement

`ProvenanceTier` distinguishes `recovered` (IL-traced literal or construction),
`reconstructed` (documented algorithm when the helper was not captured) and
`inferred` (explicit substitute with a rationale). The package resource now has
**19 IL literals** and **13 claims**. `testProvenanceIsPresent` and
`testProvenanceTiersAreEnforced` require:

* every literal to be graded `recovered` with a method and IL offset;
* every `reconstructed` claim to name a documented algorithm;
* every `inferred` claim to give a rationale;
* all three tiers to appear;
* every visible part in `partTiers` to be graded, with a supporting claim.

`testFullAssemblyDeclaresEveryFamilyTier` pins the complete map:

```
basket recovered · prongs inferred · domes reconstructed · gallery inferred
bezel reconstructed · haloSeats recovered · haloBand reconstructed · haloGems inferred
```

## What was checked

| Check | Result |
|---|---|
| `python Tools/build_corpus_v2.py --check` | 5 files, 268 types, hashes match |
| `python Tools/head_geometry_vectors.py --check` | golden vectors match; **19 constants traced to IL** |
| `python Tools/operation_catalog.py --check` | 88 v1 operations, **14 wired** |
| `python 04-index/validate_handoff.py` | 0 failures |
| `python Tools/m2.py --check` | 50,134-method ledger and 254-operation matrix unchanged |
| Linux CI | **success** — corpus v2, geometry, catalog and package tests |
| macOS CI | **success** — **34 tests, 0 failures**, 11 `HeadGeometryTests` |
| iOS simulator CI | **success** — GoldJewel built for iPhone and iPad simulator |

The green run for the geometry and app commit is `548a01b` (linux
40645122595, macos 40645122756, ios-simulator 40645122734). The report and
wired-operation commit `90b24a2` is also green on all three gates (linux
40645522493, macos 40645522375, ios-simulator 40645522505). The simulator job
builds and uploads the `.app`; it does **not** launch it, so this is a compile
gate, not a runtime pass. There is no macOS host on this machine.

Offline inspection used `09-logs/render_check.py` with the golden data. The
first halo pass read as a solid washer from above; the band was narrowed to
0.6 × the melee diameter, shortened and dropped below the seats. The final
three views show separate stones, a thin band, visible dome caps and the bezel
collar. Those images are generated from the Python mirror, not from the Swift
renderer.

## App changes

* Domes are part of the default head; height, setting distance and setting
  angle are controls.
* Bezel is an optional family with seat height, seat length and seat angle.
* Halo is optional with melee diameter, spacing, rail offset, rail height,
  seat rotation and even-count.
* Saved projects decode older documents with the dome on and the optional
  families off; new fields are `dome`, `bezel`, `halo`.
* The preview draws every family in `HeadAssembly.combined` order and the
  Evidence panel lists each part's grade.

**Operations.** `GetActiveBuilderId` and `GetAllBuilderGuids` moved from listed
entry points to wired behaviour (the selected project is the active builder;
all project IDs are the builder GUIDs). That raises the wired count from 12 to
**14 of 88**. No v1 operation is named for a bezel or halo; those families are
reached through `ExecuteBuilderCommand`, which now rebuilds and reports every
graded family.

## What still rests on inference

1. Dome meridians start along the radial section direction; the vendor derives
   tangents from a Rhino curve/surface split that is not reproduced.
2. The bezel wall is a ruled rectangular section, not the exact
   `BezelProfile`/`RevolveBezel` outline, and uses the radial ellipse normal.
3. The halo metal band is a modelled rectangular sweep; `MakeHaloProfile` is
   captured but its 60-constant profile is not reproduced.
4. Halo melee stones are proxies; `CSGemInstance` faceting is not ported.
5. The M3/M4 inference list still applies to the prong section, spline solver
   and gallery band.
6. Nothing has been run on a simulator or device. The app compiles for both
   device families; navigation, persistence and rendering remain runtime
   unverified.

## Reproduce

```
python Tools/build_corpus_v2.py --check
python Tools/head_geometry_vectors.py --check
python Tools/operation_catalog.py --check
python 04-index/validate_handoff.py
python Tools/m2.py --check
```

The app is generated by XcodeGen from `07-ios-handoff/App/project.yml`; CI
builds it for `generic/platform=iOS Simulator`.
