#!/usr/bin/env python3
"""Capture oracle corpus v2 from the shipped first-party IL.

V1 covered the head-builder namespace and the prong family in CSBlocks. V2 adds
the helpers those families call and the halo/cluster placement types:

  CSBlockUtil        CSUtilCurves, CSUtilSweepRC, CSUtilGeometry, CSUtilMath
  CSBlockDataUtils   GemOffsetCurve
  CSBlocks           head builder, GemClusters (halo/cluster/shapes)
  CSGemInstance      CSGemInstanceDefinition and its ProngPosition seats
  CSDatas            CSGemData and the gem-data model

RhinoCommon is not in the mirrored product; Brep/BrepSurface/Revolve calls are
recorded as call edges and documented semantics, not as captured vendor IL.

  python Tools/build_corpus_v2.py           capture (Windows, licensed mirror)
  python Tools/build_corpus_v2.py --check   verify committed corpus only
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL_DIR = os.path.join(ROOT, "Tools", "oracle", "OracleCapture")
TOOL_DLL = os.path.join(TOOL_DIR, "bin", "Release", "net8.0", "OracleCapture.dll")
CORPUS_DIR = os.path.join(ROOT, "05-evidence", "corpus", "v2")
LOG_DIR = os.path.join(ROOT, "09-logs")
MANIFEST = os.path.join(CORPUS_DIR, "manifest.json")
SCHEMA = "goldjewel.oracle.corpus/2"

TARGETS = {
    "csblockutil": (
        "CSBlockUtil",
        [
            "CSBlockUtil.CSUtilCurves",
            "CSBlockUtil.CSUtilSweepRC",
            "CSBlockUtil.CSUtilGeometry",
            "CSBlockUtil.CSUtilMath",
        ],
    ),
    "csblockdatautils": (
        "CSBlockDataUtils",
        ["CSBlockDataUtils.CSGemOffsetCurves"],
    ),
    "csblocks-families": (
        "CSBlocks",
        [
            "CSBlocks.Settings.Heads.CSHeadBuilderV2",
            "CSBlocks.GemClusters",
            "CSBlocks.Settings.CSClusterProngPlacer",
        ],
    ),
    "csgeminstance": ("CSGemInstance", ["CSGemInstance"]),
    "csdatas": ("CSDatas", ["CSDatas"]),
}


def rel(path: str) -> str:
    return os.path.relpath(path, ROOT).replace("\\", "/")


def sha256(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_lf(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read().replace(b"\r\n", b"\n")).hexdigest()


def tool_env() -> dict:
    env = os.environ.copy()
    env.update(
        {
            "NUGET_PACKAGES": os.path.join(ROOT, "02-toolchain", "nuget"),
            "DOTNET_CLI_HOME": os.path.join(ROOT, "02-toolchain", "dotnet-home"),
            "TMP": os.path.join(ROOT, "02-toolchain", "tmp"),
            "TEMP": os.path.join(ROOT, "02-toolchain", "tmp"),
            "DOTNET_NOLOGO": "1",
            "DOTNET_CLI_TELEMETRY_OPTOUT": "1",
            "DOTNET_SKIP_FIRST_TIME_EXPERIENCE": "1",
        }
    )
    for key in ("NUGET_PACKAGES", "DOTNET_CLI_HOME", "TMP", "TEMP"):
        os.makedirs(env[key], exist_ok=True)
    return env


def dotnet() -> str:
    found = shutil.which("dotnet")
    if found:
        return found
    candidate = r"C:\Program Files\dotnet\dotnet.exe"
    if os.path.exists(candidate):
        return candidate
    raise SystemExit("dotnet not found")


def resolve_assembly(assembly: str) -> tuple[str, str]:
    il_dir = os.path.join(ROOT, "03-decompiled", "il", assembly)
    if not os.path.isdir(il_dir):
        raise SystemExit(f"missing IL directory for {assembly}")
    files = sorted(f for f in os.listdir(il_dir) if f.endswith(".il"))
    if not files:
        raise SystemExit(f"missing IL for {assembly}")
    stem = os.path.splitext(files[0])[0]

    mirror = os.path.join(ROOT, "01-target", "mirror")
    candidates: list[str] = []
    for dirpath, _dirs, names in os.walk(mirror):
        for ext in (".dll", ".mgp"):
            name = stem + ext
            if name in names:
                candidates.append(os.path.join(dirpath, name))
    if not candidates:
        raise SystemExit(f"missing assembly for {assembly}: {stem}")
    # Prefer the managed DLL when both a DLL and a plugin bundle exist.
    candidates.sort(key=lambda p: (not p.lower().endswith(".dll"), p))
    return candidates[0], os.path.join(il_dir, files[0])


def run(cmd: list[str], env: dict, log: str) -> int:
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(log, "w", encoding="utf-8") as fh:
        proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=fh, stderr=subprocess.STDOUT, text=True)
    return proc.returncode


def capture(check: bool) -> int:
    if check:
        return check_corpus()

    if not os.path.exists(TOOL_DLL):
        print("building OracleCapture")
        env = tool_env()
        code = run(
            [dotnet(), "build", TOOL_DIR, "-c", "Release", "-v", "m"],
            env,
            os.path.join(LOG_DIR, "corpus-v2-build.log"),
        )
        if code != 0:
            print(f"build failed ({code}); see 09-logs/corpus-v2-build.log", file=sys.stderr)
            return 1

    env = tool_env()
    os.makedirs(CORPUS_DIR, exist_ok=True)

    guard_path = r"C:\REA-LAB-v2-guard-test.json"
    guard_code = subprocess.run(
        [dotnet(), TOOL_DLL, next(iter(resolve_assembly("CSBlocks"))), guard_path,
         "CSBlocks.Settings.Heads.CSHeadBuilderV2"],
        cwd=ROOT, env=env, capture_output=True, text=True,
    ).returncode
    if guard_code != 3 or os.path.exists(guard_path):
        print(f"D: guard failed: exit={guard_code} file={os.path.exists(guard_path)}", file=sys.stderr)
        return 1

    assemblies: dict[str, dict] = {}
    corpora: dict[str, dict] = {}
    for name, (assembly, prefixes) in TARGETS.items():
        assembly_path, il_path = resolve_assembly(assembly)
        assemblies[assembly] = {
            "name": assembly,
            "file": rel(assembly_path),
            "sha256": sha256(assembly_path),
            "bytes": os.path.getsize(assembly_path),
            "il": rel(il_path),
        }
        out = os.path.join(CORPUS_DIR, f"{name}.il.json")
        log = os.path.join(LOG_DIR, f"corpus-v2-{name}.log")
        code = run([dotnet(), TOOL_DLL, assembly_path, out, *prefixes], env, log)
        if code != 0:
            print(f"capture {name} failed ({code}); see {rel(log)}", file=sys.stderr)
            with open(log, encoding="utf-8", errors="replace") as fh:
                print(fh.read()[-3000:], file=sys.stderr)
            return 1
        payload = json.load(open(out, encoding="utf-8"))
        corpora[name] = {
            "assembly": assembly,
            "path": rel(out),
            "sha256": sha256_lf(out),
            "sha256_raw": sha256(out),
            "bytes": os.path.getsize(out),
            "targets": prefixes,
            "summary": payload["summary"],
        }
        print(f"{name}: {payload['summary']}")

    manifest = {
        "schema": SCHEMA,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "il-static-no-execution",
        "hash_mode": "sha256 over canonical LF text; sha256_raw is the on-disk bytes",
        "execution": {
            "status": "not-run",
            "reason": (
                "CSBlocks.mgp and its helper DLLs are Rhino assemblies. Loading CSBlocks outside "
                "Rhino fails in Rhino_DotNet.dll initialisation with 0x8007045A "
                "(ERROR_DLL_INIT_FAILED). No vendor method is executed; IL operands are the "
                "ground truth. RhinoCommon is not in the mirrored product."
            ),
        },
        "assemblies": assemblies,
        "corpora": corpora,
        "d_only": {
            "policy": "All writes resolve under D:; the harness refuses any other output root.",
            "guard": {"attempted": guard_path, "exit_code": guard_code, "refused": True},
        },
    }
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n")
    read_back = json.load(open(MANIFEST, encoding="utf-8"))
    if set(read_back.get("corpora", {})) != set(corpora):
        print("manifest read-back does not match the captured corpora", file=sys.stderr)
        return 1
    print(f"wrote {rel(MANIFEST)}")
    return 0


def check_corpus() -> int:
    failures: list[str] = []
    if not os.path.exists(MANIFEST):
        print(f"missing manifest: {rel(MANIFEST)}", file=sys.stderr)
        return 1
    manifest = json.load(open(MANIFEST, encoding="utf-8"))
    if manifest.get("schema") != SCHEMA:
        failures.append(f"manifest schema {manifest.get('schema')!r}")
    if manifest.get("mode") != "il-static-no-execution":
        failures.append("manifest mode must record that no vendor code executed")
    if manifest["execution"]["status"] != "not-run":
        failures.append("execution status must stay not-run")
    if not manifest.get("d_only", {}).get("guard", {}).get("refused"):
        failures.append("D: guard not recorded as refused")

    total_types = 0
    for name, (assembly, prefixes) in TARGETS.items():
        record = manifest.get("corpora", {}).get(name)
        if not record:
            failures.append(f"{name}: missing from manifest")
            continue
        if record.get("assembly") != assembly:
            failures.append(f"{name}: assembly {record.get('assembly')!r} != {assembly!r}")
        path = os.path.join(ROOT, record["path"])
        if not os.path.exists(path):
            failures.append(f"{name}: missing {record['path']}")
            continue
        if sha256_lf(path) != record["sha256"]:
            failures.append(f"{name}: sha256 does not match manifest")
        payload = json.load(open(path, encoding="utf-8"))
        if payload.get("schema") != "goldjewel.oracle.corpus/1":
            failures.append(f"{name}: payload schema {payload.get('schema')!r}")
        names = {t["full_name"] for t in payload["types"]}
        missing = [p for p in prefixes if not any(n.startswith(p) for n in names)]
        if missing:
            failures.append(f"{name}: targets absent {missing}")
        if payload["summary"]["methods"] == 0 or payload["summary"]["instructions"] == 0:
            failures.append(f"{name}: empty capture")
        total_types += payload["summary"]["types"]
        print(
            f"{name}: {payload['summary']['types']} types, "
            f"{payload['summary']['methods']} methods, "
            f"{payload['summary']['strings']} strings, "
            f"{payload['summary']['numeric_constants']} constants"
        )

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print(f"corpus v2 ok: {len(TARGETS)} files, {total_types} types, hashes match")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify committed corpus, no capture")
    args = parser.parse_args()
    return capture(args.check)


if __name__ == "__main__":
    raise SystemExit(main())
