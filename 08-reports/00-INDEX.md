# REA-LAB — MatrixGold 3.1 Reverse-Engineering Lab

**Target:** `D:\MAIN SOFTWARE\jewerly software\matrix gold\Gemvision.MatrixGold\Main\MatrixGold`
**Build:** MatrixGold 3.1.22284.1001, .NET Framework 4.8, WPF, Rhino 7 plugin
**Lab root:** `D:\REA-LAB` (all toolchain, caches, decompilation and reports live here)
**Deliverable:** eight implementation-grade dossiers + a schema-verified Swift package for iPadOS (compile gate in CI)

---

## Read this first

| If you are… | Read |
|---|---|
| The iOS architect | `06-dossiers/01` -> `02` -> `03` -> `05` -> `04` -> `06` -> `07` -> `08` |
| Starting implementation tomorrow | `07-ios-handoff/JewelryKit` (working package) + `06-dossiers/05` (engine contract) |
| Reviewing fidelity claims | `08-reports/coverage-report.md` + `08-reports/limitations.md` |
| Reproducing the analysis | `00-control/*.ps1`, `04-index/*.py` (each dossier ends with its queries) |

---

## Deliverables

### Dossiers (`06-dossiers/`)
1. `01-application-shell.md` — two-process architecture, startup, 254-operation service contract, licensing boundary.
2. `02-document-model-persistence.md` — **designs are JSON/gzip**, exact file format and schema, import/GUID remap, undo.
3. `03-presentation-layer.md` — 4,205 binding facts, 117 XAML files, screen weights, the single `CommandUpdateGraphFromUI` contract, SwiftUI architecture.
4. `04-geometry-kernel.md` — Rhino call profile, Clipper 2D layer, NURBS contract, transform nodes, tolerance model, iOS kernel options.
5. `05-parametric-construction.md` — the block graph contract, 408-node taxonomy (731 with legacy), head/prong/bezel/halo algorithms, cutters, JSON persistence, porting order.
6. `06-gems-and-materials.md` — versioned gem size tables, 55-field `.mgm` material model, metal identity, specific gravity, PBR mapping.
7. `07-ring-sizing.md` — 22 regions, exact closed-form formulas, table semantics, **7,005 executed golden vectors**.
8. `08-content-localization-settings.md` — 81 patchwire vocabulary, content taxonomy, 18 locales, settings that change behaviour, extraction backlog.

### Swift package (`07-ios-handoff/JewelryKit`)
`Package.swift` (iOS 17 / macOS 14), `RingSizing` (22 regions, 7,005 sizes, banker's rounding), `MaterialIO` (`MGMaterial` Codable, 257/257 corpus conformance checked on Windows), `JewelryDomain`, `ParametricKit`, tests with real `.mgm` fixtures, GitHub Actions workflow. Compilation has not been run locally; the workflow is the gate.

### Evidence (`04-index`, `05-evidence`)
* `symbols.sqlite` — 225 managed assemblies, 35,645 types, 303,780 methods, 75,497 properties, 155,009 fields, 91,902 strings, 1,379,497 call edges.
* `xaml-bindings.csv` — 4,205 binding/command facts from 117 decompiled BAML files.
* `05-evidence/vectors/ring-sizes.json` — 7,005 sizes executed from the real assembly.
* `05-evidence/rea/` — PE/CLI evidence bundles for the 14 core assemblies, all `coverage=complete` (31,875 methods).
* `03-decompiled/il/` — per-assembly CIL for all 35 first-party assemblies (41,460 `.method` directives, 111.6 MB).

---

## Reproduce

```powershell
# 1. environment (D: only)
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\env.ps1

# 2. symbol index + ledger
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\analyze-index.ps1
python D:\REA-LAB\04-index\build_ledger.py

# 3. decompile + XAML
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\decompile.ps1
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\emit-il.ps1
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\00-control\baml.ps1
python D:\REA-LAB\04-index\xaml_bindings.py

# 4. golden vectors + validation
powershell -ExecutionPolicy Bypass -File D:\REA-LAB\02-toolchain\RingVectors\build.ps1
python D:\REA-LAB\04-index\validate_handoff.py
```

---

## Ground truth

* Target frozen read-only at `01-target/mirror`; `01-target/target-manifest.csv` holds SHA-256 per file (2,688 files, 1.81 GiB).
* No PDBs ship with the product: dossiers cite **types, methods, IL evidence and file paths**, never invented source line numbers.
* Obfuscation: Red Gate SmartAssembly. Method names are mangled; **namespaces, type names (44.8 %), property names, field names, strings, XAML and all data formats survive**. Dossiers are built on the surviving surface plus call-graph and behavioural evidence.
* Licensing/auth code is a stated boundary and is not analysed (Dossier 01, section 6).
