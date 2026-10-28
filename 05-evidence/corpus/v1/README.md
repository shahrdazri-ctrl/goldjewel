# Oracle corpus v1

IL-level ground truth for the two builders that the first Swift geometry port
depends on: the head/basket builder and the prong family.

| File | Types | Methods | Instructions | Strings | Numeric constants | Call edges |
|---|---:|---:|---:|---:|---:|---:|
| `head-builder.il.json` | 35 | 185 | 43,207 | 84 | 1,576 | 11,289 |
| `prong-family.il.json` | 7 | 49 | 14,839 | 64 | 628 | 3,207 |

Assembly: `CSBlocks.mgp`, SHA-256 `ddd92dc8c7e53ba3…` (3,070,976 bytes), the
GUID-named plugin bundle mapped through `03-decompiled/il-index.csv`.

## What this is

Every record is read from the shipped IL with Mono.Cecil. Nothing is inferred
from behaviour, because **nothing was executed**:

> `CSBlocks.mgp` is a mixed-mode Rhino plugin. Loading it outside Rhino fails in
> `Rhino_DotNet.dll` initialisation with `0x8007045A` (`ERROR_DLL_INIT_FAILED`).
> The probe that established this is recorded in `08-reports/limitations.md`.

That limitation is why the corpus records IL operands rather than geometry:
strings (`ldstr`), numeric constants (`ldc.*`, including `NaN`/infinity encoded
as named strings because JSON has no number form for them), call edges
(`call`/`callvirt`/`newobj`/`ldftn`), field accesses, parameter defaults,
constant fields, enum values, attributes and every method signature — all with
IL offsets, so any claim can be re-checked against the binary.

## Schema

`schema: goldjewel.oracle.corpus/1`. Top level: `assembly` (name, version,
SHA-256, bytes, MVID), `targets` (type prefixes), `mode`
(`il-static-no-execution`), `execution` (status and the reason above), `summary`
and `types`.

Each type carries `full_name`, base type, interfaces, attributes, enum values,
fields (with `const`), properties, `decompiled_paths` and `methods`. Each method
carries its signature, access, static/virtual/abstract flags, attributes,
parameters (with defaults) and `body`: instruction count, max stack, exception
handlers, `strings`, `constants`, `calls`, `field_access`.

`decompiled_paths` links a record to the ILSpy output under
`03-decompiled/raw/CSBlocks`, which is where the algorithm is read and the Swift
port is written from.

Hashes are SHA-256 over canonical LF text (`hash_mode` in the manifest), because
the .NET writer emits CRLF on Windows while Git stores the blob with LF. The raw
on-disk hash is recorded too, and only the canonical hash is verified in CI.

## Scope, stated plainly

* The head corpus is the `CSBlocks.Settings.Heads.CSHeadBuilderV2` subtree (35
  types, including compiler-generated closures).
* The prong corpus is the `CSProng`, `CSProngPlacerGC`, `CSClusterProngPlacer`
  and `CSProngOnSurface` families, plus `CSProngPlacerSetup` (7 types total).
* These are 2 of the 408 current-generation block types. The remaining families
  are captured milestone by milestone; `08-reports/triage-ledger.csv` already
  classifies all 50,134 first-party methods, and `08-reports/capability-matrix.csv`
  names the 88 operations in the v1 surface.

Type prefixes can match siblings (`CSProng` also selects `CSProngPlacerSetup`
and `CSProngOnSurface`). That is deliberate for the prong family, and recorded
in `targets` so the scope is never implicit.

## Reproduce

```bash
python Tools/m2.py            # licensed Windows machine with the D: mirror
python Tools/m2.py --check    # any machine: validates schema, hashes and scope
```

`Tools/build_corpus.py` builds `Tools/oracle/OracleCapture`, resolves the
assembly through the IL index, proves the write guard by asking the harness to
write to `C:\REA-LAB-guard-test.json` and requiring exit code 3 with no file
created, then captures both corpora and records the audit in `manifest.json`.
