# REA evidence — capture record

`rea@6.8.0` (`02-toolchain/npm-global`) was used for PE/CLI inspection only. No target assembly is loaded or executed.

## Status (re-captured 2026-10-27)

All **14 / 14** core bundles report `coverage.state = complete` and contain real member rows. Earlier CS, CSBlocks and MatrixGold captures contained a type inventory and **zero methods** because REA's metadata projection budget was exceeded; those superseded stubs are no longer kept. The current CSRingSizes bundle is the full 33-type / 153-method assembly.

| Assembly | Types | Methods | Fields | Call edges | Bundle |
|---|---:|---:|---:|---:|---:|
| MatrixGold.exe | 951 | 8,711 | 4,363 | 48,524 | 48.2 MB |
| CS.dll | 653 | 7,550 | 3,819 | 53,873 | 50.7 MB |
| CSBlocks.mgp | 965 | 5,927 | 13,407 | 166,437 | 140.8 MB |
| MatrixGoldPlugin.rhp | 382 | 3,028 | 1,393 | 20,292 | 21.0 MB |
| SharedTypes.dll | 156 | 986 | — | — | 4.3 MB |
| MatrixCommon.dll | 233 | 1,295 | — | — | 3.8 MB |
| Common.dll | 188 | 1,353 | — | — | 4.7 MB |
| CSGemInstance.dll | 103 | 484 | — | — | 8.7 MB |
| CSMaterials.dll | 12 | 103 | — | — | 0.7 MB |
| CSRingSizes.dll | 33 | 153 | 70 | 975 | 0.8 MB |
| GVBuilders.dll | 93 | 145 | — | — | 10.5 MB |
| GemvisionGeometry.dll | 66 | 414 | — | — | 4.6 MB |
| Viewport2D.dll | 86 | 1,114 | — | — | 6.2 MB |
| CSDatas.dll | 56 | 612 | — | — | 3.0 MB |
| **Total** | **3,977** | **31,875** | — | — | **308 MB** |

Machine-readable: `members-index.csv` (counts, sizes, SHA-256) and `artifact-index.csv`.

## Why a local tool patch exists

The stock constant is `MAX_METADATA_REPRESENTATION_BYTES = 64 * 1024 * 1024` in two build files. It is not exposed as a CLI option or environment variable. CS, CSBlocks and MatrixGold exceeded it during member decoding, producing the resource-limit stubs.

The local copy raises the constant to **1 GiB**:

* `dist/dotnet/ManagedDecodeBudget.js`
* `dist/cli-runtime/ManagedSnapshot-C5h4avgc.js`

`rea-budget.patch` is the exact unified diff; `*.orig` files are kept beside each patched file. Only admission capacity changed — metadata, signatures and CIL anchors are unmodified. `NODE_OPTIONS=--max-old-space-size=12288` is set during capture.

## Reproduce

```powershell
# all 14 artifact records, then all 14 complete member bundles
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\rea-evidence.ps1
```

`*.members-summary.json` is the CLI's summary stdout; `*.members.json` is the complete Evidence bundle. The capture loop deletes an existing bundle before re-capturing it.
