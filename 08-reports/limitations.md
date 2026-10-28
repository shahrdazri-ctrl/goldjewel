# Limitations & Residual Risk Register

Honest statement of what this program does **not** establish, and what to do about each item.

| # | Limitation | Impact | Mitigation / next step |
|---|---|---|---|
| 1 | **No PDBs ship with the product.** | No original line numbers; decompiled C# line numbers are ILSpy's, not the vendor's. | All citations use type/method names + IL metadata + file paths. Dossier claims are traceable via `symbols.sqlite`. |
| 2 | **Method names are SmartAssembly-mangled** inside the core assemblies (`\u0001`, `\u0002`). | Algorithm *bodies* are readable but not self-describing; some private helpers cannot be named from metadata alone. | Semantics reconstructed from public signatures, properties, string literals, call graph and the readable helper assemblies (`CSUtil*`, `GemvisionGeometry`). Anything still ambiguous is flagged in its dossier. |
| 3 | **Type-name mangling is 55.2 %** in `MatrixGold.exe`. | Some UI/support types are anonymous. | UI semantics recovered from XAML x:Class + bindings (4,205 facts), which survive. |
| 4 | **Runtime observation was authorised but not executed** in this pass. | Numeric constants inside heavily-mangled geometry loops (tolerances, blend factors) are inferred from code, not measured. | Use the prepared Frida approach on the local licensed copy: hook `CSBlock.Update`, log inputs/outputs, diff against the port. Treat as the verification phase, not discovery. |
| 5 | **Swift toolchain is not installed on this machine.** | `JewelryKit` was not compiled here. | Ring-size logic validated in Python against **7,005 executed vectors** and **565/565** formula parity. A GitHub Actions macOS workflow is included; run `swift test` on macOS before shipping. |
| 6 | **Gem size tables are documented, not yet extracted.** | The iOS team has the schema and shape list but not the numeric rows. | Top of the extraction backlog (Dossier 06 §7, Dossier 08 §6). Reuse the proven `RingVectors` harness pattern. |
| 7 | **Localization strings are documented, not yet exported.** | 3,461 accessors and 18 locales identified; values not dumped. | Backlog item 2. Reflect the generated `Strings` accessors and pair with shipped `.resources`. |
| 8 | **openNURBS boolean availability is unverified.** | The iOS geometry stack recommendation depends on it. | Verify before committing to openNURBS: the open SDK provides B-rep structures; `BrepBoolean` may be Rhino-only. Fallback: exact-predicate mesh booleans on tessellated solids (acceptable for cutters only). |
| 9 | **Licensing/auth code is deliberately out of scope.** | No account, entitlement or package logic is described. | Implement your own (Sign in with Apple + StoreKit 2). Dossier 01 §6 states the boundary. |
| 10 | **Content assets are licensed, not transferable.** | 903 `.3dm`, 257 `.mgm`, 25 `.mgstyle`, 61 `.pat` cannot be shipped as-is. | Ship your own licensed content; export only schemas and generated numeric tables. |
| 11 | **USB volume instability.** | The D: Micron SSD dropped out twice during analysis; large single writes occasionally truncated. | All artefacts were written in verified chunks and re-read. Re-run `validate_handoff.py` if the drive was disconnected mid-session. |
| 12 | **No git repository exists** for the lab or the target. | The mission's commit/PR/merge step has no target. | The lab is a filesystem deliverable on D:. If version control is wanted, initialise a repo *excluding* licensed binaries (`01-target/mirror`, `03-decompiled/raw`) and commit only dossiers, scripts and the Swift package. |

## Fidelity ceiling, stated plainly

An iOS app built from these dossiers can reproduce: document format, ring sizing, block graph, node taxonomy, material model, UI interaction model and the geometry API contract. It will **not** be bit-identical on first implementation for sweep-heavy constructions (prong rails, bezels, halos), because those algorithms are the vendor's core IP expressed in obfuscated code with Rhino-specific tolerances. Closing that gap requires the runtime-diff loop in item 4, block by block.

That is the honest definition of "same calibre": same architecture, same data contracts, same node vocabulary, verified numerics where they are deterministic (ring sizing, gem tables), and a measurement loop for the rest.
