# M6 — the simulator runtime gate

M5 ended with a compile-only iOS gate: the app was built for the simulator but
never launched. M6 makes the gate execute the app on both device families and
assert behaviour, not just survival.

## The run

| | iPhone | iPad |
|---|---|---|
| Simulator | iPhone SE (3rd generation) | iPad mini (A17 Pro) |
| OS | iOS 18.6 | iOS 18.6 |
| Attempt 1 | **passed**, 649.6 s (884.2 s runner) | **passed**, 624.2 s (859.4 s runner) |
| Attempt 2 | — | — |
| Screenshots exported | 12 | 12 |

Both devices passed on their first attempt in run `40708660181` (job
`122887591049`) at commit `5fff28d`. The linux (`40708660101`) and macos
(`40708660128`) jobs are green on the same commit; the whole iOS job took
31 m 38 s. The devices are pinned to an iPhone SE (3rd generation) and an iPad
mini (A17 Pro) on iOS 18.6, and the gate fails loudly if either pin is missing
rather than silently taking whatever the runner image has.

The gate's bounded worst case is 98 minutes: 6 m 10 s of simctl discovery,
15 minutes of `build-for-testing`, and two devices at 38 m 25 s each (two
1000 s attempts, two 60 s shutdowns, one 5 s retry delay and one 180 s
screenshot export). With 20 minutes of workflow overhead and a required
10-minute margin, that needs a 128-minute job; the workflow declares 130. The
runtime step needs 108 minutes and declares 120.
`python3 run_runtime_gate.py --check-budget` runs before the build and fails
if any constant or either timeout drifts. A deliberately reduced 40-minute job
fails the check with both job and step errors.

Artifact: `GoldJewel-runtime-screenshots` on run `40708660181`
(`07-ios-handoff/App/build/runtime-evidence/{iphone,ipad}/`). Each device has 12
PNGs, including `iPhone-00-project-list-screen.png` and
`iPhone-01-project-created-screen.png` (and the iPad equivalents). XCTest's GUID
names are mapped from the attachment manifest to these readable names, and the
per-device `manifest.json` records the device, file and original attachment
name. `summary.json` records status, duration and paths; result bundles are in
`GoldJewel-runtime-xcresult`.

## What the test asserts

`GoldJewelUITests/GoldJewelRuntimeTests.swift` drives the app through XCUITest:

1. **Launch and navigation.** The app reaches the foreground within 45 s. The
   project list's New Project button exists; the list is captured as
   `00-project-list-screen`, creating a project adds a row and opens the editor
   (iPhone push, iPad split-view selection), captured as
   `01-project-created-screen`. The head preview must appear and report its
   triangle count in its accessibility value.
2. **Non-blank render.** A 48×48 downsample of the preview must contain more
   than **2 %** gold-coloured pixels (saturated, luminance ≥ 45). Chrome,
   background and the white sidebar cannot satisfy this.
3. **Editing.** The name field takes keyboard focus, accepts ` Gate`, the
   keyboard dismisses, and the field's value contains the addition.
4. **Every family.** Gallery rail off, prong domes off, bezel on and halo on.
   For each: the switch's accessibility value must flip, the preview's
   accessibility value must change, and the 48×48 luminance must differ from
   the previous capture by at least **0.005** of cells (threshold 10/255).
5. **A parameter change.** The gem-diameter slider moves from 6.5 mm to 9.8 mm;
   the preview must rebuild (new accessibility value) and the pixels must
   differ by at least **0.01**.
6. **Persistence.** The app is terminated and relaunched **without** the reset
   argument. The row with the edited name must exist; opening it must produce a
   non-blank preview (> 2 % gold), the name field must equal the edited name,
   and rail/dome must still be off while bezel/halo are on.

The screenshots in the artifact show the sequence for both devices: the project
list, the just-created project, base head with rail and dome, rail removed,
dome removed, bezel added, halo added, larger gem, and the restored project. On
iPad the restored capture visibly carries the bezel and halo with the rail and
dome absent; on iPhone the same state is shown with the halo stones around the
gallery.

## Why it failed before it passed

The earlier attempts found real interaction defects rather than assertion noise.

* iPadOS 18 presents the sidebar over the detail and dims it. The test's
  left-edge drags re-opened that overlay instead of scrolling. The test now
  dismisses the overlay before interacting and drags in the content's trailing
  margin.
* The iPad toggle row spans the whole detail column, so a tap at 90 % of the
  row fell in the gap beside the switch. Taps now target 28 pt from the
  trailing edge.
* The status-bar scroll-to-top does not work on iPad. Scrolling is now anchored
  on the preview becoming hittable, then searches in half-page steps.
* The name was written through on every keystroke and autosaved immediately;
  the resulting re-render could drop keyboard focus mid-word. The editor keeps a
  draft and commits on submit/focus loss, and autosave is coalesced (450 ms) and
  flushed when the app leaves the foreground.
* The first pinned run failed loudly because the simctl runtime key was reduced
  to its last component (`iOS 18.6` became `6`). The pin now extracts the full
  iOS version and the failure lists the available devices.

## What a simulator still cannot prove

* **Real device hardware.** Rendering is a CPU `Canvas`; there is no Metal,
  RealityKit, GPU memory pressure or thermal behaviour in this gate. Frame rate
  and battery are not asserted.
* **Form factors beyond the two used.** iPhone SE has a home button and a small
  screen; iPad mini is the smallest iPad. No Dynamic Island/notch safe area, no
  11"/13" iPad, no landscape, Split View, Stage Manager or external display.
* **System integration.** No archive/signing/TestFlight install, no push, no
  Files import/export, no share sheet, no accessibility (VoiceOver, Dynamic
  Type), no light/dark appearance switch, no locale switch.
* **Crash durability.** The persistence proof is a clean `terminate()` after
  the 450 ms save coalescing window. A crash inside that window can still lose
  the last edit; the gate does not inject one.
* **Vendor equivalence.** This proves the app renders and persists its own
  graded geometry. It does not close limitation #4 (no vendor geometry has ever
  been measured): the recovered/reconstructed/inferred grades in
  `08-reports/m5-report.md` are unchanged.
* **Screenshot-service reliability.** An earlier iPad attempt died in XCTest's
  screenshot request after the render was already correct; this run passed both
  devices on their first attempt, and the runner still retries once. That was a
  simulator-service timeout, not an app hang. A physical device uses a
  different capture path.

## Reproduce

```
cd 07-ios-handoff/App
python3 run_runtime_gate.py
```

The gate builds the test bundle once, requires the pinned iPhone SE (3rd
generation) and iPad mini (A17 Pro) on iOS 18.6, runs the same test on each,
retries a failed device once after five seconds, exports every attachment under
its readable name to `build/runtime-evidence/<kind>/`, and writes
`summary.json`. Run `python3 run_runtime_gate.py --check-budget` first; CI runs
it before the build and uploads the evidence and `.xcresult` bundles on every
outcome.
