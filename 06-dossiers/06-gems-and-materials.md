# Dossier 06 — Gems, Metals & Materials

**Status:** implementation-grade · **Evidence:** `CSGemInstance` (103 types / 484 methods), `CSMaterials` (12 / 103), `Common.Materials` (34 / 153), `Common.CyclesModels`, plus 257 real `.mgm` files
**Why it matters:** gem proportions and metal appearance are what the customer judges. A geometrically perfect ring with wrong diamond depth or wrong white-gold colour reads as fake.

---

## 1. Two separate systems

| System | Types | Persistence | Purpose |
|---|---|---|---|
| **Gem instances** | `CSGemInstance` + `CSBlocks.Gems` | Inside the design graph / `.3dm` | Shape, mm size, table data, seating depth |
| **Materials** | `Common.CyclesModels.MGMaterial`, `CSMaterials` | `.mgm` JSON per material, `.mgstyle` stylesheets, `.mge` environments | PBR-ish appearance, metal identity, render preview |

Do not merge them. A gem has a *material* reference, but the gem's geometry comes from its shape/size table.

---

## 2. Gem model

`CSGemInstanceDefinition` (55 methods) is the base; subclasses are concrete shapes:

* `CSGemInstanceDefinitionCustom` -> `CustomDiamondEmerald`, `CustomDiamondBaguetteTapered`, `CustomUser`
* Shape classes live in `CSGemInstance.GemTableData.GemTables` (30+ files): `DiamondRound`, `DiamondOval`, `DiamondMarquise`, `DiamondPear`, `DiamondHeart`, `DiamondPrincess`, `DiamondEmerald`, `DiamondCushion` (+ rotated/square variants), `DiamondBaguetteStraight/Tapered`, `DiamondTrillionCurved/Straight`, `DiamondHalfMoon`, `DiamondHexagon`, `DiamondOctagon`, `DiamondRadiant`, `DiamondTriangle`, plus `CabochonRound/Oval/Cushion/Emerald/Heart/Marquise/Pear/Square/Bullet`.

**Size tables are versioned.** `GemTableBase` is constructed with a shape and a list of table versions; e.g.:

```csharp
public DiamondRound() : base(GemTableType.Diamond, GemTableShape.Round,
                             new List<int> { -6, -5, -4, -3, -2, -1, 1, 2 }) { }
```

Each version returns its own `IEnumerable<GemSizeBase>`. Entries are `GemSizeRectangle`/`GemSizeRectanglePercent(width, height, depthPercent)`; round brilliant uses a constant **61.5 %** depth across the size range (starting at 1.0 mm in three table versions and 0.8 mm in the other five). Version selection matters: designs saved by older MatrixGold reference older table versions, and the same "1 ct round" can differ by tenths of a millimetre between versions.

**Recovered data contract**

| Concept | Type | Fields |
|---|---|---|
| Shape identity | `GemTableType`, `GemTableShape` | Diamond/Cabochon/... x Round/Oval/Emerald/... |
| Size row | `GemSizeBase` -> `GemSizeRectangle`, `GemSizeRectanglePercent` | width mm, height mm, depth (percent or mm) |
| Table | `GemTableBase` / `IGemTable` | `SizeTable(version)`, `CurrentVersion` |
| Registry | `GemTableHelper` (25 methods) | lookup by shape + version |
| Instance | `CSGemInstanceDefinition` | shape, size, position, orientation |
| Parameters | `GemInstanceDefinitionParametersBase` + shape-specific | custom proportions (table %, crown angle, pavilion depth, girdle thickness) |
| Placement math | `CSUtilGem` (55), `CSUtilGemRails` (44), `CSUtilGemOnCrv`, `CSUtilGemRailsNew` | girdle curve, seat plane, transforms |

Custom shapes (`CustomDiamondEmerald`, `CustomDiamondBaguetteTapered`, `CustomUser`) expose the full proportion parameter set. Port these as an explicit `GemProportions` struct; do not try to infer them from a mesh.

**iOS mapping.** `GemShape` enum (CaseIterable, Codable) -> `GemTable` protocol with `size(version:index:)` -> `GemSize` value type. Tables are data, not code: export them once from `SizeTable(version)` for every shape/version into JSON (same approach as ring sizes) and ship that as the source of truth. This is the single highest-fidelity, lowest-risk extraction available in the whole program.

---

## 3. Material model (`.mgm`)

`MGMaterial` is `[DataContract]`, ~55 serialised members. Real file header (584 KB, includes XML + base64 preview):

```json
{
  "BumpMapData": null, "BumpTextureType": 0, "ColorMapData": null, "ColorTextureType": 0,
  "Diffuse": 0, "DisplayPreviewRender": false, "EnglishName": "*Diamond Classic",
  "EnvironmentMapData": null, "GuidToReplace": "00000000-...", "HasBumpMap": false,
  "HasColorMap": false, "HasCustomSpecificGravity": false, "Hue": 0,
  "Id": "f53bfbce-b620-414a-89b6-0474e4546838", "Ior": 0,
  "IsRenderGemMaterial": true, "IsGemMaterial": false, "IsMetalMaterial": false,
  "Luminance": 0, "MaterialOwner": 1, ...
}
```

Full member set (authoritative, from `[DataMember]`):

* **Identity**: `Id`, `Name`, `EnglishName`, `Description`, `MaterialType`, `MaterialSubType`, `MaterialOwner`, `IsUserMaterial`, `IsModified`, `IsFavoriteMaterial`
* **Classification flags**: `IsMetalMaterial`, `IsGemMaterial`, `IsGroundPlaneMaterial`, `IsMiscellaneousMaterial`, `IsAlphaMaterial`, `IsRenderMetalMaterial`, `IsRenderGemMaterial`
* **Metal identity**: `MetalType` (`Gold`, `Palladium`, `Platinum`, `Silver`), `MetalSubType` (`Green`, `White`, `Rose`, `Yellow`, `SuperWhite`, `Iridium`, `Ruthenium`, `Sterling`), `MetalQuality`, `Quality`, `QualityType`, `StullerColor/Family/Name`
* **Optical**: `Diffuse`, `HasOnlyDiffuse`, `Specular`, `Shine`, `Reflectivity`, `ReflectionColor`, `ReflectiveColor`, `Transparency`, `TransparencyColor`, `Hue`, `Saturation`, `Luminance`, `Ior`
* **Maps**: `ColorMapData`, `BumpMapData`, `EnvironmentMapData` (each `MaterialMapData`), `ColorTextureType`, `BumpTextureType`, `HasColorMap`, `HasBumpMap`
* **Physical**: `SpecificGravity`, `StockSpecificGravity`, `HasCustomSpecificGravity` (drives metal **weight**, not just looks)
* **Render**: `MaterialXml`, `PreviewBase64`, `DisplayPreviewRender`, `FlamingoLibraryGuid`, `GuidToReplace`, `FilePath`, `CSMaterialName`

`MaterialMapData`: `MapPath`, `MapType`, `MapChannelType`, `Blend`, `IsOn`, `IsAvailable`, `IsEnvironmentMap`, `IsRepeatLocked`, `FinishType`, `LocalName`, `EnglishName`, `MapPreviewBytes`.

**Enums**: `MaterialOwner { None, Stuller, User, Public }`; `MaterialType { None, Metal, Gem, GroundPlane, Miscellaneous, RenderMetal, RenderGem }`; `MaterialSubType { None, ColorMap, EnvironmentMap }`; `MetalType { None, Gold, Palladium, Platinum, Silver }`; `MetalSubType { None, Green, White, Rose, Yellow, SuperWhite, Iridium, Ruthenium, Sterling }`; `MaterialFinish { Polish, Hammer, Florentine, BeadBlast, Brushed, Satin, Custom }`; `RenderTextureType { TileTexture, BitmapTexture, LeatherGrainBumpTexture, StuccoTexture, NoiseTexture, Other, None }`.

**Specific gravity is functional.** `SpecificGravity` + volume yields metal weight in grams (the number a jeweller quotes). Any iOS port must keep both `SpecificGravity` and `StockSpecificGravity` and the custom override flag; using only appearance data loses a core business feature.

---

## 4. Material groups and the render pipeline

`CSMaterials.MaterialGroup` (25 methods) with 15 properties: `Id`, `Name`, `MaterialName`, `Description`, `Classification`, `AlphaOrdinal`, `MaterialGroupItems`, and the flags `IsDefaultMaterialGroup`, `IsDesignerMaterialGroup`, `IsEditableMaterialGroup`, `IsGemMaterialGroup`, `IsGemNumberingOnly`, `IsMetalMaterialGroup`, `IsConstructionGroup`, `IsUserMaterialGroup`.

`CSDisplayMaterial` (17) has just `Name` + `DisplayMaterial` — the viewport proxy. `CSDisplayConduit.LoadMaterials()` / `GetLoadedMaterialByName(string)` (in `CS.dll`) resolve a name to a viewport material at draw time.

`CSMaterials.Helpers.ExportHelper` (25 methods) handles export-time material conversion; `CommonMaterialHelper` (76 methods in `Common.Materials`) is the shared import/export/validation path for `.mgm` and legacy render materials (`MGRenderMaterial`).

**Pipeline (recovered):**
```
.mgm JSON  -> MGMaterial (DataContract)
           -> MaterialGroup (classification: metal / gem / construction / user)
           -> CSDisplayMaterial (viewport)
           -> render engine (Cycles-style: IOR, transmission, metal tint)
           -> ExportHelper (STL/OBJ/3DM material assignment)
```

`.mgstyle` (25 files) are stylesheet bundles that reference material groups; `.mge` (16) are environment/HDR definitions; 34 HDR environments ship in the content library.

---

## 5. Content inventory (measured)

| Asset | Count | Notes |
|---|---:|---|
| `.mgm` materials | 257 | PascalCase JSON, `Id` GUIDs, ~590 KB average for render gems |
| `.mgstyle` stylesheets | 25 | 30 MB total stylesheet content |
| `.mge` environments | 16 | render environment definitions |
| `.3dm` gem/component models | 903 | 1.14 GB |
| HDR environments | 34 | shipped in the content library |

These are **licensed content**, not code. The iOS app must ship its own licensed equivalents; do not copy `.3dm`/`.mgm` assets into an App Store build. Export only schemas and the numeric tables you generated.

---

## 6. iOS mapping (Metal / RealityKit)

| MatrixGold | iOS |
|---|---|
| `MGMaterial` | `struct MaterialPreset: Codable` (same field names for round-trip) |
| `MaterialType`/`MetalType`/`MetalSubType` | Swift enums, `Int`-backed to match the wire format, exhaustive |
| `MaterialMapData` | `MaterialChannel { path, type, blend, finish }` |
| `MaterialGroup` | `MaterialCollection` with `Classification` |
| `GemTableBase` | `GemTable` protocol + JSON tables |
| `CSDisplayMaterial` | `PhysicallyBasedMaterial` cache keyed by name |
| `SpecificGravity` | `density` on `MetalPreset`, used by `WeightCalculator` |

**Rendering recipe for believable gems:** `PhysicallyBasedMaterial` with `transmission` 0.9–1.0, `ior` from `MGMaterial.Ior` (diamond 2.417), `specular`, thin `clearcoat`. Faceted sparkle needs a pre-baked environment map or a custom Metal shader with dispersion; default PBR looks plasticky without it. Budget a dedicated gem shader — it separates "jewelry app" from "3D viewer".

**Weight calculator** (small, high-value):
```
volume_mm3 = solid volume of the finished Boolean result
weight_g   = volume_mm3 * specificGravity / 1000
```
Use the metal's real `SpecificGravity` from shipped `.mgm` files; never hardcode from memory.

---

## 7. Verification state

* `JewelryKit` decodes real `.mgm` fixtures (`real-groundplane.mgm`, `real-metal.mgm`) and round-trips every modelled field; `sample.mgm` covers nested `MaterialMapData`.
* **Gem-table extraction is not yet executed** — it is the top item in the extraction backlog (Dossier 08). Method: instantiate each `GemTableBase` subclass in an isolated harness (exactly like the ring-size harness), call `SizeTable(version)` for every version, serialise to JSON. Roughly 30 shapes x 8 versions x ~100 rows.
* Material count/format verified against the mirror: 257 `.mgm`, PascalCase JSON, GUID identity.

---

## 8. Evidence queries

```sql
select t.full_name, count(m.id) n
from types t join assemblies a on a.id=t.asm_id left join methods m on m.type_id=t.id
where a.assembly in ('CSGemInstance','CSMaterials','Common.Materials')
   or (a.assembly='CSBlocks' and t.namespace like 'CSBlocks.Gems%')
group by t.id order by n desc;

select p.name, p.type from properties p join types t on t.id=p.type_id
where t.full_name='Common.CyclesModels.MGMaterial' order by p.name;
```

Sources: `03-decompiled/raw/CSGemInstance/**` (89 files), `03-decompiled/raw/Common/Common.CyclesModels/MGMaterial.cs`, `03-decompiled/raw/CSMaterials/**`.
