# Coverage Report — what was actually analysed

All numbers below are measured from `04-index/symbols.sqlite` and the frozen mirror, not estimated.

## 1. Target

| Fact | Value |
|---|---|
| Install root | `D:\MAIN SOFTWARE\jewerly software\matrix gold\Gemvision.MatrixGold\Main\MatrixGold` |
| Mirror | `01-target/mirror` — 2,688 files, 1.81 GB, SHA-256 per file |
| Executable version | 3.1.22284.1001, unsigned, no strong name |
| Runtime | .NET Framework 4.8, WPF, MVVM |
| Managed assemblies | 225 (104 unique by name), 0 IL errors |
| Native-only assemblies | `MeshAPI.dll` (confirmed native, excluded) |
| Plugins | all 3 `.mgp` + both `.rhp` are managed .NET |

## 2. Mechanical coverage (100 % of managed metadata)

| Artifact | Count |
|---|---:|
| Types | 35,645 |
| Methods | 303,780 |
| Properties | 75,497 |
| Fields | 155,009 |
| Events | 768 |
| String literals | 91,902 |
| Call edges | 1,379,497 |
| Methods with IL errors | 0 |

## 3. First-party surface (the part that matters)

29 assemblies, deduplicated across the three shipping copies (`MatrixGold\`, `MatrixGoldPlugin\`, `MatrixGoldRenderPlugin\`):

| Artifact | Count |
|---|---:|
| Types | 4,466 |
| Methods | 38,934 |
| String literals | 18,604 |
| Call edges | 356,458 |

Largest first-party assemblies: `MatrixGold.exe` 951 types / 8,711 methods, `CS.dll` 653 / 7,550, `CSBlocks.mgp` 965 / 5,927, `MatrixGoldPlugin.rhp` 382 / 3,028, `Localization.dll` 6 / 2,117, `LocalizationCore.dll` 7 / 1,380, `Common.dll` 188 / 1,353, `MatrixCommon.dll` 233 / 1,295.

## 4. Decompilation

| Output | Count | Size |
|---|---:|---:|
| First-party assemblies decompiled | 32 / 32 | — |
| C# files | 2,787 | 65 MB |
| BAML -> XAML files | 117 / 117 (0 failures) | 31 MB |
| Extracted binding/command facts | 4,205 | — |
| Distinct binding paths | 1,169 | — |
| Distinct commands | 366 | — |

## 5. Executed evidence (not just read)

| Evidence | Result |
|---|---|
| Ring-size vectors from the real `CSRingSizes.dll` | **7,005 sizes**, 22 regions |
| Closed-form formula parity | **565 / 565** exact |
| Catalog structural validation | **7,005 / 7,005** (index sequence, radius derivation, plausible diameter) |
| `.mgm` material files parsed | **257 / 257** |
| Swift package resource identity | byte-identical to executed vectors |
| REA PE/CLI evidence bundles | 14 core assemblies |

## 6. Semantic coverage by subsystem

| Subsystem | Types | Methods | Dossier | Depth |
|---|---:|---:|---|---|
| Shell / service boundary | 1,155 | 7,821 | 01 | Architecture + 254-op contract + startup sequence |
| Document / persistence | 853 | 9,203 | 02 | Exact file format + schema + import/remap |
| Presentation | 249 | 4,497 | 03 | Full binding inventory + screen weights + interaction contract |
| Geometry | 302 | 1,222 | 04 | Call profile + kernel contract + algorithms |
| Parametric construction | 807 | 5,928 | 05 | Node contract + 300-node taxonomy + head/bezel/halo algorithms |
| Gems / materials | 262 | 1,317 | 06 | Full data model + enums + size-table structure |
| Ring sizing | 33 | 153 | 07 | Exhaustive + executed vectors |
| Content / l10n / settings | 1,474 | 15,828 | 08 | 81-node vocabulary + taxonomy + 18 locales |

(Subsystem counts overlap where a type legitimately belongs to two dossiers; they are not additive.)

## 7. What "100 % mechanical" means here

Every managed type, method, property, field, string literal and call edge is indexed and queryable. Every first-party assembly is decompiled to C#. Nothing was sampled for the mechanical layer.

The **semantic** layer is deliberately prioritised: dossiers cover the eight subsystems that determine product quality, at implementation depth, rather than giving 4,466 one-line type summaries. Anything not in a dossier remains queryable — `04-index/condense.py <subsystem>` regenerates a fact sheet on demand.

## 8. Reproduce

```powershell
python D:\REA-LAB\04-index\validate_handoff.py     # 0 failures expected
python D:\REA-LAB\04-index\condense.py parametric 40
sqlite3 D:\REA-LAB\04-index\symbols.sqlite "select count(*) from methods;"
```
