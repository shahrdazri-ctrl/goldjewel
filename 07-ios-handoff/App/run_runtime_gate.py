#!/usr/bin/env python3
"""Run the GoldJewel UI tests on one iPhone and one iPad simulator.

The gate builds the test bundle once, then runs the same runtime test against
each device. A test run that does not finish inside the timeout is treated as a
failure, not as a reason to skip: the simulator is shut down, the run is retried
once after five seconds, and the second failure is reported with the log tail.

Screenshots are XCTAttachments in the result bundle. They are exported to
`build/runtime-evidence/<kind>/` so CI can publish them as artifacts; the run
fails if a passing test produced no screenshots.
"""
from __future__ import annotations

import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone

APP_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(APP_DIR))
BUILD_DIR = os.path.join(APP_DIR, "build")
PROJECT = os.path.join(APP_DIR, "GoldJewel.xcodeproj")
SCHEME = "GoldJewel"
RUN_TIMEOUT = 900
BUILD_TIMEOUT = 900


def _progress_line(line: str) -> bool:
    """Keep the CI console readable while still showing live test progress."""
    markers = ("RUNTIME_STEP", "Test Case", "Test Suite", "error:", "Assertion")
    return any(marker in line for marker in markers)


def run(cmd: list[str], timeout: int, log_path: str | None = None, echo: bool = False):
    """Run a command with a hard timeout, a full log and optional live echoes.

    Reading the pipe in a thread lets the timeout kill a wedged xcodebuild while
    every line still reaches the log. A hung test then shows which RUNTIME_STEP
    it stopped after, instead of only a timeout.
    """
    handle = open(log_path, "w", encoding="utf-8", newline="\n") if log_path else None
    process = subprocess.Popen(
        cmd,
        cwd=APP_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    chunks: list[str] = []

    def pump() -> None:
        if process.stdout is None:
            return
        for line in process.stdout:
            chunks.append(line)
            if len(chunks) > 2000:
                del chunks[:1000]
            if handle is not None:
                handle.write(line)
                handle.flush()
            if echo and _progress_line(line):
                print(line.rstrip(), flush=True)

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(process.pid), signal.SIGTERM)
        try:
            process.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            process.wait(timeout=15)
        code = 124
    reader.join(timeout=10)
    if handle is not None:
        handle.close()
    return code, "".join(chunks)[-12000:]


def compiler_errors(log_path: str) -> list[str]:
    """Return the compiler diagnostics from a full xcodebuild log."""
    try:
        with open(log_path, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
    except OSError:
        return []
    selected = [line.rstrip() for line in lines if "error:" in line]
    if not selected:
        selected = [line.rstrip() for line in lines if "TEST BUILD FAILED" in line]
    return selected[-40:]


def capture(cmd: list[str], timeout: int = 60):
    """Capture a short command's stdout and stderr as one string.

    Device discovery needs the exact bytes simctl printed. It is kept separate
    from the streaming `run`, whose merged line pump is for xcodebuild logs.
    """
    completed = subprocess.run(
        cmd,
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    return completed.returncode, (completed.stdout or "") + (completed.stderr or "")


def simulator_devices() -> list[dict]:
    # CoreSimulatorService can be slow to answer on a cold runner. A hung list
    # is retried a bounded number of times rather than failing the gate or
    # waiting forever.
    code = 1
    output = ""
    for attempt in range(3):
        try:
            code, output = capture(
                ["xcrun", "simctl", "list", "devices", "available", "-j"],
                timeout=120,
            )
        except subprocess.TimeoutExpired:
            print(f"runtime gate: simctl list timed out (attempt {attempt + 1}/3)",
                  file=sys.stderr)
            time.sleep(5)
            continue
        if code == 0:
            break
        print(f"runtime gate: simctl list failed (attempt {attempt + 1}/3, exit {code})",
              file=sys.stderr)
        time.sleep(5)
    else:
        raise RuntimeError(f"simctl list did not answer after 3 attempts: {output[-2000:]}")
    if code != 0:
        raise RuntimeError(f"simctl list failed: {output[-2000:]}")
    try:
        payload = json.loads(output)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"simctl list produced unparseable JSON ({error}): {output[:800]!r}"
        ) from error
    devices = []
    for runtime, entries in payload.get("devices", {}).items():
        if "iOS" not in runtime:
            continue
        version = runtime.rsplit("-", 1)[-1].replace("_", ".")
        for entry in entries:
            if entry.get("isAvailable", True):
                devices.append({
                    "name": entry["name"],
                    "udid": entry["udid"],
                    "runtime": runtime,
                    "version": version,
                })
    return devices


def pick_device(devices: list[dict], kind: str) -> dict:
    token = "iPad" if kind == "ipad" else "iPhone"
    candidates = [device for device in devices if token in device["name"]]
    if not candidates:
        raise RuntimeError(f"no {token} simulator is available")
    candidates.sort(key=lambda device: (device["version"], device["name"]), reverse=True)
    return candidates[0]


def build_for_testing(device: dict) -> None:
    """Build app and XCTest bundles once, for a concrete simulator.

    A generic iOS Simulator destination is enough for a plain build but not for
    a test bundle, so the build targets the same iPhone the runtime test uses.
    The resulting bundle is installed on both device families.
    """
    os.makedirs(BUILD_DIR, exist_ok=True)
    log = os.path.join(BUILD_DIR, "runtime-build.log")
    code, output = run(
        [
            "xcodebuild",
            "build-for-testing",
            "-project", PROJECT,
            "-scheme", SCHEME,
            "-destination", f"platform=iOS Simulator,id={device['udid']}",
            "-derivedDataPath", BUILD_DIR,
            "CODE_SIGNING_ALLOWED=NO",
        ],
        timeout=BUILD_TIMEOUT,
        log_path=log,
    )
    if code != 0:
        errors = compiler_errors(log)
        if errors:
            print("\n".join(errors), file=sys.stderr)
        print(output[-4000:] if output else "")
        print(f"runtime gate: build-for-testing failed (exit {code}); log at {log}", file=sys.stderr)
        raise SystemExit(1)
    print("runtime gate: built test bundle")


def shutdown(udid: str) -> None:
    run(["xcrun", "simctl", "shutdown", udid], timeout=60)


def export_screenshots(result_bundle: str, kind: str) -> list[str]:
    evidence = os.path.join(BUILD_DIR, "runtime-evidence", kind)
    if os.path.isdir(evidence):
        shutil.rmtree(evidence)
    os.makedirs(evidence, exist_ok=True)
    exported = os.path.join(evidence, "attachments")
    code, output = run(
        [
            "xcrun", "xcresulttool", "export", "attachments",
            "--path", result_bundle,
            "--output-path", exported,
        ],
        timeout=180,
    )
    if code != 0:
        print(output[-2000:] if output else "")
        return []
    screenshots = []
    for root, _, files in os.walk(exported):
        for name in files:
            if name.lower().endswith(".png"):
                source = os.path.join(root, name)
                destination = os.path.join(evidence, name)
                shutil.copy2(source, destination)
                screenshots.append(destination)
    return screenshots


def run_device(device: dict, kind: str) -> dict:
    result_bundle = os.path.join(BUILD_DIR, f"runtime-{kind}.xcresult")
    log_path = os.path.join(BUILD_DIR, f"runtime-{kind}.log")
    if os.path.exists(result_bundle):
        shutil.rmtree(result_bundle)

    command = [
        "xcodebuild",
        "test-without-building",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", f"platform=iOS Simulator,id={device['udid']}",
        "-derivedDataPath", BUILD_DIR,
        "-resultBundlePath", result_bundle,
        "-only-testing:GoldJewelUITests/GoldJewelRuntimeTests",
        # Bound a wedged simulator at the xcodebuild level as well as the
        # runner's own process timeout, so one device cannot eat the job.
        "-test-timeouts-enabled", "YES",
        "-default-test-execution-time-allowance", "480",
        "-maximum-test-execution-time-allowance", "600",
        "CODE_SIGNING_ALLOWED=NO",
    ]
    attempt = 1
    code = 1
    while attempt <= 2:
        # A retry must not fail because the previous attempt left a bundle at
        # the result path; xcodebuild refuses to overwrite one.
        if os.path.exists(result_bundle):
            shutil.rmtree(result_bundle)
        print(f"runtime gate: {kind} attempt {attempt} on {device['name']} ({device['udid']})")
        code, output = run(command, timeout=RUN_TIMEOUT, log_path=log_path, echo=True)
        if code == 0:
            break
        print(f"runtime gate: {kind} attempt {attempt} failed (exit {code})")
        if output:
            print(output[-3000:])
        if os.path.exists(log_path):
            with open(log_path, encoding="utf-8", errors="replace") as handle:
                tail = handle.readlines()[-120:]
            print("".join(tail))
        shutdown(device["udid"])
        attempt += 1
        if attempt <= 2:
            time.sleep(5)

    if code != 0:
        # Export what the failing run managed to attach. A red gate should still
        # show the screen it was looking at, not just an assertion message.
        failed_shots = export_screenshots(result_bundle, kind) if os.path.exists(result_bundle) else []
        for path in failed_shots:
            print(f"runtime gate: failure screenshot {os.path.relpath(path, REPO_ROOT)}")
        return {
            "kind": kind,
            "device": device["name"],
            "udid": device["udid"],
            "status": "failed",
            "screenshots": [os.path.relpath(path, REPO_ROOT) for path in failed_shots],
        }

    screenshots = export_screenshots(result_bundle, kind)
    if not screenshots:
        print(f"runtime gate: {kind} passed but exported no screenshots", file=sys.stderr)
        return {
            "kind": kind,
            "device": device["name"],
            "udid": device["udid"],
            "status": "failed-no-screenshots",
            "screenshots": [],
        }
    for path in screenshots:
        print(f"runtime gate: screenshot {os.path.relpath(path, REPO_ROOT)}")
    return {
        "kind": kind,
        "device": device["name"],
        "udid": device["udid"],
        "status": "passed",
        "screenshots": [os.path.relpath(path, REPO_ROOT) for path in screenshots],
    }


def main() -> int:
    os.makedirs(BUILD_DIR, exist_ok=True)
    devices = simulator_devices()
    selected = {
        "iphone": pick_device(devices, "iphone"),
        "ipad": pick_device(devices, "ipad"),
    }
    for kind, device in selected.items():
        print(f"runtime gate: {kind} -> {device['name']} ({device['runtime']})")

    build_for_testing(selected["iphone"])
    results = [run_device(selected[kind], kind) for kind in ("iphone", "ipad")]

    summary = {
        "schema": "goldjewel.runtime-gate/1",
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "results": results,
    }
    evidence_dir = os.path.join(BUILD_DIR, "runtime-evidence")
    os.makedirs(evidence_dir, exist_ok=True)
    with open(os.path.join(evidence_dir, "summary.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(summary, handle, indent=2)
        handle.write("\n")

    failed = [result for result in results if result["status"] != "passed"]
    if failed:
        for log_name in ("runtime-build.log", "runtime-iphone.log", "runtime-ipad.log"):
            source = os.path.join(BUILD_DIR, log_name)
            if os.path.exists(source):
                shutil.copy2(source, os.path.join(evidence_dir, log_name))
        for result in failed:
            print(f"runtime gate: FAILED {result['kind']} on {result['device']} ({result['status']})",
                  file=sys.stderr)
        return 1
    print("runtime gate: both devices passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
