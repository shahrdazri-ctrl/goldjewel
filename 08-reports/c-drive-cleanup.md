# C: Drive Footprint — Cleanup and Proof

Policy for this program: **all toolchain, caches, temp and work output live on D:**. C: was touched only to read the pre-existing Freebuff config for measurement and to delete the approved stale temp data.

## 1. What was deleted (approved scope)

| Target | Path | Size |
|---|---|---:|
| Frida temp dirs | `%LOCALAPPDATA%\Temp\frida-*` (203 dirs) | 12.08 GiB |
| Autodesk ODIS download cache | `%LOCALAPPDATA%\Temp\odis_download_dest` | 1.99 GiB |
| Autodesk rollback backup | `%LOCALAPPDATA%\Temp\AdAppMgrRollBackBackup` | 1.10 GiB |
| **Total** | 205 targets | **16,289,098,760 bytes = 15.17 GiB (16.29 GB)** |

Result (from `00-control/cleanup-result.json`):

```json
{
  "ranAtUtc": "2026-10-28T02:12:00Z",
  "targetCount": 205,
  "freedBytes": 16289098760,
  "freedGiB": 15.17,
  "failedPaths": [],
  "fridaRemaining": 0,
  "odisRemaining": false,
  "adskRemaining": false
}
```

Every deletion was guarded to paths under `%LOCALAPPDATA%\Temp`. No other C: path was removed. No Freebuff config, project, or user document was touched.

## 2. Before / after

| Metric | Before | After | Delta |
|---|---:|---:|---:|
| `%LOCALAPPDATA%\Temp` size | 15.46 GiB | 0.29 GiB | **-15.17 GiB** |
| C: free space | 798.8 GiB | 813.9 GiB | **+15.1 GiB** |
| `frida-*` directories | 203 | 0 | -203 |

## 3. Proof that the lab did not add anything to C:

Measured after all analysis work:

| Candidate C: location | State |
|---|---|
| `%USERPROFILE%\.npm` | absent |
| `%USERPROFILE%\.nuget` | absent |
| `%USERPROFILE%\.dotnet` | absent |
| `%USERPROFILE%\.frida` | absent |
| `%LOCALAPPDATA%\npm-cache` | absent |
| `%APPDATA%\npm-cache` | absent |
| `%LOCALAPPDATA%\REA-LAB` | absent |
| `%USERPROFILE%\.config\freebuff-desktop` | 68.83 MiB — **pre-existing**, unchanged |

How containment was enforced:

* **Node 24.22.1** installed to `D:\REA-LAB\02-toolchain\node`; `npm` prefix `D:\REA-LAB\02-toolchain\npm-global`; npm cache `D:\REA-LAB\02-toolchain\npm-cache`.
* **REA** installed into that prefix (`D:\REA-LAB\02-toolchain\npm-global`), 176 packages, verified with `rea doctor`/`--version` (6.8.0).
* **ILSpy** installed as a local dotnet tool in `D:\REA-LAB\02-toolchain\ilspy`; `NUGET_PACKAGES`, `DOTNET_CLI_HOME`, `TEMP`, `TMP` all redirected to D: (`00-control/env.ps1`).
* **Python** used the system interpreter but wrote only to D: paths.
* Target mirror, decompilation, index, evidence and reports all under `D:\REA-LAB`.

## 4. Re-verify at any time

```powershell
# 1. confirm no frida/autodesk temp remains
Get-ChildItem $env:LOCALAPPDATA\Temp -Directory | Where-Object Name -match 'frida-|odis_download_dest|AdAppMgrRollBackBackup'

# 2. confirm no toolchain residue
@("$env:USERPROFILE\.npm","$env:USERPROFILE\.nuget","$env:USERPROFILE\.dotnet","$env:USERPROFILE\.frida") |
  ForEach-Object { "$_ => $(Test-Path $_)" }

# 3. free space
(Get-PSDrive C).Free / 1GB
```

Expected: no output from (1), all `False` from (2), ~814 GiB from (3).

## 5. Note on the USB volume

`D:` is a 4 TB Micron USB SSD and dropped out twice during the session. Every artefact was written with verification, and the final validation (`validate_handoff.py`) re-read all 7,005 vectors and 257 materials from disk with zero failures. If the drive was physically disconnected after delivery, re-run that script.
