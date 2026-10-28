# REA-LAB — MatrixGold reverse-engineering lab

Everything for this program lives here, on `D:`. Start with:

**[`08-reports/00-INDEX.md`](08-reports/00-INDEX.md)** — what was delivered, how to read it, how to reproduce it.

Quick map:

| Path | Contents |
|---|---|
| `00-control/` | environment, containment, mirror, decompile, BAML, evidence, cleanup scripts |
| `01-target/mirror/` | frozen read-only copy of the install + SHA-256 manifest |
| `02-toolchain/` | Node, REA, ILSpy, SymbolScan, BamlTool, RingVectors harness |
| `03-decompiled/` | 2,943 C# files + 117 XAML files |
| `04-index/` | SQLite symbol ledger, binding inventory, validation scripts |
| `05-evidence/` | REA PE/CLI bundles + 7,005 executed ring-size vectors |
| `06-dossiers/` | the eight implementation-grade dossiers |
| `07-ios-handoff/` | schema-verified Swift package (`JewelryKit`) + CI compile gate |
| `08-reports/` | index, coverage, limitations, C: cleanup proof |
| `09-logs/` | install/decompile/cleanup logs |

Verification: `python 04-index/validate_handoff.py` (expects 0 failures).
