# Dossier 07 — Ring Sizing & Measurement

**Status:** complete and machine-verified · **Evidence:** `CSRingSizes.dll` v3.1.22284.1001 decompiled + **7,005 golden vectors executed from the real assembly**
**Deliverable in hand:** `07-ios-handoff/JewelryKit` already implements this dossier (`RingSize`, `RingSizeTable`, `RingSizeCatalog`, `RingSizeMath`) against all vectors.

---

## 1. Model

One type, one invariant: a ring size is a **diameter** (mm). Radius is derived; circumference is derived. Every regional "size number" is a presentation of that diameter under a region-specific mapping.

```csharp
public readonly double Diameter;
public readonly double Radius;
// UniversalRingSize(RingSizeRegion, string ringSizeName, double diameter, double radius, int index)
```

`ToString()` -> `"{RingSizeAbrv}:{RingSizeName}:{Diameter}"` — a compact, round-trippable identity used in UI and persistence.

`RingSizeRegion` has **22 members**, each classified `RingSizeRegionType.Region` or `.Mathematical`:

| # | Region | Abbrev | Kind | Count |
|---|---|---|---:|---:|
| 1 | `Us` | US | Region | 65 |
| 2 | `Uk` | UK | Region | 66 |
| 3 | `Jp` | JP | Region | 37 |
| 4 | `Fr` | FR | Region | 160 |
| 5 | `De` | DE | Region | 38 |
| 6 | `Ch` | CH | Region | 160 |
| 7 | `Eu` | EU | Region | 39 |
| 8 | `DiameterMM` | DIAM. MM | Mathematical | 1,415 |
| 9 | `CircumferenceMM` | CIRC. MM | Mathematical | 4,443 |
| 10 | `DiameterIN` | DIAM. IN | Mathematical | 56 |
| 11 | `CircumferenceIN` | CIRC. IN | Mathematical | 176 |
| 12 | `DeRg` | DE (RG) | Region (table) | 32 |
| 13 | `EuRg` | EU (RG) | Region (table) | 32 |
| 14 | `JpRg` | JP (RG) | Region (table) | 32 |
| 15 | `UkRg` | UK (RG) | Region (table) | 55 |
| 16 | `UsRg` | US (RG) | Region (table) | 52 |
| 17 | `Fi` | FI | Region (table) | 29 |
| 18 | `Hk` | HK | Region (table) | 14 |
| 19 | `Pt` | PT | Region (table) | 35 |
| 20 | `EsRg` | ES (RG) | Region (table) | 26 |
| 21 | `Tw` | TW | Region (table) | 17 |
| 22 | `Es` | ES | Region (table) | 26 |
| | | | **Total** | **7,005** |

`(RG)` = "ring gauge" variant: the same physical sizes expressed with a different numbering convention.

**Rounding rule (critical).** The base class calls `Math.Round(value, 2)` — .NET banker's rounding (mid-point to even). Swift's `(x * 100).rounded() / 100` is *not* equivalent. The port must implement round-half-to-even; `JewelryKit.RingSizeMath.roundToEven` does.

---

## 2. Closed-form translators (7 regions, exact formulas)

Recovered verbatim from `GetDiameterAux(int index)` / `GetIndexAux(double diameter)`. `index` is 0-based.

### UK — `RingSizeRegionTranslatorUk`
```
diameterMM = ((index / 2.0) * 1.25 + 37.55) / pi
index      = round((diameterMM * pi - 37.55) / 1.25 * 2.0)
```
Name: `A...Z` at half steps (`A`, `A 1/2`, `B`, ...), then `Z+1`, `Z+1 1/2`, ... beyond Z (index >= 52).

### Japan — `RingSizeRegionTranslatorJp`
```
diameterMM = (index + 38.0) / 3.0
index      = round(3.0 * diameterMM - 38.0)
```
Name: the index as a decimal string.

### EU — `RingSizeRegionTranslatorEu`
```
diameterMM = (index + 41) / pi
index      = round(diameterMM * pi - 41.0)
```
Name: `index + 41`.

### France — `RingSizeRegionTranslatorFr`
```
diameterMM = (index / 4.0 + 41.0) / pi
index      = round((diameterMM * pi - 41.0) * 4.0)
```
Name: `index/4 + 41` with `1/4`, `1/2`, `3/4` fractions.

### Switzerland — `RingSizeRegionTranslatorCh`
Same diameter formula as France, but names start at 1: `index/4 + 1` (+ fractions). This is why CH and FR have identical diameters but different labels — a classic port bug.

### Germany — `RingSizeRegionTranslatorDe`
```
diameterMM = (index + 53) / 4.0
index      = round(diameterMM * 4.0 - 53.0)
```
Name: `(index + 53)/4` + fractions.

### US — `RingSizeRegionTranslatorUs`
```
diameterMM = ((index / 4.0) * 0.102 + 1.43) / pi * 25.4
index      = round((diameterMM * 0.0393700787 * pi - 1.43) / 0.102 * 4.0)
```
Constants: 0.102 in = 0.102 x 25.4 mm **per quarter size**, origin 1.43 in circumference. `0.0393700787` is `RingSizeHelper.ToIN`; `25.4` is `ToMM`.

### Mathematical regions
Dense scales stepped by `RingSizeHelper.RingSizeStep = 0.01`:

```
DiameterMM:      diameter = RingSizeDiameterMin + 0.01 * index
CircumferenceMM: circumference = RingSizeDiameterMin*pi + 0.01 * index; diameter = circ/pi
DiameterIN:      diameter = (minDiamIN + 0.01*index) * 25.4
CircumferenceIN: circumference = (minCircIN + 0.01*index) * 25.4; diameter = circ/pi
```
`RingSizeDiameterMin/Max` are computed at static-init time by intersecting every translator's own min/max (`RingSizeHelper` static constructor), so they are **derived**, not constants. For the port, use the measured range 11.56 mm ... 25.70 mm (from the vectors), which yields the counts above.

---

## 3. Table-backed translators (15 regions)

`RingSizeRegionTranslatorHardCoded` is a sealed base over `List<Tuple<string,double>> RingSizePairs`:
```
diameter = pairs[index].Item2
index    = argmin_i |pairs[i].Item2 - diameter|      // nearest, ties -> first
name     = pairs[index].Item1
```
`GetIndexAux` is a linear scan initialised with `double.MaxValue` — **nearest wins, first wins on tie**. Reimplement exactly; do not binary-search with different tie-breaking.

These tables exist because the standards are irregular (HK, TW, PT, FI, ES, and the RG variants). They are captured exactly in `05-evidence/vectors/ring-sizes.json` and embedded in the Swift package; no formula should be invented for them.

---

## 4. Behavioural rules to preserve

1. **Diameter is canonical.** Converting US->EU goes through mm, never size-number arithmetic.
2. **Radius rounds from the unrounded diameter.** `GetRadius` is `Math.Round(GetDiameterAux(index) / 2.0, 2)` — it halves the **raw** diameter, then rounds. Do not halve the already-rounded diameter: at UK size A the two differ (5.98 vs 5.97).
3. **Nearest lookup clamps** to the first/last table entry rather than returning nil.
4. **Name lookup is exact** in the original (`RingSizeName` string match, case-sensitive). `JewelryKit` normalises case and `7.5` -> `7 1/2` as a documented superset.
5. **Index is not stable across regions.** Never persist a bare index without its region.

---

## 5. Verification (already executed)

* The `RingVectors` harness executed the **real `CSRingSizes.dll`** in an isolated harness (no UI, no licensing path) and emitted `05-evidence/vectors/ring-sizes.json`: 22 regions, 7,005 sizes with name/diameter/radius/index.
* `04-index/validate_handoff.py` re-implements the 7 closed-form translators and compares name, diameter and radius against the harness output: **565/565 exact matches** (every US, UK, JP, FR, DE, CH, EU entry).
* `JewelryKit` tests assert catalog total (7,005), per-region spot values, inverse round-trips, and banker's-rounding edge cases.

Reproduce: `python 04-index/validate_handoff.py`

---

## 6. iOS mapping

`RingSizeRegion` (22 cases, `String`-backed) -> `RingSize` value type -> `RingSizeTable` (one region) -> `RingSizeCatalog` (all regions, bundled JSON). Formatting in `RingSizeMath`; lookup/normalisation in `RingSizeCatalog`.

UI guidance: choose region **before** number, because the same number is a different physical size; always show mm alongside the regional label (professional users check both). For measuring a physical ring, accept diameter or circumference at 0.01 mm precision — the original supports both.

**Do not** re-derive the hardcoded tables from an online "standard"; they are region- and vendor-specific. Use the vectors.
