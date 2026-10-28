# Dossier 04 — Geometry Kernel & Transform Layer

**Status:** implementation-grade · **Evidence:** `GemvisionGeometry` (66 types / 414 methods), `GemvisionCommon` (37 / 154), `CSBlocks.Transforms` (82 / 284), `CSBlocks.Curves` (64 / 205), `CSBlocks.Maths` (23 / 56), `CSBlocks.Core` (30 / 109), plus the global call profile
**Purpose:** define exactly which geometry primitives the iOS engine must provide, with the algorithms and tolerances the original relies on.

---

## 1. The dependency the port must accept

MatrixGold's geometry is **RhinoCommon**, not a bespoke kernel. Measured call profile across all first-party code (top callees):

| Calls | Callee |
|---:|---|
| 2,874 | `Transform.op_Multiply(Transform, Transform)` |
| 2,393 | `Point3d.get_Origin()` |
| 2,288 | `Point3d..ctor(double,double,double)` |
| 2,003 / 1,827 / 1,145 | `Point3d.X` / `.Y` / `.Z` |
| 1,687 | `Vector3d.op_Multiply(Vector3d, double)` |
| 1,648 | `Vector3d.ZAxis` |
| 1,635 | `GeometryBase.Transform(Transform)` |
| 1,536 | `RhinoDoc.ActiveDoc` |
| 1,246 / 687 / 346 | `Vector3d.XAxis` / `.YAxis` / `Curve.TangentAt` |
| 1,048 | `Point3d.op_Subtraction` |
| 1,025 / 642 | `Curve.PointAtStart` / `.PointAtEnd` |
| 928 | `Vector3d.Unitize()` |
| 923 | `Curve.Domain` |
| 864 / 834 / 509 | `BoundingBox.Min` / `.Max` / `.Center` |
| 840 | `Transform.Translation(Vector3d)` |
| 826 | `Point3d.Transform` |
| 777 | `NurbsCurve.Points` |
| 664 | `Curve.DuplicateCurve`, `Curve.ClosestPoint` |
| 657 | `Curve.PointAt(t)` |
| 548 | `NurbsCurve.Knots` |
| 534 | `Transform.Rotation(angle, axis, center)` |
| 487 | `Transform.Scale(plane, x, y, z)` |
| 495 | `Curve.ToNurbsCurve()` |
| 377 | `CurveIntersections` |
| 348 | `Curve.TangentAt(t)` |

**Conclusion:** 80 % of the engine needs only: Point3d, Vector3d, Transform (4x4), BoundingBox, Plane, LineCurve, NurbsCurve (control points, knots, domain, closest-point, tangent, subdivision), Brep (trimmed surfaces, caps, booleans), Mesh. Implement those well and the parametric dossiers become portable. `RhinoDoc.ActiveDoc` (1,536 calls) is document coupling — replace with an explicit `Document` dependency.

---

## 2. 2D polygon layer (Clipper)

`GemvisionGeometry.Helpers.Clipper` — **112 methods**, the largest single geometry type. Names (`AddLocalMinPoly`, `AddLocalMaxPoly`, `AddOutPt`, `AddEdgeToSEL`, `AXISTEST_X01`, `AXISTEST_X2`, `AddHorzJoin`, `AddKinkPoint`, `ReversePolygons`, `Subdivide`) identify it as the classic **Clipper** polygon-clipping library (Angus Johnson) embedded and renamed.

Implications:
* 2D booleans, offsets and joins are polygon-based here, not NURBS-based. Include a polygon clipper in the port (Clipper2 is MIT-licensed and has been ported widely; or write a bounded implementation).
* `ClipperBase`, `PolyNode`, `Int128` (16 methods, 128-bit integer maths for exact intersection) are part of it. The `Int128` type matters: Clipper's robustness comes from integer coordinates with 64/128-bit products. **Do not** replace with `Double` — you will get flickering self-intersections at small scales.
* `GemvisionGeometry.Calc.PolylineOffset` (24) is a separate offsetting algorithm with `OffsetDistance`, `MinEdgeLength`, `MaxOffset`, `PointCount`, and stages `CalcCornerDirs`, `CalcEdgeMaxOffsets`, `CalcEdgeTypes`, `CalcIntersectPoints`, `PerformOffset`. This is used for pave/channel outlines where Clipper's offset is too coarse.

**iOS mapping:** a `Polygon2D` type over integer coordinates (scale mm by 1e5), `Clipper` port, then `PolylineOffset` as a separate path for curved edges. Keep both; they are not interchangeable.

---

## 3. NURBS layer

`GemvisionGeometry.Geometry.GNurbsCurve` (10 methods): `Create`, `CreateInterp`, `AddGPoint`, `ClosestPoint` (2 overloads), `DeleteControlPoint`, `IsSymetrical`, `ToPolyLineMinLen`, `ToPolyLineMinLength`, `subDivide`.

`CurveDefinition` (31) + `CurveSegment` (24) wrap curve construction/segmentation; `CSBlocks.Curves.CSCurveRhinoOffset` (10) is the Rhino-backed offset used when a true NURBS offset is required (as opposed to `PolylineOffset`).

**Contract to reimplement** (minimum viable curve API, derived from call sites):

```
protocol Curve3D {
    var domain: (Double, Double) { get }
    func point(at t: Double) -> Point3D
    func tangent(at t: Double) -> Vector3D
    func closestPoint(to p: Point3D, tolerance: Double) -> (t: Double, distance: Double)?
    func duplicate() -> Curve3D
    func toNurbs() -> NurbsCurve
    func subdivide(count: Int) -> [Curve3D]
    func polyline(minLength: Double) -> [Point3D]
}
```

`IsSymetrical` (sic) exists because signet/twist designs test curve symmetry before mirroring. Keep it.

---

## 4. Transform nodes

Transforms are **blocks** in the graph, not utility functions:

| Node | Inputs | Behaviour |
|---|---|---|
| `CSBend` | `InObj`, `InPointOriginal`, `InPointCurrent`, `InPointSpine`, `InPointsArray`, `InPreserve`, `InRigid`, `InStraight` -> `OutObj` | Bend a solid along a 3-point spine. `DynamicBendParameters { StartPoint, Bendpoint, EndPoint, Preserve, Rigid, Straight }` |
| `CSShear` | — | Six explicit cases: `ObtainTransformXYForXSide/YSide/ZSide`, `ObtainTransformXZForXSide/YSide/ZSide`, with `ComputeRotatedVectorXY/XZ` |
| `CSCopyFromGem` | gem reference | Derive placement/transform from an existing gem |
| `CSMirror` (current generation) | object, plane | Mirror |
| `CSOrientBoundingBox` | `InObject`, `InGrowX/Y/Z` -> min/max/size/center + `OutTransformOrientUp` / `OutTransformOrientDown` | Bounding-box alignment, used to seat components |

`Bend` semantics (from `DynamicBendParameters`): given start, bend and end points, map geometry so the segment start->bend rotates to bend->end, with `Preserve` (keep length), `Rigid` (no shear), `Straight` (post-bend straight run). This is a **deformation**, not a rigid transform — it rewrites control points. Implement as a piecewise map over the object's points/control points with arc-length parameterisation; the original does it point-by-point (`InPointsArray` is the point set).

---

## 5. Tolerance and precision

Constants and helpers that encode the precision model:

* `GemvisionGeometry.Helpers.GMath` (21): `Clamp` (3 overloads), `IsValidDouble`, `IsValidSingle`, `LineInt`, `LineToPointDistance2D`, `GetClosestPointToLine`, `GetIntersection`, `InBoX` (sic), `CrossProduct2D`, `DotProduct2D`, `AngleBetweenVectors`, `AngleOfPoint`, `CheckLineBox`, `PiMinMax`, `ToDegrees`, `ToRadians`, `Factorial`.
* `CSBlocks.Maths`: `CSSubtractMulti`, `CalculateApolloniusCircle` (circle tangent to three circles/edges — used for fillets and prong blends), `Denominador`, `DorthInfty`, `Dpara`.
* `CSBlockUtil.CSUtilMath` (68 methods), `CSUtilGeometry` (88) — the shared numeric toolbox.
* Global: `DoubleEqual`, `CheckTolerance`, `GetError` in the parametric layer.

**Rule for the port:** one `Tolerance` value threaded through every call. MatrixGold works at 0.01 mm feature size; use absolute tolerance 1e-4 mm for curve operations and 1e-3 mm for booleans, and never compare doubles with `==`.

---

## 6. Mesh vs B-rep boundary

* Construction is **B-rep** (`Brep`, `Surface`, `NurbsSurface`) because fillets, offsets and booleans must stay exact.
* Display and STL export are **mesh** (`CreateMeshFromBrep`, `GetMeshableObjects`, `GetOutwardsMesh`, `CreateMeshProngMesh`).
* `Common.CyclesModels`/render uses tessellated meshes with material groups.

So the port needs both, and a tessellator with controllable chord tolerance. RealityKit renders meshes only; keep B-rep authoritative and tessellate on demand (cache keyed by `ExecutionTick`).

---

## 7. Recommended iOS geometry stack

| Option | Fidelity | Cost | Verdict |
|---|---|---|---|
| **openNURBS C++ (arm64)** + Swift bridge | Exact Rhino types, `.3dm` read/write, booleans | Medium; C++ interop, licence compliance | **Recommended** for the construction engine |
| Custom Swift NURBS + CSG | Medium; booleans are the weak point | High | Only if openNURBS licensing is unacceptable |
| Mesh-only (ModelIO + CSG) | Low; no Class-A surfaces, no `.3dm` | Low | Viewer/prototype only |

Bridging notes: openNURBS has no built-in tessellator as capable as Rhino's; budget a subdivision/tessellation layer. It also lacks Rhino's `BrepBoolean` in the open SDK (openNURBS provides data structures; some operations live in Rhino). Verify boolean availability early — if absent, use a robust mesh boolean on tessellated solids, accepting a fidelity loss confined to cutters.

---

## 8. Evidence queries

```sql
-- geometry types by method count
select t.full_name, count(m.id) n
from types t join assemblies a on a.id=t.asm_id left join methods m on m.type_id=t.id
where a.assembly in ('GemvisionGeometry','GemvisionCommon')
   or (a.assembly='CSBlocks' and (t.namespace like 'CSBlocks.Transforms%'
       or t.namespace like 'CSBlocks.Curves%' or t.namespace like 'CSBlocks.Maths%'
       or t.namespace like 'CSBlocks.Core%'))
group by t.id order by n desc;
```

Sources: `03-decompiled/raw/GemvisionGeometry/**` (48 files), `03-decompiled/raw/CSBlocks/CSBlocks.Transforms*/**`, `CSBlocks.Curves*/**`, `CSBlocks.Maths*/**`, `CSBlocks.Core*/**`.
