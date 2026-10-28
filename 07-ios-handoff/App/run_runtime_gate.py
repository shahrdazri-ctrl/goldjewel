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
import re
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
RUN_TIMEOUT = 1000
BUILD_TIMEOUT = 900
SHUTDOWN_TIMEOUT = 60
EXPORT_TIMEOUT = 180
DISCOVERY_TIMEOUT = 120
DISCOVERY_ATTEMPTS = 3
RETRY_DELAY = 5
ATTEMPTS_PER_DEVICE = 2
DEVICE_COUNT = 2
TEST_ALLOWANCE = 780
# Time outside the runner: xcodegen, the generic build, and artifact uploads.
WORKFLOW_OVERHEAD = 1200
# Required headroom below the workflow timeout.
MIN_BUDGET_MARGIN = 600
PINNED_DEVICES = {
    "iphone": ("iPhone SE (3rd generation)", "18.6"),
    "ipad": ("iPad mini (A17 Pro)", "18.6"),
}
WORKFLOW_PATH = os.path.join(REPO_ROOT, ".github", "workflows", "ios-simulator.yml")


def worst_case_seconds() -> dict[str, int]:
    """Sum every bounded wait the gate can perform, in seconds."""
    discovery = (
        DISCOVERY_TIMEOUT * DISCOVERY_ATTEMPTS
        + RETRY_DELAY * (DISCOVERY_ATTEMPTS - 1)
    )
    per_device = (
        ATTEMPTS_PER_DEVICE * RUN_TIMEOUT
        + ATTEMPTS_PER_DEVICE * SHUTDOWN_TIMEOUT
        + (ATTEMPTS_PER_DEVICE - 1) * RETRY_DELAY
        + EXPORT_TIMEOUT
    )
    devices = DEVICE_COUNT * per_device
    gate = discovery + BUILD_TIMEOUT + devices
    return {
        "discovery": discovery,
        "build": BUILD_TIMEOUT,
        "per_device": per_device,
        "devices": devices,
        "gate": gate,
        "job": gate + WORKFLOW_OVERHEAD,
    }


def _minutes(seconds: int) -> str:
    return f"{seconds / 60:.1f} min"


def read_workflow_timeouts(path: str = WORKFLOW_PATH) -> tuple[int, int]:
    """Read the job and runtime-step timeout from the iOS workflow."""
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    job = re.search(r"^\s{4}timeout-minutes:\s*(\d+)\s*$", text, re.MULTILINE)
    step = re.search(
        r"- name: Run iPhone and iPad runtime tests\n([\s\S]*?)(?=\n\s{6}- name:|\Z)",
        text,
    )
    step_timeout = (
        re.search(r"^\s{8}timeout-minutes:\s*(\d+)\s*$", step.group(1), re.MULTILINE)
        if step
        else None
    )
    if job is None or step_timeout is None:
        raise RuntimeError(
            "ios-simulator.yml must declare both the job timeout and the "
            "runtime-step timeout"
        )
    return int(job.group(1)), int(step_timeout.group(1))


def check_workflow_budget(path: str = WORKFLOW_PATH) -> list[str]:
    """Fail unless every bounded wait fits below the workflow's timeout."""
    budget = worst_case_seconds()
    job_minutes, step_minutes = read_workflow_timeouts(path)
    job_seconds = job_minutes * 60
    step_seconds = step_minutes * 60
    required_job = budget["job"] + MIN_BUDGET_MARGIN
    required_step = budget["gate"] + MIN_BUDGET_MARGIN
    print(
        "runtime gate budget: "
        f"gate worst case {budget['gate']} s ({_minutes(budget['gate'])}): "
        f"discovery {budget['discovery']} s + build {budget['build']} s + "
        f"{DEVICE_COUNT} devices x {budget['per_device']} s"
    )
    print(
        f"runtime gate budget: with {WORKFLOW_OVERHEAD} s of workflow overhead, "
        f"the job needs {required_job} s ({_minutes(required_job)}) and is "
        f"configured for {job_seconds} s ({job_minutes} min)"
    )
    print(
        f"runtime gate budget: the runtime step needs {required_step} s "
        f"({_minutes(required_step)}) and is configured for {step_seconds} s "
        f"({step_minutes} min)"
    )
    problems = []
    if RUN_TIMEOUT <= TEST_ALLOWANCE:
        problems.append(
            f"RUN_TIMEOUT ({RUN_TIMEOUT} s) must exceed the test allowance "
            f"({TEST_ALLOWANCE} s)"
        )
    if job_seconds < required_job:
        problems.append(
            f"job timeout {job_seconds} s is below the required {required_job} s"
        )
    if step_seconds < required_step:
        problems.append(
            f"runtime step timeout {step_seconds} s is below the required "
            f"{required_step} s"
        )
    if step_seconds >= job_seconds:
        problems.append("the runtime step must be shorter than the whole job")
    return problems


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


def runtime_version(runtime: str) -> str:
    """Turn a simctl runtime key such as iOS-18-6 into 18.6."""
    if "iOS-" in runtime:
        return runtime.rsplit("iOS-", 1)[-1].replace("-", ".")
    return runtime.rsplit("-", 1)[-1].replace("_", ".")


def simulator_devices() -> list[dict]:
    # CoreSimulatorService can be slow to answer on a cold runner. A hung list
    # is retried a bounded number of times rather than failing the gate or
    # waiting forever.
    code = 1
    output = ""
    for attempt in range(DISCOVERY_ATTEMPTS):
        try:
            code, output = capture(
                ["xcrun", "simctl", "list", "devices", "available", "-j"],
                timeout=DISCOVERY_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            print(
                f"runtime gate: simctl list timed out "
                f"(attempt {attempt + 1}/{DISCOVERY_ATTEMPTS})",
                file=sys.stderr,
            )
            time.sleep(RETRY_DELAY)
            continue
        if code == 0:
            break
        print(
            f"runtime gate: simctl list failed "
            f"(attempt {attempt + 1}/{DISCOVERY_ATTEMPTS}, exit {code})",
            file=sys.stderr,
        )
        time.sleep(RETRY_DELAY)
    else:
        raise RuntimeError(
            f"simctl list did not answer after {DISCOVERY_ATTEMPTS} attempts: "
            f"{output[-2000:]}"
        )
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
        version = runtime_version(runtime)
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
    """Return the pinned simulator, or fail with the available alternatives."""
    name, version = PINNED_DEVICES[kind]
    candidates = [
        device
        for device in devices
        if device["name"] == name and device["version"] == version
    ]
    if not candidates:
        token = "iPad" if kind == "ipad" else "iPhone"
        available = sorted({
            f"{device['name']} iOS {device['version']}"
            for device in devices
            if token in device["name"]
        })
        raise RuntimeError(
            f"pinned {kind} simulator {name!r} on iOS {version} is not "
            f"available: {', '.join(available) or 'none'}"
        )
    return sorted(candidates, key=lambda device: device["udid"])[0]


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
    run(["xcrun", "simctl", "shutdown", udid], timeout=SHUTDOWN_TIMEOUT)


def _readable_attachment_name(name: str) -> str:
    stem = os.path.splitext(os.path.basename(name))[0]
    stem = re.sub(r"_0_[0-9A-Fa-f-]{36}$", "", stem)
    stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-")
    return (stem or "attachment") + ".png"


def export_screenshots(result_bundle: str, kind: str) -> list[str]:
    evidence = os.path.join(BUILD_DIR, "runtime-evidence", kind)
    if os.path.isdir(evidence):
        shutil.rmtree(evidence)
    os.makedirs(evidence, exist_ok=True)
    exported = os.path.join(evidence, ".attachments")
    code, output = run(
        [
            "xcrun", "xcresulttool", "export", "attachments",
            "--path", result_bundle,
            "--output-path", exported,
        ],
        timeout=EXPORT_TIMEOUT,
    )
    if code != 0:
        print(output[-2000:] if output else "")
        return []
    manifest_path = os.path.join(exported, "manifest.json")
    entries = []
    if os.path.exists(manifest_path):
        try:
            payload = json.loads(open(manifest_path, encoding="utf-8").read())
            if isinstance(payload, list) and payload:
                entries = payload[0].get("attachments", [])
        except (OSError, json.JSONDecodeError, AttributeError):
            entries = []
    if not entries:
        print(
            "runtime gate: xcresulttool produced no attachment manifest; "
            "refusing to publish GUID-named screenshots",
            file=sys.stderr,
        )
        shutil.rmtree(exported, ignore_errors=True)
        return []
    screenshots = []
    records = []
    used = set()
    for entry in entries:
        filename = entry.get("exportedFileName")
        if not filename or not filename.lower().endswith(".png"):
            continue
        source = os.path.join(exported, filename)
        if not os.path.exists(source):
            continue
        readable = _readable_attachment_name(
            entry.get("suggestedHumanReadableName") or filename
        )
        stem, suffix = os.path.splitext(readable)
        candidate = readable
        index = 2
        while candidate in used:
            candidate = f"{stem}-{index}{suffix}"
            index += 1
        used.add(candidate)
        destination = os.path.join(evidence, candidate)
        shutil.copy2(source, destination)
        screenshots.append(destination)
        records.append({
            "file": candidate,
            "device": entry.get("deviceName", ""),
            "attachment": entry.get("suggestedHumanReadableName", ""),
        })
    shutil.rmtree(exported, ignore_errors=True)
    if records:
        with open(
            os.path.join(evidence, "manifest.json"),
            "w",
            encoding="utf-8",
            newline=chr(10),
        ) as handle:
            json.dump(
                {
                    "schema": "goldjewel.runtime-evidence/1",
                    "kind": kind,
                    "attachments": records,
                },
                handle,
                indent=2,
            )
            handle.write(chr(10))
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
        "-default-test-execution-time-allowance", str(TEST_ALLOWANCE),
        "-maximum-test-execution-time-allowance", str(TEST_ALLOWANCE + 120),
        "CODE_SIGNING_ALLOWED=NO",
    ]
    started = time.monotonic()
    attempt = 1
    code = 1
    while attempt <= ATTEMPTS_PER_DEVICE:
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
        if attempt <= ATTEMPTS_PER_DEVICE:
            time.sleep(RETRY_DELAY)

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
            "duration_seconds": round(time.monotonic() - started, 1),
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
        "duration_seconds": round(time.monotonic() - started, 1),
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
    if "--check-budget" in sys.argv[1:]:
        try:
            problems = check_workflow_budget()
        except (OSError, RuntimeError) as error:
            print(f"runtime gate budget: FAIL: {error}", file=sys.stderr)
            raise SystemExit(1)
        if problems:
            for problem in problems:
                print(f"runtime gate budget: FAIL: {problem}", file=sys.stderr)
            raise SystemExit(1)
        print("runtime gate budget: OK")
        raise SystemExit(0)
    raise SystemExit(main())
