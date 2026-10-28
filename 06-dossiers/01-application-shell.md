# Dossier 01 — Application Shell, Startup & Service Boundary

**Status:** implementation-grade · **Evidence:** `MatrixGold.exe` (951 types / 8,711 methods), `MatrixGoldPlugin.rhp` (382 / 3,028), `Common.dll` startup helpers, decompiled entry points
**Headline finding:** MatrixGold is a **two-process application**. The WPF shell owns the UI and the design document; a Rhino plugin owns geometry and rendering. They talk over a duplex service contract (`IRhinoService`, **254 operations**). The iOS app is therefore not "a WPF app rewritten" — it is a **single-process merge of an existing client/server split**, and that split should be preserved as a protocol.

---

## 1. Process topology

```
MatrixGold.exe  (WPF, 951 types)
   ├─ design document (CSDocument / CSParaGraph)
   ├─ all views + view-models (Dossier 03)
   ├─ CommonServiceLocator container
   └─ WCF client  ── IRhinoService (254 ops) ──►  Rhino 7 process
                                                   └─ MatrixGoldPlugin.rhp (382 types)
                                                        ├─ RhinoService : IRhinoService (304 methods)
                                                        ├─ geometry via RhinoCommon (Dossier 04)
                                                        └─ display conduit / render
                        ◄── IMatrixGoldUiCallback (62 ops) ──┘
```

Evidence: `MatrixGold.RhinoServiceReference.IRhinoService` (508 methods client-side proxy), `MatrixGoldPlugin.IRhinoService` (254 contract methods), `MatrixGoldPlugin.RhinoService` (304 implementation methods), `MatrixGold.Helpers.RhinoServiceCallback` (64), `MatrixGoldPlugin.IMatrixGoldUiCallback` (62).

**Why this matters for iOS:** the contract is already explicit, typed and coarse-grained. Porting it as a Swift `protocol JewelryService` with an in-process implementation gives you the same separation (UI never touches geometry objects directly) and makes it trivial to later move geometry to a background service or a Mac companion.

---

## 2. Startup sequence (recovered)

`MatrixGold.App` (16 methods) plus `Common.Helpers.RhinoStartupHelper` / `RhinoStartupOptions`:

1. `App.Main()` -> WPF `OnStartup`.
2. `InitializeCultures()` — sets UI culture before any resource lookup (18 locales).
3. `RhinoStartupHelper.CheckRhinoInstall(version)` + `CheckForRhinoPath(RegistryKey)` — locate Rhino 7 via registry.
4. Build `RhinoStartupOptions { ExecutablePath, PluginPath, SchemeName, Arguments, ShowRhinoOnStartup, NoServer, Version, App }`.
5. `StartRhino(options)` — launches the Rhino process with the plugin; `IsRhinoStartupSuccessfull` and `RhinoProcess` expose the result.
6. `ConnectToRhinoAppIdleForStartup` / `IsRhinoAppIdleForStartup` — poll until Rhino is idle.
7. `CreateCallbackChannel()` — establishes the duplex callback (`IMatrixGoldUiCallback`).
8. `AfterUILoadedSettings` — push persisted settings into the plugin.
9. Splash (`WindowSplash`) closes; `MainWindow` (33 methods) shows.

**Failure policy:** global handlers are installed for `DispatcherUnhandledException`, `AppDomain.UnhandledException`, `TaskScheduler.UnobservedTaskException`, `DomainUnload`, `ProcessExit` (`App_Exit`). A missing Rhino install is a *precondition failure* with its own dialog, not a crash.

**iOS replacement:** no external process, but keep the same ordered phases:
```
launch -> load settings -> open document (or blank) -> build service -> restore UI state -> ready
```
with a hard rule that geometry service initialisation failure surfaces as a recoverable state (read-only mode), not a crash.

---

## 3. Service surface (the real feature list)

`IRhinoService`'s 254 operations cluster cleanly. This is the most honest feature inventory in the whole program:

| Cluster | Representative operations |
|---|---|
| **Builders** | `ExecuteBuilderCommand`, `GetActiveBuilderId`, `GetAllBuilderGuids`, `GetBuilderCommands`, `DeleteBuilder`, `HighlightBuilderInViewport`, `GetUIControlsForCSValueGemParamListInstance`, `GetUIControlsFromGraph`, `GetUIControlsRelatedToPatchwire` |
| **Document/IO** | `ReadJsonFromDocument`, `GetActiveDocPath`, `GetFilePreview`, `SaveDocumentAsCounterSketchFile`, `SaveToJobBag`, `SaveStyleFromUI`, `LoadStyleFromFilePath`, `ReadContentManagerInfoFromFile` |
| **Rings** | `ResizeRing`, `GetRingRailInfoFromDocument`, `GetRingSizeRegionAbrvs`, `GetRingSizesFromRegionAbrv`, `GetDefaultRingSizeRegionAbrv`, `SetDefaultRingSizeRegionAbrv` |
| **Materials/render** | `ApplyMaterial`, `ApplyMGMaterialGroundPlane`, `ApplyMGRenderStyle`, `AdjustMaterialHueSatLum`, `AdjustShine`, `AdjustSpecificGravity`, `GetMGMaterialsInDocument`, `GetUserMaterials`, `GetStockEnvironments`, `SaveRenderMaterial`, `Render`, `RenderBatch`, `RenderAnimationFrame`, `RenderWithAlphaObjects`, `SetCurrentRenderPasses`, `SetCurrentRenderSize`, `SetCyclesRenderDevice`, `LoadRenderPlugin` |
| **Gems** | `GetGemsInfo`, `GetGemsForReport`, `MaterialsForReport`, `GetCaratWeightByGravity`, `OpenGemMap`, `GetBitmapImageBytesFromGemMap` |
| **Weights** | `GetObjectsWeight`, `GetObjectsWeightByGravity`, `GetAllObjectsVolumeSum`, `GetGramsAndDwtFromMaterial` |
| **Layers/groups** | `AddSelectionToLayer`, `HideLayer`, `LockLayer`, `SetActiveLayer`, `SelectObjectsInLayer`, `PopulateUserLayers`, `AddToExistingGroup`, `GetNewDynamicGroup`, `InterrogateImportedGroups` |
| **Animation** | `CreateAnimation`, `ModifyCameraPath`, `ScrubAnimation`, `LoadCameraPathFromPreset`, `LoadDisplayModes` |
| **Settings** | `GetHistorySettings`, `SetAutosaveSettings`, `SetEnableAutosave`, `GetGridSnapSpacing`, `SetGridSnapSpacing`, `SetEnableSmartTrack`, `SetEnableControlPointsOnCurveSelection`, `ResetDisplayModesToDefault` |
| **Diagnostics** | `Ping`, `CanRunTechReport`, `GetRhinoVersionString`, `GetRhinoServerProcessId`, `GetErroredPatchwires`, `GetLegacyObjectTypesInDocument` |

Port these **by cluster**, not alphabetically. Each cluster is a screen (Dossier 03) plus a document concern (Dossier 02).

---

## 4. Configuration and file system contract

`CS.CSApplication` exposes 82 properties, of which these are the path/setting contract:

`CSRootPath`, `CSSystemPath`, `CSStyleSheetPath`, `CSLibraryPath`, `CSLibraryPathUser`, `CSMatrixStyleSheetPath`, `CSMatrixStyleSheetPathUser`, `CSIterationPresetsPath`, `CSMeshRepairPath`, `InvokePartPath`, plus behaviour flags `DebugLogEnabled`, `IsBlockParallelProcessingEnabled`, `AutoHideInputs`, `IsForceHideDisabled`, `DisableMeshObjectMeshing`, `DrawBuildersWireFrame`, `SaveOutputChannelData`, `WhenExportingHonorGemPrintingFlags`, `IsExportingSTL`, `IsExportingForPrint`.

Settings split into **system** (read-only, under the install root) and **user** (writable). The `*User` suffixed paths encode that split. The iOS app must do the same: bundled read-only content vs. Application Support for user content, styles and presets. Never write into the bundle.

`DocumentUserData` (a sectioned key/value store) carries UI state such as `Display/CurrentComponents`, `Display/FreehandComponentsVisible`, and `UI/Template` (`SetupTemplateName`). It is saved *inside the design file* — so per-document UI state must be part of the iOS document model, not app preferences.

---

## 5. Threading and responsiveness

* `IsBlockParallelProcessingEnabled` gates `GenerateConcurrently`.
* `InterruptUpdate(offsetMs)` aborts long updates after ~100 ms, preserving UI responsiveness.
* `Application_DispatcherUnhandledException` + `TaskScheduler_UnobservedTaskException`: unobserved task faults are logged, not fatal.
* Rendering is off-process (`Render`, `RenderBatch`, `RenderAnimationFrame`), i.e. asynchronous by construction.

**iOS:** the equivalent discipline is a serial graph queue + `Task` cancellation + a render queue. Treat "cancel on new edit" as a first-class requirement, not an optimisation.

---

## 6. The licensing boundary (explicit)

`CommonAuthentication` contains `SecurityHelper` (101 methods), `PackageHelper` (14), `LoginWindow` (12), `ViewModel.Locator`, and the shell shows `WindowEula` (9). These implement account login, entitlement checks and package validation.

**This program deliberately does not analyse, document or reproduce that logic.** The dossier stops at the boundary:

* The iOS app must implement its **own** authentication and entitlement system (Sign in with Apple + your backend, StoreKit 2 for subscriptions).
* No licence-server protocol, key derivation, signature check or package format is described here, by design.
* Everything else in this dossier set is product logic and is fair game.

Practical note for the port: entitlement checks in the original are interleaved with feature entry points (`CanRunTechReport`, gated builders). Design the iOS equivalent as a single `Entitlements` service queried by feature gates, so it can be tested and audited in one place.

---

## 7. iOS service protocol (recommended shape)

```swift
protocol JewelryService: Sendable {
    // Document
    func open(_ url: URL) async throws -> DesignDocument
    func save(_ doc: DesignDocument, to url: URL) async throws

    // Builders
    func builderCatalog() async -> [BuilderDescriptor]
    func execute(_ command: BuilderCommand, in doc: inout DesignDocument) async throws

    // Rings
    func resizeRing(_ request: RingResizeRequest, in doc: inout DesignDocument) async throws

    // Gems & materials
    func gems(in doc: DesignDocument) async -> [GemRecord]
    func materials(in doc: DesignDocument) async -> [MaterialPreset]

    // Reports
    func weights(for doc: DesignDocument) async throws -> WeightReport
    func gemReport(for doc: DesignDocument) async -> GemReport

    // Render
    func render(_ request: RenderRequest) async throws -> CGImage
}
```

Keep it coarse (one call per user action), `async`, and `Sendable`. Do **not** mirror all 254 operations 1:1 — many are Rhino-host concerns that vanish in a single-process app (`GetRhinoServerProcessId`, `SetFocusToRhino`, `SendKeyStroke`, `GetRhinoWindowHandle`).

---

## 8. Evidence

```sql
-- service contract
select m.name, m.signature from methods m join types t on t.id=m.type_id
where t.full_name='MatrixGoldPlugin.IRhinoService' order by m.name;

-- shell startup
select m.name from methods m join types t on t.id=m.type_id
where t.full_name='MatrixGold.App';

-- application settings
select p.name, p.type from properties p join types t on t.id=p.type_id
where t.full_name='CS.CSApplication' and p.name like 'CS%Path%';
```

Sources: `03-decompiled/raw/MatrixGold/MatrixGold/App.cs`, `MatrixGold/MainWindow.cs`, `03-decompiled/raw/Common/Common.Helpers/RhinoStartup*.cs` (duplicated across three Common copies), `03-decompiled/raw/MatrixGoldPlugin/**`.
