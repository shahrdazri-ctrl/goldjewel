# M6 — the simulator runtime gate

M5 ended with a compile-only iOS gate: the app was built for the simulator but
never launched. M6 makes the gate execute the app on both device families and
assert behaviour, not just survival.

## The run

| | iPhone | iPad |
|---|---|---|
| Simulator | iPhone SE (3rd generation) | iPad mini (A17 Pro) |
| OS | iOS 18.6 | iOS 18.6 |
| Attempt 1 | **passed**, 670.9 s (820.3 s gate) | **passed**, 615.3 s (726.2 s gate) |
| Attempt 2 | — | — |
| Screenshots exported | 14 | 14 |

Both devices passed on their first attempt in run `40739496475` (job
`122996921831`) at commit `ed3562b`. The linux (`40739497026`) and macos
(`40739496461`) jobs are green on the same commit; the iOS job took 27 minutes.
The devices are pinned to an iPhone SE (3rd generation) and an iPad mini
(A17 Pro) on iOS 18.6, and the gate fails loudly if either pin is missing rather
than silently taking whatever the runner image has.

A confirmation run `40751909986` (job `123040542848`) on `9025a8d`, the revert
of the temporary proof commit, is also green. Its iPad passed first attempt in
737.9 s. Its iPhone attempt 1 failed after 833.0 s in the existing
scroll-to-control helper (`could not scroll to "bezel-toggle"`, which was
off-screen), not in the operations checks; the gate's retry passed in 720.5 s.

### The check can fail

Before trusting the operations assertions, the gate was run against a
presentation-only defect: `b54c27c` made `ResizeRing` claim to be wired while
the catalogue and the summary still counted 12 wired operations. Run
`40746345537` (job `123021042639`) went red on both devices and both attempts at
`GoldJewelRuntimeTests.swift:106` with `"wired" is not equal to
"entry-point" — ResizeRing is presented as wired`. The change was reverted in
`9025a8d`; the confirmation run above is on that tree.

The gate's bounded worst case is 104 m 40 s: 6 m 10 s of simctl discovery,
15 minutes of `build-for-testing`, and two devices at 41 m 45 s each (two
1100 s attempts, two 60 s shutdowns, one 5 s retry delay and one 180 s
screenshot export). With 20 minutes of workflow overhead and a required
10-minute margin, that needs a 134 m 40 s job; the workflow declares 140. The
runtime step needs 114 m 40 s and declares 130.
`python3 run_runtime_gate.py --check-budget` runs before the build and fails
if any constant or either timeout drifts. A deliberately reduced 40-minute job
fails the check with both job and step errors.

Artifact: `GoldJewel-runtime-screenshots` on run `40739496475`
(`07-ios-handoff/App/build/runtime-evidence/{iphone,ipad}/`). Each device has 14
PNGs, including `iPhone-00-project-list-screen.png`,
`iPhone-01-project-created-screen.png`, `iPhone-07-operations-sheet-screen.png`
and `iPhone-08-operations-entry-point-screen.png` (and the iPad equivalents).
XCTest's GUID names are mapped from the attachment manifest to these readable
names, and the per-device `manifest.json` records the device, file and original
attachment name. `summary.json` records status, duration and paths; result
bundles are in `GoldJewel-runtime-xcresult`.

## What the test asserts

`07-ios-handoff/App/UITests/GoldJewelRuntimeTests.swift` drives the app through
XCUITest:

1. **Launch and navigation.** The app reaches the foreground within 45 s. The
   project list's New Project button exists; the list is captured as
   `00-project-list-screen`, creating a project adds a row and opens the editor
   (iPhone push, iPad split-view selection), captured as
   `01-project-created-screen`. The head preview must appear and report its
   triangle count in its accessibility value.
2. **The operations sheet.** From the editor, the sheet must show the
   catalogue's exact totals (`88 v1 operations · 12 wired · 76 entry points`),
   present all twelve wired rows as `wired`, present `ResizeRing` and
   `SetDefaultRingSizeRegionAbrv` as `entry-point`, and expose Done. Both
   pending entries are opened: each detail must say `Entry point only` and must
   not expose a Run control. A wired operation (`GetActiveBuilderId`) is opened
   and run, and its result must appear. Captured as
   `07-operations-sheet-screen` and `08-operations-entry-point-screen`.
3. **Non-blank render.** A 48×48 downsample of the preview must contain more
   than **2 %** gold-coloured pixels (saturated, luminance ≥ 45). Chrome,
   background and the white sidebar cannot satisfy this.
4. **Editing.** The name field takes keyboard focus, accepts ` Gate`, the
   keyboard dismisses, and the field's value contains the addition.
5. **Every family.** Gallery rail off, prong domes off, bezel on and halo on.
   For each: the switch's accessibility value must flip, the preview's
   accessibility value must change, and the 48×48 luminance must differ from
   the previous capture by at least **0.005** of cells (threshold 10/255).
6. **A parameter change.** The gem-diameter slider moves from 6.5 mm to 9.8 mm;
   the preview must rebuild (new accessibility value) and the pixels must
   differ by at least **0.01**.
7. **Persistence.** The app is terminated and relaunched **without** the reset
   argument. The row with the edited name must exist; opening it must produce a
   non-blank preview (> 2 % gold), the name field must equal the edited name,
   and rail/dome must still be off while bezel/halo are on.

The screenshots in the artifact show the sequence for both devices: the project
list, the just-created project, the operations sheet with its totals, a pending
entry point's detail, base head with rail and dome, rail removed,
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
* The sheet's Done item disappears while its search field is active, which
  replaced the navigation bar's trailing item. The test now asserts Done before
  it searches and cancels the search before dismissing the sheet.

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
