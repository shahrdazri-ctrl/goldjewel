#!/usr/bin/env python3
"""Build the capability matrix for the 254 IRhinoService operations.

The operation names come from the decompiled service contract, not from a
hand-written list: every OperationContract action is parsed, sync/async pairs
are collapsed, and each operation receives exactly one disposition with the
rule that produced it.

  v1            implemented in the first iPadOS release
  defer         in product scope, not in the first release
  drop          desktop-only, replaced by the app, or integration we do not ship
  out-of-scope  licensing/activation, a stated boundary

Usage:
  python Tools/capability_matrix.py
"""
from __future__ import annotations

import csv
import os
import re
import sys

SERVICE = "03-decompiled/raw/MatrixGold/MatrixGold.RhinoServiceReference/IRhinoService.cs"

V1 = {
    # builders and the graph
    "ExecuteBuilderCommand", "GetActiveBuilderId", "GetAllBuilderGuids",
    "GetBuilderCommands", "DeleteBuilder", "GetUIControlsFromGraph",
    "GetUIControlsRelatedToPatchwire", "GetUIControlsForCSValueGemParamListInstance",
    "UpdateUIControlForCSValueGemParamListInstance", "UpdateGraphFromUIControl",
    "SetParametricRegenerationFull", "GetPreviewImageByteArrayFromBuilder",
    "ActivateBuilderFrom3dm", "HighlightBuilderInViewport",
    "GetUIClassificationForCommandId",
    # document
    "ReadJsonFromDocument", "WriteJsonToDocument", "GetActiveDocPath",
    "GetCurrentFileIsModified", "SetCurrentFileAsNoModified",
    "GetJsonCenterPointFromObjects", "GetRelatedPatchwires",
    "GetPatchwireNameFromInstanceGuid", "SetPatchwireNameFromInstanceGuid",
    "GetPatchwireHasGumball", "HasHiddenOutput", "ShowPatchwireOutput",
    "ShowPatchwireOutputForAll", "HidePatchwireOutput",
    "GetVisiblePatchwireIdentifiers", "GetErroredPatchwires",
    # objects and selection
    "GetObjectsInDocument", "GetSelectedRhinoObjects", "GetRenderGuidFromObject",
    "SelectObjectsById", "SelectObjectsDocument", "DeselectObjects",
    "HideObjects", "ShowObjects", "UpdateHasRhinoObjectsSelected",
    # measurement
    "GetObjectsVolume", "GetAllObjectsVolumeSum", "GetObjectsWeight",
    "GetObjectsWeightByGravity", "GetGramsAndDwtFromMaterial",
    "RemoveNonVolumizableItemsFromList",
    # rings
    "ResizeRing", "GetRingRailInfoFromDocument", "GetRingSizeRegionAbrvs",
    "GetRingSizesFromRegionAbrv", "GetDefaultRingSizeRegionAbrv",
    "SetDefaultRingSizeRegionAbrv", "SetRingResizerData", "SetVPCHScale",
    "SetScaleViewportRing", "SetVisibleViewportRing",
    # materials and gems
    "ApplyMaterial", "ApplyUserMaterial", "AdjustMaterialHueSatLum",
    "AdjustShine", "AdjustSpecificGravity", "AdjustMetalFinish",
    "AdjustReflectiveColor", "ChangeMapType", "ChangeMaterialMap",
    "SetSingleMapValue", "GetMGMaterialsInDocument", "GetNewMGMaterialsInDocument",
    "GetUserMaterials", "GetStockMapDataList", "SaveRenderMaterial",
    "DuplicateRenderMaterial", "ResetRenderMaterial",
    "DeleteRenderMaterialFromDocument", "LoadRhinoMaterialFromFile",
    "ImportRenderMaterialsFromFile", "OpenGemMap", "CloseGemMap",
    "GetBitmapImageBytesFromGemMap", "GetUpdatedImageBytesFromGemMap",
    "GetGemsInfo", "GetCaratWeightByGravity",
    # settings that change behaviour
    "GetHistorySettings", "UpdateHistorySettings", "SetRecordHistory",
    "SetAutosaveSettings", "SetEnableAutosave",
    "SetEnableControlPointsOnCurveSelection", "SetAutoHide",
}

OUT_OF_SCOPE = {"ActivateLicense", "CheckLicense", "GetLicenseInfo", "SetLicense"}

# Ordered: the first matching rule decides. Each entry is (substring, reason).
DROP_RULES = [
    ("License", "licensing/activation is a stated boundary"),
    ("CallbackChannel", "WCF plumbing between the WPF shell and Rhino"),
    ("AppIdle", "Rhino host lifecycle"),
    ("RhinoServer", "Rhino host identity"),
    ("RhinoWindowHandle", "Rhino host identity"),
    ("RhinoVersion", "Rhino host identity"),
    ("SetFocusToRhino", "window focus is a desktop concern"),
    ("SendKeyStroke", "synthetic input into the desktop shell"),
    ("Macro", "desktop macro recording"),
    ("ExecuteScript", "user scripting host is not part of v1"),
    ("PopulateStaticPaths", "installation path discovery"),
    ("GetSystemPath", "installation path discovery"),
    ("CommandBar", "desktop command bar"),
    ("StatusBar", "desktop status bar"),
    ("StandardToolbar", "desktop toolbar"),
    ("RhinoMenu", "desktop menu"),
    ("ShowHelp", "desktop help window"),
    ("SetDev", "developer switch"),
    ("SetBeta", "developer switch"),
    ("SetCore", "developer switch"),
    ("FirstRunScheme", "desktop first-run theme"),
    ("CommandPrompt", "desktop command prompt"),
    ("AbortRunningCommand", "desktop command host"),
    ("GetRunningCommandName", "desktop command host"),
    ("GetInternalCommands", "desktop command host"),
    ("JobBag", "CounterSketch job-bag integration"),
    ("CounterSketch", "CounterSketch job-bag integration"),
    ("Role", "CounterSketch pricing roles"),
    ("MatchAttributesWfc", "CounterSketch attribute matching"),
    ("CreateAnimation", "animation is out of v1 scope"),
    ("ModifyCameraPath", "animation is out of v1 scope"),
    ("ScrubAnimation", "animation is out of v1 scope"),
    ("StopAnimation", "animation is out of v1 scope"),
    ("CameraPath", "animation is out of v1 scope"),
    ("Render", "offline/Cycles rendering is out of v1 scope"),
    ("Cycles", "offline/Cycles rendering is out of v1 scope"),
    ("AlphaViewport", "render compositing is out of v1 scope"),
    ("SafeFrame", "render compositing is out of v1 scope"),
    ("Focal", "render camera controls are out of v1 scope"),
    ("TechReport", "desktop diagnostics"),
    ("MaterialsForReport", "desktop reporting"),
    ("GemsForReport", "desktop reporting"),
    ("CaptureRhinoView", "desktop capture pipeline"),
    ("ViewportCaptures", "desktop capture pipeline"),
    ("PreviewForSelectedObjects", "desktop preview pipeline"),
    ("SelectedObjectsPreviewBytes", "desktop preview pipeline"),
    ("VisibleObjectsPreview", "desktop preview pipeline"),
    ("Script", "scripting host"),
]

CLUSTERS = [
    ("Builders", ("Builder", "UIControl", "Patchwire", "Graph")),
    ("Rings", ("Ring", "RingSize", "Resize")),
    ("Gems", ("Gem", "Carat")),
    ("Materials", ("Material", "Metal", "Shine", "Reflective", "Map", "Environment", "Backdrop")),
    ("Weights", ("Weight", "Volume", "Gravity", "Dwt")),
    ("Document", ("Document", "Json", "DocPath", "File", "Preview", "ContentManager")),
    ("Layers", ("Layer",)),
    ("Groups", ("Group",)),
    ("Selection", ("Select", "Object", "Hide", "Show", "Highlight", "Conduit")),
    ("Viewport", ("Viewport", "DisplayMode", "Wireframe", "Shade", "Gumball", "Grid", "Snap", "Osnap", "Planar", "Ortho", "Zoom", "ScaleViewport", "VPCH")),
    ("Render", ("Render", "Cycles", "Alpha", "SafeFrame", "Focal", "Lighting")),
    ("Animation", ("Animation", "CameraPath")),
    ("Settings", ("Settings", "Setting", "Autosave", "History", "SmartTrack", "ControlPoints")),
    ("Styles", ("Style", "Profile", "Preset", "Library")),
    ("Diagnostics", ("Ping", "RhinoVersion", "TechReport", "Errored")),
    ("Licensing", ("License",)),
]


def cluster_of(name: str) -> str:
    for cluster, keywords in CLUSTERS:
        if any(keyword in name for keyword in keywords):
            return cluster
    return "Other"


def classify(name: str) -> tuple[str, str, str]:
    if name in OUT_OF_SCOPE:
        return "out-of-scope", "licensing/activation", "explicit"
    if name in V1:
        return "v1", "core design loop", "explicit-v1"
    for token, reason in DROP_RULES:
        if token in name:
            return "drop", reason, f"contains:{token}"
    return "defer", "product scope, not the first release", "unmatched-defer"


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source = os.path.join(root, *SERVICE.split("/"))
    if not os.path.exists(source):
        print(f"missing service contract: {source}", file=sys.stderr)
        print("run this in the lab (the decompiled tree is not committed)", file=sys.stderr)
        return 2

    text = open(source, encoding="utf-8").read()
    names = set()
    for match in re.finditer(r'IRhinoService/([A-Za-z0-9_]+)"', text):
        name = match.group(1)
        if name.endswith("Async") or name.endswith("Response"):
            continue
        names.add(name)
    operations = sorted(names)
    if len(operations) != 254:
        print(f"warning: expected 254 operations, parsed {len(operations)}", file=sys.stderr)

    rows = []
    for name in operations:
        disposition, reason, rule = classify(name)
        rows.append(
            {
                "operation": name,
                "cluster": cluster_of(name),
                "disposition": disposition,
                "rule": rule,
                "reason": reason,
            }
        )

    out = os.path.join(root, "08-reports", "capability-matrix.csv")
    with open(out, "w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=["operation", "cluster", "disposition", "rule", "reason"])
        writer.writeheader()
        writer.writerows(rows)

    counts = {}
    for row in rows:
        counts[row["disposition"]] = counts.get(row["disposition"], 0) + 1
    print(f"operations {len(rows)}")
    for key in ("v1", "defer", "drop", "out-of-scope"):
        print(f"{key} {counts.get(key, 0)}")
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
