# Dossier 05 — Parametric Construction Engine (CSBlocks)

**Status:** implementation-grade spec · **Evidence:** static decompilation + symbol ledger + BAML bindings + REA PE/CLI evidence
**Assemblies:** `CSBlocks` (managed `.mgp`, 965 types / 5,927 methods), `CSBlockUtil` (85 / 872), `CSBlockDataUtils` (35 / 207)
**Purpose:** this is the "calibre" of MatrixGold. Everything else is packaging. An iPad app that reproduces this engine can honestly claim to be a jewelry CAD tool; one that only reproduces the UI cannot.

---

## 1. What this subsystem is

MatrixGold does not store finished meshes. It stores a **directed graph of parametric blocks**, each of which owns typed input channels, typed output channels, and an `Update()` that recomputes geometry. A ring is a graph: `Shank -> RingRail -> Head/ProngPlacer -> Gems -> Cutters -> Boolean -> Output`. Editing a parameter invalidates downstream nodes only.

Two consequences the iOS team must internalise:

1. **The unit of persistence is the graph, not the mesh.** Meshes are a cache. Any iOS design that saves only geometry cannot support parameter editing and will not match MatrixGold's behaviour.
2. **Block granularity is the product's vocabulary.** There is no "make ring" function; there are ~300 block types (heads, prong placers, bezels, halo builders, channel cutters, shanks, rails), each independently parameterised.

---

## 2. The node contract (`CS.CSObjects.CSBlocks.CSBlock`)

`CSBlock : CSObject`. This is the single most important interface in the software. Reproduced from the decompiled contract (all names below are **non-obfuscated** and therefore authoritative):

| Member | Signature (abridged) | Meaning for the port |
|---|---|---|
| `Update` | `bool Update()` | Recompute this node. Returns success. |
| `Process` | `bool Process()` | Orchestrates update: pre-checks -> `Update` -> status. |
| `PreUpdateCheck` | `bool PreUpdateCheck()` | Validate inputs before any geometry work. |
| `BlankOutBeforeUpdate` | `bool BlankOutBeforeUpdate()` | Clear previously generated objects so a rebuild is idempotent. |
| `InputError` | `bool InputError()` | Distinguish "bad input" from "failed computation". |
| `AddInputChannel` | `int AddInputChannel(string, ChannelFlag)` | Declare a typed input port; returns its index. |
| `AddOutputChannel` | `int AddOutputChannel(string)` | Declare an output port. |
| `GetInputChannel` / `GetOutputChannel` | `CSInputChannel` / `CSOutputChannel` | Port access by index. |
| `GetOutputChannelData` | `CSData GetOutputChannelData(int)` | The payload an edge carries. |
| `SetInputChannel` | `bool SetInputChannel(int, CSBlock, ...)` | Wire an edge from another block. |
| `UpdateInputOutputObject` | `bool UpdateInputOutputObject()` | Propagate changed state along edges. |
| `MarkAllChanged` | `bool MarkAllChanged(int)` | Dirty propagation. |
| `UpdateAllChanged` | `bool UpdateAllChanged()` | Graph-level settle. |
| `CheckIllegalLoops` | `bool CheckIllegalLoops(CSBlock)` | Cycle detection; the graph is a DAG. |
| `HasIllegalLoop` / `LoopCheckStatus` | `bool` / `BlockLoopCheckStatus` | Loop state surfaced to UI. |
| `ProcessingStatus` | `BlockProcessingStatus` | Idle / processing / error / cancelled. |
| `ExecutionTick` | `long` | Monotonic edit counter; drives cache validity. |
| `Generate` / `GenerateConcurrently` | `void Generate(bool)` | Batched evaluation, optionally parallel. |
| `RequestCancellationOfParallelTasks` | `void` | Cooperative cancellation for interactive editing. |
| `ReadJson` / `WriteJson` | `bool ReadJson(JObject, CSParaGraph, int)` / `void WriteJson(ref JObject)` | **Persistence is JSON per node.** |
| `SetUndo` | `bool SetUndo(CSObject)` | Per-node undo capture. |
| `UpdateTransform` | `bool UpdateTransform(Transform)` | Whole-block rigid transform. |
| `OutputChannelsToAddToDocument` | `List<ChannelOutputToDocConfig>` | Declarative "what becomes visible geometry". |
| `AddToDocumentExport` / `AddToDocumentRender` | `bool ...(ConcurrentBag<...>)` | Two consumers: export (STL/print) and render. |

**Port model.** `CSInputChannel` (129 methods) and `CSOutputChannel` (10) derive from `CSChannel` (11). Behaviour is governed by `ChannelFlag`, `ChannelDataType`, `ChannelArrayType`. Inputs are not just geometry: channels carry `CSData`, numbers, curves, bitmaps (`SetBitmapToChannel`), and object references. An input may be satisfied by a literal ("value channel") or by an edge from another block — which is why the same block works standalone or embedded.

**Evaluation pipeline** (reconstructed order, each step a real method):

```
mark dirty (MarkAllChanged)
  -> PreUpdateCheck                 (reject invalid input early)
  -> BlankOutBeforeUpdate           (idempotent rebuild)
  -> Update()                       (block-specific geometry)
  -> UpdateInputOutputObject        (push results down edges)
  -> UpdateAllChanged / Generate    (settle downstream, DAG order)
  -> status: BlockProcessingStatus  (Idle | Processing | Error | Cancelled)
```

**Invariants**

* `Update()` must be idempotent with respect to stored state: calling it twice yields identical geometry. `BlankOutBeforeUpdate` enforces this.
* A block must never read a downstream block. Illegal loops are detected, not prevented at wire time (`CheckIllegalLoops`), so the UI can show a broken graph rather than block the edit.
* `ExecutionTick` is the cache key: output is valid only if the tick at generation equals the current tick.
* Cancellation is cooperative and must be checked inside long loops (`RequestCancellationOfParallelTasks`).

**iOS mapping.** Model as a `ParametricGraph` of `Block` values with typed `Channel` endpoints, evaluated by a scheduler that topologically sorts and can cancel. Swift actors are a poor fit (geometry is CPU-bound, not IO-bound); use a serial `DispatchQueue` per graph plus a concurrent worker pool for independent branches, mirroring `GenerateConcurrently`. Persist as Codable JSON with a `type` discriminator and channel arrays (section 7).

---

## 3. Block taxonomy (measured)

`CSBlocks` namespace families, by method count (excluding vendored code):

| Family | Types | Methods | Role |
|---|---:|---:|---|
| `CSBlocks.Settings` | 78 | 975 | Prong placers, cluster placement, seat/gallery parameters |
| `CSBlocks.Settings.Heads` | 64 | 850 | Head (basket) builders, prong profiles, head styles |
| `CSBlocks.GemClusters` | 45 | 638 | Halo and cluster builders |
| `CSBlocks.Gems` | 79 | 424 | Gem placement transforms, pave, channel setup |
| `CSBlocks.Cutters` | 31 | 414 | Azure, channel, halo, comfort-fit, shank-mounting cutters |
| `CSBlocks.Shank` | 36 | 286 | Shank profiles, signet, French-set production |
| `CSBlocks.Transforms` | 82 | 284 | Matrix/plane construction (Dossier 04) |
| `CSBlocks.Curves` | 64 | 205 | Curve utilities (Dossier 04) |
| `CSBlocks.Core` | 30 | 109 | Bounding boxes, orientation, primitives |
| `CSBlocks.Maths` | 23 | 56 | Numeric helpers (Apollonius, blends) |
| other (`Profiles`, `Rails`, `Sweeps`, `Caps`, `Patterns`, `Texture`, `Builders`, `Tools`, `Tests`) | 477 | 1,801 | Sweep/rail/profile machinery and composite builders |

**Versioning reality.** The assembly contains `.Obsolete` namespaces with multiple generations (`CSProngPlacerGC6...GC16`, `CSHeadBuilderV1/V2`, `CSHaloBuilder2...5`, `CSChannelFromGemsNew3...5`). Only the newest non-obsolete generation should be ported. This is a large saving: `CSProngPlacerGC12/13` alone are 77 methods each and are dead code. The ledger's namespace data filters this mechanically (query in section 8).

Current-generation anchors to port, with method counts:

| Type | Methods | Why it matters |
|---|---:|---|
| `CSBlocks.Settings.Heads.CSHeadBuilderV2.CSHeadBuilder` | 21 + `Update` | The head/basket generator used by the current UI |
| `CSBlocks.Settings.Heads.CSHeadBuilderV2.ProngParam` | 54 | Prong parameterisation (tip, dome, rail, blend) |
| `CSBlocks.Settings.CSProngPlacerGC` | 19 | Generic prong placement along a curve/rail |
| `CSBlocks.Settings.CSClusterProngPlacer` | 16 | Cluster/halo prong placement |
| `CSBlocks.Settings.Bezels.BezelCreationHelper` | 43 | Bezel wall, gallery rail, under-bezel, handle transforms |
| `CSBlocks.Shank.ShankV1.CSShankGem` | 14 | Gem-set shank |
| `CSBlocks.Shank.French.CSFrenchSetProduction` | — | French-set channel production |
| `CSBlocks.Rails.CSRingRailFlex` / `CSRingRailTube` | 18 / 15 | Ring rail variants |
| `CSBlocks.Builders.CSGemInChannelSetUp` | 30 | Channel-set gem layout |
| `CSBlocks.Gems.CSPaveProngsTransforms` | 23 | Pave bead/prong transforms |
| `CSBlocks.Cutters.CSAzureCutter`, `CSHaloCutter`, `CSShankCutterMounting` | 16 / 14 / 14 | The cutters that make a design manufacturable |

---

## 4. The head builder (the most valuable algorithm)

`CSHeadBuilderV2.CSHeadBuilder` declares only 21 methods but the file is 99 KB — the work lives in `Update()` and in `CSHeadFinish`. Recovered control flow:

```
Update()
 |- read gem (CSData inGem) -> girdle curve, diameter, table plane
 |- compute rail geometry from gem girdle + railMultiplier
 |- build prong rails          BuildProngRail, BuildProngRailBlend, BuildProngRailExtension
 |- build prong profiles       BuildProngProfile / BuildProngProfileNew / BuildProngProfilePolyline
 |- build prong domes          BuildProngDomeProfile, CreateProngDome, CalculateProngTipHeightToDome
 |- sweep rails -> surfaces    BuildSweepRail, BuildSweepProfile, BuildLofts, ComputeCurveSweep
 |- assemble head             CSHeadFinish(... 13 out arrays ...)
 |    |- prongs, rails, head, prongDomes, prongParts
 |    |- displayCurves, constructionProngCurves, constructionHeadCurves, constructionRailCurves
 |    |- PullToBase(railMultiplier, baseObject, gems, railsNotPulled, ...)   [if base object present]
 |- write output channels
```

`CSHeadFinish` is itself the spec — it declares exactly the outputs a head block must produce:

```csharp
private static bool CSHeadFinish(
    CSData inGem, double railMultiplier, List<Brep> iHeadProngObjects, List<Curve> headCurves,
    CSDataArray prongCurves, CSDataArray inProngParts, RailParam[] rails, bool diy,
    bool pullToBaseObject, CSDataArray inBaseObject,
    out CSDataArray outProngs, out CSDataArray outRails, out CSDataArray head,
    out CSDataArray prongDomes, out CSDataArray prongParts,
    out CSDataArray displayCurves, out CSDataArray constructionProngCurves,
    out CSDataArray constructionHeadCurves, out CSDataArray constructionRailCurves)
```

Port note: keep **construction curves** and **display curves** separate. MatrixGold uses construction curves for downstream blocks (cutters, rails) and display curves for viewport/render. Collapsing them breaks boolean cutters.

`PullToBase` has two overloads: one for prongs/rails (`CSDataArray baseObject, CSData gems, ...`) and one for a bezel (`ref Brep inBezel`). Both project generated geometry onto the shank surface using `railMultiplier` as the sink depth factor.

### Prong geometry primitives (all present as named methods)

* Profile construction: `BuildProngProfile`, `BuildProngProfileNew`, `BuildProngProfilePolyline`
* Tip/dome: `CreateProngDome`, `BuildProngDomeProfile`, `CalculateProngTipHeightToDome`, `CreateDomeRC`, `CreateDomeTop`, `CreateDomeBase`
* Rail/blend: `BuildProngRail`, `BuildProngRailBlend`, `BuildProngRailExtension`, `BuildBlendedProngMesh`, `BlendCorners`, `BlendCurveAdvanced`
* Seating: `GetClosestPointToGemGirdle`, `CalculateGemOrientationRelativeToTarget`, `CalculateTestGem`, `CalculateRotateTestGem`
* Validation: `CheckIntersectingObjects`, `CheckTolerance`, `HeadIntersect`, `FixBrepSolidOrientation`

### Bezels

`BezelCreationHelper` (43 methods) exposes the full bezel vocabulary: `BezelBuilder`, `BezelProfile`, `BezelRevolveInnerOuter`, `BezelOuterSurface`, `BezelSurfaceTop`, `BezelOutsideOnRingRail`, `BezelSweepNoProfile`, `CalculateBezelConstructionValues`, `CalculateBezelHandleTransforms`, `CalculateBezelHeightAdjustment`, `CalculateUnderBezelConstructionValues`, `CalculateUnderBezelHandleTransforms`, `GalleryRailOutside`, `CalculateGalleryRailHandles`, `CalculateGalleryRailHeightAdjustment`.

The bezel is **not** a swept profile but a revolve/sweep hybrid with explicit "handle transforms" — the wall is defined by two rails (inner/outer) whose handles are adjusted for height, then swept. Port the parameter set first, then the two-rail sweep.

### Cluster / halo

`CSClusterProngPlacer` (16) + `CSHaloBuilder*` + `CSClusterProngs1`, `CSClusterProngsToCurve1`. Method names give the contract: `CalcGemPos`, `CalcGemCurvePoints`, `CalcGemCurvePointsClosed`, `CalcLastLoopingGemPos`, `FindFirstSplitGemLocation`, `AdjustGemPosEnd`, `AdjustGemPosEndMirror`, `AddGems`, `AddGemsUp`, `AddGemsDown`, `AddSplitGems`, `AddTaperingGemsDown`, `AdjustEndErrorSoGemSpacingLessGemTollerance`.

**Spacing algorithm (recovered shape):** distribute N gems along a closed curve; the last gem's endpoint error shrinks spacing until it is below `gemTolerance` (`AdjustEndErrorSoGemSpacingLessGemTollerance`). Mirror variants exist for symmetric halves. Port this exactly — it is what makes halos look hand-set rather than evenly spaced.

---

## 5. Boolean and cutter strategy

Cutters are separate blocks (`CSBlocks.Cutters`, 31 types / 414 methods) that output **closed solids**, not operations. The boolean is applied at export/render assembly time, not inside the cutter. Named cutters: `CSAzureCutter`, `CSHaloCutter`, `CSShankCutterMounting`, `CutterChannel`, `CutterChannelFromCenter`, `CutterChannelFromEdge`, `CutterChamfer`, `CutterChamferWithFlat`, `CutterComfortFit`, `CutterHollow`, `CutterInsideRound`, `CutterInsideRoundWithFlat`, `CutterOval`, `CutterTopCenter`, `CutterTopEdge`, `CutterTopEdgeWithFlat`, `CutterTopWave`, `CutterTopWave2`, `Cutter2ChannelsFromCenter`, `Cutter2ChannelsFromEdge`.

**Invariant:** every cutter must be a closed manifold. `FixBrepSolidOrientation`, `FixOpenBrepRC`, `CapPlanarHoles`, `CapInterior`, `CleanBrepArray` are the repair steps that enforce it.

**iOS mapping.** Do not attempt B-rep booleans in Swift. Options, in order of fidelity:
1. **openNURBS C++** (Rhino's kernel, permissive licence) compiled for arm64 plus a thin Swift bridge. It gives `ON_Brep`, `ON_BrepBoolean`, `ON_Surface`, `ON_Curve` — the exact types this code manipulates.
2. A mesh-first approach (SceneKit/ModelIO plus a CSG library) ships faster but will not reproduce `.3dm` round-trip or Class-A surfaces. Acceptable for a v1 viewer, **not** for the construction engine.

---

## 6. What is genuinely hard (do not hand-wave)

1. **Sweep construction.** `CSBlockUtil.CSUtilSweep` (26), `CSUtilSweepRC` (16), `Sweep4Profile` (19), `CSSweep2C4Param`, `CSAutoSweep`, `BuildLofts`, `ComputeCurveSweepWithRhinoPlanes`. Multi-rail sweeps with per-rail planes are where most ports fail. Budget most of the engineering here.
2. **Rail/profile generality.** `CSRingRailFlex` vs `CSRingRailTube` vs `CSRingRailNew` vs `CreateSignetOutsideRingRail` — the rail is the spine of every design. Rails are parameterised by extents (`GetRingRailPointTop/Left/Right/Bottom/ExtentTop/ExtentLeft/ExtentRight/ExtentBottom`), with the side profile a separate curve (`GetRingRailSideProfile`).
3. **Tolerance discipline.** Jewelry is 0.01 mm. `CheckTolerance`, `DoubleEqual`, `GetError`, `DoublePointProd` exist because naive `==` and default tolerances fail at this scale. Use one `Tolerance` type with explicit absolute/relative values everywhere.
4. **Orientation repair.** Booleans on tiny, near-tangent solids produce inverted shells. `FixBrepSolidOrientation`, `FixBrepSolidOrientationRC`, `GetOutwardsBrep`, `GetOutwardsMesh` are load-bearing.
5. **Naming.** Method names are obfuscated inside these classes; only public API, class/field/property names survive. The semantics above come from signatures, strings, call graph and the readable helper assemblies — not from reading `\u0001()`.

---

## 7. Persistence contract

Each block serialises with `WriteJson(ref JObject)` and reads with `ReadJson(JObject, CSParaGraph, int)`. `CSParaGraph` is the document-level container. Channel identity is **index plus identifier** (`SetChannelIdentifiers`, `GetInputChannelIdentifier`), so saved designs reference channels positionally: the iOS decoder must preserve channel order exactly and tolerate unknown properties (Newtonsoft default) rather than fail.

Minimum JSON shape implied by the API:

```json
{
  "blocks": [
    {
      "type": "CSBlocks.Settings.Heads.CSHeadBuilderV2.CSHeadBuilder",
      "id": "guid",
      "executionTick": 42,
      "inputChannels": [
        { "identifier": "Gem", "dataType": "CSData", "sourceBlock": null, "value": {} }
      ],
      "outputChannels": [
        { "identifier": "Head", "dataType": "CSData", "toDocument": true }
      ],
      "parameters": { "RailMultiplier": 1.0, "ProngCount": 4 }
    }
  ],
  "edges": [ { "from": "guid", "fromChannel": 0, "to": "guid", "toChannel": 1 } ]
}
```

Property names survive obfuscation, so `parameters` keys can be recovered 1:1 from the `properties` table.

---

## 8. Evidence queries (reproduce these)

```sql
-- current-generation parametric types, excluding dead code
select t.full_name, count(m.id) n
from types t join assemblies a on a.id = t.asm_id
left join methods m on m.type_id = t.id
where a.assembly in ('CSBlocks','CSBlockUtil','CSBlockDataUtils')
  and coalesce(t.namespace,'') not like '%Obsolete%'
group by t.id having n > 10 order by n desc;

-- the node contract, verbatim
select m.name, m.signature from methods m join types t on t.id = m.type_id
where t.full_name = 'CS.CSObjects.CSBlocks.CSBlock' order by m.name;

-- every readable property on a block (drives the parameter schema)
select p.name, p.type from properties p join types t on t.id = p.type_id
where t.full_name = 'CS.CSObjects.CSBlocks.CSBlock' and p.is_obf = 0;
```

Decompiled sources: `03-decompiled/raw/CSBlocks/**` (798 files). Largest: `CSBlocks.Settings/CSProngPlacerGC.cs` (219 KB), `CSBlocks.Settings.Bezels/BezelCreationHelper.cs` (177 KB), `CSBlocks.Settings.Heads.CSHeadBuilderV2/CSHeadBuilder.cs` (99 KB).

---

## 9. Porting order for iPadOS (recommended)

1. `Tolerance`, `CSData`, `CSChannel`, graph + scheduler, JSON persistence. No UI yet; assert round-trip on 10 real designs.
2. `CSRingRailFlex/Tube` + profile sweeps. A plain band is the first visible win.
3. `CSHeadBuilderV2` + `ProngParam` + gems. A solitaire is the first *credible* win.
4. `BezelCreationHelper` + gallery rails.
5. `CSClusterProngPlacer` + halo builders (spacing algorithm in section 4).
6. Cutters + boolean + orientation repair.
7. Shank variants (signet, French set), patterns, textures.

**Definition of done for parity:** given the same design JSON, the iOS engine produces geometry whose sampled surface deviation from MatrixGold's export is below 0.01 mm on every block output, with identical channel-level metadata.
