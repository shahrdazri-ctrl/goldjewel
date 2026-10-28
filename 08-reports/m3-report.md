# M3 — first Swift geometry slice

The smallest end-to-end path from corpus v1 to pixels: a 6.5 mm round solitaire
head with four prongs renders in the iOS/iPadOS app, and the same builder
re-renders for 4/6/8 prongs and 6.0–8.0 mm gems.

## What renders

`HeadShapeBuilder` ports `CSHeadShape.HeadShape` (`GetDrop` for a null base
object, the three scale transforms, the four-point prong rail,
`ProngInterpCurve`). `ProngSweeper` places the prong section at the rail start
and end using the recovered scale/nudge rules and lofts between them along the
rail. `HeadAssembly` lofts the four recovered outlines into an open basket and
adds one capped solid per prong.

The app draws the resulting meshes with a small software projector (drag to
orbit, two segmented pickers to rebuild). No third-party geometry or rendering
dependency was added.

| Part | Triangles (4 prongs) |
|---|---:|
| Basket (four outlines, 128 samples) | 768 |
| Each prong (32 rail sections × 36 profile points) | 2,304 |
| **Total** | **9,984** |

## What the numbers were checked against

* **Golden vectors**: `05-evidence/vectors/head-geometry.json`, recomputed by
  `Tools/head_geometry_vectors.py` from the decompiled formulas, independent of
  the Swift. It fixes drop, the three scale vectors, all 128 girdle points,
  4 × 32 rail points, the bezel rail and the expected mesh counts. The Swift
  tests compare every point to 1e-9; CI runs the Python comparison and the
  Swift tests.
* **IL provenance**: nine literals used by the slice are listed in
  `JewelryKit/.../Resources/head-geometry-provenance.json` with method and IL
  offset. `Tools/head_geometry_vectors.py --check` fails if any offset does not
  hold that value in `05-evidence/corpus/v1/head-builder.il.json`.
* **CI**: `linux` runs both checks; `macos` builds the package and runs its
  tests; `ios-simulator` builds the app for iPhone and iPad.
* **Visual**: the golden mesh was rendered offline to catch orientation
  defects. The first version oriented the section along the rail and produced
  flat blades; the render exposed it and the frame was rebuilt so sections are
  perpendicular to the rail.

## CI evidence

At commit `7054d7e`:

| Gate | Run | Result |
|---|---|---|
| linux (validator, M2 corpus, geometry vectors, Swift tests) | 40635971561 | success |
| macos (package build + 28 tests, 5 in `HeadGeometryTests`) | 40635971460 | success |
| ios-simulator (iPhone + iPad app with the preview) | 40635971522 | success |

The macOS log shows `HeadGeometryTests` executing five cases, including the
point-by-point golden comparison and the 4/6/8-prong parametric test.

## Recovered, with provenance

| Behaviour | Source |
|---|---|
| `drop = headHeight + baseOffset` when no base object | `CSHeadShape.GetDrop`, null branch |
| base scale `(gemX + 2·drop·tan(angleX), …)` at `z = drop` | `CSHeadShape.HeadShape` IL 241/258 |
| middle scale with `baseAnglePosition` clamp and `z = drop·(1−p)` | `CSHeadShape.HeadShape` IL 1471/1530 |
| top scale `(gemX + 2·prongHeight·tan(angleX+topAngle), …)` at `z = prongHeight` | `CSHeadShape.HeadShape` |
| prong rail through top, girdle, middle, base points | `CSHeadShape.HeadShape` |
| rail point from the girdle outline at the prong angle (`50 mm` ray, `0.001` tolerance) | `CSHeadShape.HeadShape` IL 1168/1225 |
| dedupe `< 0.01`, two-point midpoint at `0.1`, cubic chord-knot interpolation | `CSHeadShape.ProngInterpCurve` IL 28/124 |
| section scale by `ProngTopX/Y`, `ProngBaseX/Y`, `sec(angle)`, nudge offsets | `CSHeadProngProfileSweep.ProngProfileSweep` |

## Inferred, not recovered

These are deliberate and labelled; none is presented as vendor behaviour.

1. **Gem outline**: an ellipse from `GemXSize/2`, `GemYSize/2`. This matches
   `GemOffsetRound.Offset(gem, 0)` except its `0.04` minimum-radius clamp, which
   is omitted because the builder rejects non-positive gem sizes.
2. **Prong angle**: the vendor intersects the girdle curve with a radial line;
   the port evaluates the same intersection analytically. Numerically
   equivalent, not instruction-identical.
3. **Spline solver**: natural cubic spline with chord knots reconstructs
   `Curve.CreateInterpolatedCurve(points, 3, Chord)`. It is not Rhino's exact
   solver, so intermediate rail positions may differ slightly; endpoints and
   control points are recovered.
4. **Prong section**: the vendor consumes an authored `ProngTopProfile` /
   `ProngBaseProfile` curve. The slice substitutes an ellipse (`0.5` corner
   fraction); replacing it changes no placement or scale rule.
5. **Sweep surface**: Rhino's two-profile `Sweep1` is approximated by a loft of
   interpolated sections along the same rail. The section placement is
   recovered; the interpolation between sections is a kernel choice.
6. **Open basket and caps**: the cage is an open loft and the prong ends are
   fan-capped. Real caps/booleans are later work.
7. **Tessellation and rendering**: 128 ring / 32 rail / 36 profile samples and
   the software projector's shading are fidelity knobs, not recovered values.

## Not in this slice

Prong domes (`ProngDome`, `ProngBaseDome`), gallery rails, bezels, halo and
cluster placement, cutters and booleans, gem seat geometry, and material
assignment. The rail and cage APIs are the seam those will attach to.

## Reproduce

```bash
python Tools/head_geometry_vectors.py            # regenerate vectors
python Tools/head_geometry_vectors.py --check    # verify vectors + IL offsets
python Tools/m2.py --check                       # corpus and ledgers
```
