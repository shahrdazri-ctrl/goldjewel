#!/usr/bin/env python3
"""Capture oracle corpus v1 from the shipped CSBlocks IL.

The corpus is produced by Tools/oracle/OracleCapture, which reads metadata and
IL with Mono.Cecil and executes no vendor code. Each corpus file records every
type, method, parameter default, string literal, numeric constant, call edge and
field access for its target types, with IL offsets, plus the SHA-256 of the
assembly it came from.

  python Tools/build_corpus.py           capture (Windows, licensed mirror)
  python Tools/build_corpus.py --check   verify committed corpus only

Capture is reproducible on the machine that holds the licensed mirror. `--check`
runs anywhere and is what CI executes: it validates the schema, the recorded
hashes, the target types and the D:-only audit that capture wrote.
"""
from __future__ import annotations

import argparse
import csv
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
CORPUS_DIR = os.path.join(ROOT, "05-evidence", "corpus", "v1")
LOG_DIR = os.path.join(ROOT, "09-logs")
MANIFEST = os.path.join(CORPUS_DIR, "manifest.json")

SCHEMA = "goldjewel.oracle.corpus/1"

TARGETS = {
    "head-builder": ["CSBlocks.Settings.Heads.CSHeadBuilderV2"],
    "prong-family": [
        "CSBlocks.Settings.CSProngPlacerGC",
        "CSBlocks.Settings.CSProng",
        "CSBlocks.Settings.CSClusterProngPlacer",
    ],
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
    """Hash the text with canonical LF endings.

    The .NET writer emits CRLF on Windows and Git normalises the blob to LF, so
    the checked-out bytes differ by platform. The manifest must verify on both,
    so text artefacts are hashed over their canonical LF form.
    """
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


def resolve_assembly() -> tuple[str, str]:
    """Locate CSBlocks.mgp through the IL index, never by guessing a filename."""
    index = os.path.join(ROOT, "03-decompiled", "il-index.csv")
    if not os.path.exists(index):
        raise SystemExit(f"missing IL index: {index}")
    with open(index, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    row = next((r for r in rows if r["assembly"] == "CSBlocks"), None)
    if row is None:
        raise SystemExit("CSBlocks missing from IL index")

    il_dir = os.path.join(ROOT, "03-decompiled", "il", "CSBlocks")
    il_files = [f for f in os.listdir(il_dir) if f.endswith(".il")] if os.path.isdir(il_dir) else []
    if not il_files:
        raise SystemExit(f"missing IL for CSBlocks in {il_dir}")
    stem = os.path.splitext(il_files[0])[0]

    mirror = os.path.join(ROOT, "01-target", "mirror", "Main")
    candidate = os.path.join(mirror, f"{stem}.mgp")
    if not os.path.exists(candidate):
        for dirpath, _dirs, files in os.walk(mirror):
            if f"{stem}.mgp" in files:
                candidate = os.path.join(dirpath, f"{stem}.mgp")
                break
    if not os.path.exists(candidate):
        raise SystemExit(f"missing plugin bundle for CSBlocks: {stem}.mgp")
    return candidate, os.path.join(il_dir, os.path.basename(il_files[0]))


def snapshot(root: str, limit: int = 50_000) -> dict:
    if not os.path.isdir(root):
        return {"path": root, "exists": False, "files": 0, "bytes": 0, "truncated": False}
    files = 0
    total = 0
    truncated = False
    for dirpath, _dirs, names in os.walk(root):
        for name in names:
            if files >= limit:
                truncated = True
                break
            try:
                total += os.path.getsize(os.path.join(dirpath, name))
                files += 1
            except OSError:
                continue
        if truncated:
            break
    return {"path": root, "exists": True, "files": files, "bytes": total, "truncated": truncated}


def c_only_roots() -> list[str]:
    home = os.path.expanduser("~")
    local = os.environ.get("LOCALAPPDATA", os.path.join(home, "AppData", "Local"))
    return [
        os.path.join(home, ".dotnet"),
        os.path.join(home, ".nuget"),
        os.path.join(local, "Temp"),
    ]


def temp_canary() -> list[str]:
    local = os.environ.get("LOCALAPPDATA", os.path.join(os.path.expanduser("~"), "AppData", "Local"))
    temp = os.path.join(local, "Temp")
    if not os.path.isdir(temp):
        return []
    hits = []
    for name in os.listdir(temp):
        lower = name.lower()
        if ("oraclecapture" in lower or "goldjewel-corpus" in lower) and not lower.endswith(".log"):
            hits.append(name)
    return sorted(hits)


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
        code = run([dotnet(), "build", TOOL_DIR, "-c", "Release", "-v", "m"],
                   env, os.path.join(LOG_DIR, "corpus-build.log"))
        if code != 0:
            print(f"build failed ({code}); see 09-logs/corpus-build.log", file=sys.stderr)
            return 1

    assembly, il_file = resolve_assembly()
    env = tool_env()
    os.makedirs(CORPUS_DIR, exist_ok=True)

    before = {root: snapshot(root) for root in c_only_roots()}
    canary_before = temp_canary()

    guard_path = r"C:\REA-LAB-guard-test.json"
    guard_code = subprocess.run(
        [dotnet(), TOOL_DLL, assembly, guard_path, TARGETS["head-builder"][0]],
        cwd=ROOT, env=env, capture_output=True, text=True,
    ).returncode
    if guard_code != 3 or os.path.exists(guard_path):
        print(f"D: guard failed: exit={guard_code} file={os.path.exists(guard_path)}", file=sys.stderr)
        return 1

    wrote = {}
    for name, prefixes in TARGETS.items():
        out = os.path.join(CORPUS_DIR, f"{name}.il.json")
        log = os.path.join(LOG_DIR, f"corpus-{name}.log")
        code = run([dotnet(), TOOL_DLL, assembly, out, *prefixes], env, log)
        if code != 0:
            print(f"capture {name} failed ({code}); see {rel(log)}", file=sys.stderr)
            with open(log, encoding="utf-8", errors="replace") as fh:
                print(fh.read()[-2000:], file=sys.stderr)
            return 1
        payload = json.load(open(out, encoding="utf-8"))
        wrote[name] = {
            "path": rel(out),
            "sha256": sha256_lf(out),
            "sha256_raw": sha256(out),
            "bytes": os.path.getsize(out),
            "targets": prefixes,
            "summary": payload["summary"],
        }
        print(f"{name}: {payload['summary']}")

    after = {root: snapshot(root) for root in c_only_roots()}
    canary_after = temp_canary()
    violations = []
    for root in after:
        b, a = before[root], after[root]
        if (a["files"], a["bytes"]) != (b["files"], b["bytes"]):
            violations.append({"root": root, "before": b, "after": a})
    new_canaries = sorted(set(canary_after) - set(canary_before))
    if new_canaries:
        violations.append({"root": "temp-canary", "new": new_canaries})

    manifest = {
        "schema": SCHEMA,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "il-static-no-execution",
        "hash_mode": "sha256 over canonical LF text; sha256_raw is the on-disk bytes",
        "execution": {
            "status": "not-run",
            "reason": (
                "CSBlocks.mgp is a mixed-mode Rhino plugin. Loading it outside Rhino fails in "
                "Rhino_DotNet.dll initialisation with 0x8007045A (ERROR_DLL_INIT_FAILED). No vendor "
                "method is executed by this capture; IL operands are the ground truth."
            ),
        },
        "assembly": {
            "name": "CSBlocks",
            "file": rel(assembly),
            "sha256": sha256(assembly),
            "bytes": os.path.getsize(assembly),
            "il": rel(il_file),
        },
        "tool": {
            "name": "OracleCapture",
            "dll": rel(TOOL_DLL),
            "dotnet": subprocess.run([dotnet(), "--version"], env=env, capture_output=True,
                                     text=True).stdout.strip(),
            "captured_on": sys.platform,
        },
        "corpora": wrote,
        "d_only": {
            "policy": "All writes resolve under D:; the harness refuses any other output root.",
            "guard": {"attempted": guard_path, "exit_code": guard_code, "refused": True},
            "roots_before": list(before.values()),
            "roots_after": list(after.values()),
            "violations": violations,
        },
    }

    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    with open(MANIFEST, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)

    if violations:
        print(f"D:-only audit found {len(violations)} violation(s); see {rel(MANIFEST)}", file=sys.stderr)
        return 1
    print(f"wrote {rel(MANIFEST)}")
    return 0


def check_corpus() -> int:
    failures = []
    if not os.path.exists(MANIFEST):
        print(f"missing manifest: {rel(MANIFEST)}", file=sys.stderr)
        return 1
    manifest = json.load(open(MANIFEST, encoding="utf-8"))

    if manifest.get("schema") != SCHEMA:
        failures.append(f"manifest schema {manifest.get('schema')!r}")
    if manifest.get("mode") != "il-static-no-execution":
        failures.append("manifest mode must record that no vendor code executed")
    if manifest["execution"]["status"] != "not-run":
        failures.append("execution status must stay not-run until a Rhino-hosted capture exists")
    if not manifest.get("d_only", {}).get("guard", {}).get("refused"):
        failures.append("D: guard not recorded as refused")
    if manifest.get("d_only", {}).get("violations"):
        failures.append(f"D: audit violations recorded: {len(manifest['d_only']['violations'])}")

    total_types = 0
    for name, prefixes in TARGETS.items():
        record = manifest.get("corpora", {}).get(name)
        if not record:
            failures.append(f"{name}: missing from manifest")
            continue
        path = os.path.join(ROOT, record["path"])
        if not os.path.exists(path):
            failures.append(f"{name}: missing {record['path']}")
            continue
        if sha256_lf(path) != record["sha256"]:
            failures.append(f"{name}: sha256 does not match manifest")
        payload = json.load(open(path, encoding="utf-8"))
        if payload.get("schema") != SCHEMA:
            failures.append(f"{name}: schema {payload.get('schema')!r}")
        names = {t["full_name"] for t in payload["types"]}
        missing = [p for p in prefixes if not any(n.startswith(p) for n in names)]
        if missing:
            failures.append(f"{name}: targets absent {missing}")
        if payload["summary"]["methods"] == 0 or payload["summary"]["instructions"] == 0:
            failures.append(f"{name}: empty capture")
        total_types += payload["summary"]["types"]
        print(f"{name}: {payload['summary']['types']} types, "
              f"{payload['summary']['methods']} methods, "
              f"{payload['summary']['strings']} strings, "
              f"{payload['summary']['numeric_constants']} constants")

    if failures:
        for failure in failures:
            print(f"FAIL {failure}", file=sys.stderr)
        return 1
    print(f"corpus ok: {len(TARGETS)} files, {total_types} types, hashes match")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="verify committed corpus, no capture")
    args = parser.parse_args()
    return capture(args.check)


if __name__ == "__main__":
    raise SystemExit(main())
