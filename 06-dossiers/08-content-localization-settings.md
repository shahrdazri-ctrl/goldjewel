# Dossier 08 — Content Library, Node Vocabulary, Localization & Settings

**Status:** implementation-grade · **Evidence:** `GVBuilders` (93 types / 145 methods), 81 patchwire types, `MatrixGoldLibrary` / `StyleSheetLibrary`, `Localization` (2,103 string accessors) + `LocalizationCore` (1,358), 18 shipped locales, content inventory
**Purpose:** define what the user can *pick* (content), what they can *build with* (node vocabulary), and how the app speaks and remembers (localization, settings).

---

## 1. The node vocabulary (the actual product surface)

`GVBuilders.Patchwires` contains **81 patchwire types**. This is the most honest list of user-facing operations in the entire codebase — more useful than any menu inventory:

```
AdvancedRingCurve, AutoBase, Bail, Bend, Bezel, BlendCurves, BooleanDifference,
BooleanIntersection, BooleanUnion, BypassOutsideRingRail, BypassRingRail,
CathedralRingRail, ChannelCutter, ClusterProngPlacer, CurveFrom2Views, CutToRingRail,
DupEdge, ExtractEdge, ExtractIsocurve, ExtrudeCurve, FilletCurves, FreehandPart,
GalleryRail, Gem, GemBetween2Curves, GemCutter, GemCutterLibrary, GemGuides,
GemListOnCurve, GemOffsetCurve, GemOnCurve, GemOnRingRail, GemOnSurface, GemsInChannel,
Halo, Head, Hinge, HollowRing, Join, MSRGems, MSRObjects, MicroProngCutter,
MicroProngCutterLibrary, Mirror, ObjectOnCurve, ObjectOnSurface, Offset,
OrientToGem, OutsideRingRail, PaveProngs, PearlCup, Pipe, PolarArray, ProfileCap,
ProfilePlacer, ProfileSweep, ProngOnSurface, ProngPlacer, ProxyGem, PullPush,
PullToRail, RasterToVector, RingRail, Rope, ScallopCutter, Shear, Signet,
SignetAdvanced, SmartFlow, SmartPattern, SplitCurve, SplitShank, Sweep1, Sweep2,
Taper, TextObjects, TextOnCurve, Texture3D, TrimCurve, Twist, UnderBezel
```

Grouped for the port:

| Group | Patchwires |
|---|---|
| **Rails/shanks** | `RingRail`, `OutsideRingRail`, `CathedralRingRail`, `BypassRingRail`, `BypassOutsideRingRail`, `SplitShank`, `Signet`, `SignetAdvanced`, `AdvancedRingCurve`, `HollowRing`, `Hinge`, `AutoBase` |
| **Settings (stone seats)** | `Head`, `Bezel`, `UnderBezel`, `GalleryRail`, `ClusterProngPlacer`, `ProngPlacer`, `ProngOnSurface`, `PaveProngs`, `PearlCup`, `Halo`, `MicroProngCutter`, `MicroProngCutterLibrary` |
| **Gems** | `Gem`, `ProxyGem`, `MSRGems`, `GemOnCurve`, `GemOnRingRail`, `GemOnSurface`, `GemListOnCurve`, `GemBetween2Curves`, `GemGuides`, `GemOffsetCurve`, `GemsInChannel`, `OrientToGem` |
| **Cutters** | `ChannelCutter`, `GemCutter`, `GemCutterLibrary`, `ScallopCutter`, `CutToRingRail` |
| **Profiles/sweeps** | `ProfileSweep`, `ProfilePlacer`, `ProfileCap`, `Sweep1`, `Sweep2`, `Pipe`, `Rope`, `ExtrudeCurve` |
| **Curves** | `BlendCurves`, `FilletCurves`, `SplitCurve`, `TrimCurve`, `Offset`, `DupEdge`, `ExtractEdge`, `ExtractIsocurve`, `CurveFrom2Views`, `FreehandPart`, `RasterToVector` |
| **Transforms/arrays** | `Bend`, `Shear`, `Twist`, `Taper`, `Mirror`, `PolarArray`, `PullPush`, `PullToRail`, `SmartFlow`, `SmartPattern` |
| **Objects/text/boolean** | `ObjectOnCurve`, `ObjectOnSurface`, `TextObjects`, `TextOnCurve`, `Texture3D`, `Join`, `Bail`, `BooleanUnion`, `BooleanDifference`, `BooleanIntersection`, `MSRObjects` |

**This list is the iOS feature backlog.** Each patchwire maps to a `Block` implementation (Dossier 05) and a palette entry (Dossier 03). Ship the groups in the order: rails -> settings -> gems -> cutters -> profiles -> transforms -> curves -> booleans.

---

## 2. Content taxonomy (measured)

```
Main/MatrixGold/
  Library/        components, 865 MB
    Clayoo/ Cutter/ Gem/ Object/ Pattern/ Profile/ Rail/ Render/ SmartPatterns/ Textures/ Tripod/
  Collections/    finished designs, 783 MB
    Displays/ Earrings/ Findings/ Pendants/ Rings/
  StyleSheets/    node presets, 30 MB
    Curve/ Cutters/ Gems/ Settings/ Solid/ Tools/ Transform/
  Animation Presets/
  Eula/
```

| Asset | Count | Notes |
|---|---:|---|
| `.3dm` component/collection files | 903 | 1.14 GB, Rhino geometry |
| `.mgm` materials | 257 | Dossier 06 |
| `.mgstyle` style sheets | 25 | saved graph fragments |
| `.pat` patterns | 62 | pattern definitions for `SmartPattern`/texture |
| locale resource assemblies | 91 | 18 locales across assemblies |

**Style sheets are documents.** `JSonDocumentWriter.WriteCSFile(..., styleSheetSave: true)` writes `PreviewBitmap` + `StyleSheetDescription` and the same `Graph`/`MaterialGroups`/`GemTable` sections. A `.mgstyle` is therefore a **saved graph fragment**, not a theme file. Import = the `ImportCSFile` merge path (Dossier 02). This is how "apply a style" works: merge a prepared sub-graph into the current design.

---

## 3. Library model

| Type | Methods | Role |
|---|---:|---|
| `GV.MatrixCommon.MatrixGoldLibrary` | 10 | Root library: categories, items, refresh |
| `GV.MatrixCommon.StyleSheetLibrary` | 9 | Style-sheet-specific library |
| `MatrixGold.ViewModels.LibraryManagerViewModel` | 36 | UI: browse, preview, insert, save-to-library |
| `MatrixGold.Models.LibraryFileInfo` | 9 | Item metadata (path, preview, category) |
| `AddProfileToLibrary` (plugin command) | 6 | Persist a user profile |
| `SaveProfileToLibrary`, `OpenProfileEditor` (`IRhinoService`) | — | Round-trip of user-created profiles |

`IRhinoService` exposes the content operations directly: `ReadContentManagerInfoFromFile`, `GetPreviewImageByteArrayFromBuilder`, `GetSelectedObjectsPreviewBytes`, `GetFilePreview`, `GetPathFileTemplate`, `GetPathFileBlank`. "PathFile" is the templating mechanism for saving user content into the right folder with the right extension.

**iOS content strategy:**
1. Ship a **catalog JSON** (id, category, name, localized name key, preview asset, file hash, byte size, licence flag) — generated offline from the shipped library.
2. Ship previews as HEIC/PNG; ship geometry **on demand** in your own compressed format (do not ship `.3dm`).
3. Put user content in Application Support with the same category taxonomy so imports map cleanly.
4. Keep a `user` vs `stock` flag on every item; the original's `*User` paths encode the same distinction.

---

## 4. Localization

`Localization.Strings` exposes **2,103** members; `LocalizationCore.Strings` a further **1,358** — all generated strongly-typed accessors, one per user-visible string. `LocalizationHelper` (8 methods) resolves culture; `Localization.ResourceEditor` + `ResourceEmbedderCompilerGenerated` are build-time tooling.

Shipped locales (18): `cs`, `cs-CZ`, `de`, `es`, `fr`, `hu`, `it`, `ja`, `ja-JP`, `ko`, `pl`, `pt-BR`, `ro`, `ru`, `sv`, `tr`, `zh-Hans`, `zh-Hant`.

**Rules for the port:**
1. One key per accessor name (e.g. `Strings.HeadStyle` -> `"headstyle"`); generate the Swift `LocalizedStringResource` catalogue from the same names so translations can be reused where licensing allows.
2. Never compose sentences from fragments; some locales reorder. The original uses full-sentence resources — keep that.
3. Enum display names are localised via `EnumToLocalizedStringConverter` (Dossier 03); in Swift use `LocalizedStringResource` on the enum, not `String(describing:)`.
4. Numbers/units are locale-sensitive: use `MeasurementFormatter` for mm/inch and `NumberFormatter` for dwt/grams.

---

## 5. Settings that change behaviour

`WindowPreferencesViewModel` (388 methods) is the largest non-render VM. The settings that materially affect output:

| Setting | Effect |
|---|---|
| Ring size region (`Get/SetDefaultRingSizeRegionAbrv`) | Default sizing standard (Dossier 07) |
| Unit system (mm/inch, dwt/grams) | All displayed measurements and weights |
| Tolerances (angle, distance) | Geometry validity and boolean success |
| Grid snap spacing (`Get/SetGridSnapSpacing`), smart track | Modelling feel |
| Autosave (`SetEnableAutosave`, `SetAutosaveSettings`) | Data safety |
| History settings (`GetHistorySettings`) | Undo depth / parametric history |
| UI scale (`CommandResetUIScale`) | Layout density |
| Render device (`Get/SetCyclesRenderDevice`), passes, size | Render quality/time |
| Preview shading (`SetEnablePreviewRenderShading`), backfaces | Viewport fidelity |
| Control points on curve selection | Editing affordance |

These belong in a single `AppSettings` value type, persisted once, injected through the environment. Do not scatter `UserDefaults` reads.

---

## 6. Extraction backlog (mechanical, highest value first)

| # | Job | Method | Output |
|---|---|---|---|
| 1 | **Gem size tables** | Instantiate each `GemTableBase` subclass; call `SizeTable(version)` for all versions | `gem-tables.json` (~30 shapes x 8 versions) |
| 2 | **Localization catalogue** | Reflect `Localization.Strings` + `LocalizationCore.Strings` accessors; pair with shipped `.resources` | `strings.json` keys + 18 locales |
| 3 | **Library catalog** | Scan `Library/`, `Collections/`, `StyleSheets/`; read previews + `.3dm` bounds | `catalog.json` |
| 4 | **Style sheet samples** | Load 5 `.mgstyle`, dump graph JSON | fixtures for import tests |
| 5 | **Default settings dump** | Read `CSApplication` defaults + registry/user config | `defaults.json` |

All five reuse the harness pattern already proven for ring sizes (`02-toolchain/RingVectors`): load the real assembly in an isolated process, call public APIs, serialise to JSON. No UI, no licensing path.

---

## 7. Evidence

```sql
select full_name from types where namespace like 'GVBuilders.Patchwires%' order by full_name;

select count(*) from methods m join types t on t.id=m.type_id
where t.full_name in ('Localization.Strings','LocalizationCore.Strings');
```

Sources: `03-decompiled/raw/GVBuilders/**` (88 files), `03-decompiled/raw/Localization/Localization/Strings.cs`, `03-decompiled/raw/LocalizationCore/**`, mirror inventory `01-target/target-manifest.csv`.
