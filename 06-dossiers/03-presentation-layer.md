# Dossier 03 — Presentation Layer (WPF MVVM -> SwiftUI)

**Status:** implementation-grade · **Evidence:** 117 BAML resources decompiled to XAML, 4,205 extracted binding/command facts, `MatrixGold` UI assemblies (55 views, 39 view-models, 107 converters)
**Purpose:** define the interaction model, screen inventory and binding contract so the iPad app is a *professional tool*, not a form over a 3D view.

---

## 1. Measured structure

| Artifact | Count |
|---|---:|
| BAML -> XAML files decompiled | **117 / 117** (zero failures) |
| Extracted binding/command facts | **4,205** |
| Distinct binding paths | **1,168** non-empty |
| Distinct commands | **366** (`Command*` identifiers: 286) |
| Views (`MatrixGold.Views`) | 55 |
| View-models (`MatrixGold.ViewModels`) | 39 |
| Converters | 107 |
| UI models | 28 |

Densest screens by binding count: `views/viewrender.xaml` (577), `views/viewbuilders.xaml` (464), `resources/builderdatatemplates.xaml` (374), `views/windowpreferences.xaml` (280), `resources/commandicons.xaml` (239).

Control vocabulary: `Button` 775, `InvokeCommandAction` 548, `TextBlock` 397, `MenuItem` 172, `TextBox` 168, `Path` 168, `Border` 143, `CheckBox` 135. Most-used attributes: `Command` (1,116), `CommandParameter` (450), `Text` (442), `Visibility` (437), `IsChecked` (227).

**Interpretation:** this is a command-driven parameter editor with a very large number of small controls — i.e. a *builder* UI. It is not a document editor with a ribbon bolted on. iOS must be designed as a parameter console with a live viewport, not as a menu-driven CAD app.

---

## 2. The one interaction contract

`CommandUpdateGraphFromUI` appears **275 times** across the XAML — by far the most referenced command. It is bound from every builder control (slider release, text commit, toggle, combo selection) up to the containing `UserControl`'s `DataContext`.

Semantics recovered from the name and call sites: **UI change -> push value(s) into the block's input channel -> regenerate the graph -> refresh display**. All parameter edits funnel through it, with `CommandParameter` carrying the edited value/field.

iOS equivalent:

```swift
@MainActor final class BuilderEditor {
    func updateGraph(from edit: ParameterEdit) async {
        graph.setValue(edit.value, for: edit.channel, in: edit.blockID)
        await graph.regenerate(from: edit.blockID)   // downstream only
        viewport.refresh(for: graph.dirtyOutputs)
    }
}
```

Rules:
1. **One entry point.** Do not add per-control mutation; every edit becomes a `ParameterEdit`.
2. **Coalesce.** Slider drags must debounce/merge (the original relies on `InterruptUpdate(100 ms)`); on iOS use a 1–2 frame coalescing window plus cancellation.
3. **Never block the main thread.** `GenerateConcurrently` exists for a reason; run evaluation off-main, publish results on main.
4. **`CommandParameter` is typed.** 450 bindings pass values; the port's `ParameterEdit` must carry a typed enum (double, int, bool, string, enum case, point), not `Any`.

---

## 3. Screen inventory and weight

View-model method counts are a reliable proxy for feature weight:

| Screen | VM | Methods | What it is |
|---|---|---:|---|
| Render | `RenderViewModel` | 482 | Materials, environments, HDR, cameras, final render |
| Preferences | `WindowPreferencesViewModel` | 388 | Every app setting, units, tolerances, UI scale |
| Projects | `ProjectsViewModel` | 285 | Project/job-bag browser, metadata, status |
| Animation Studio | `AnimationStudioViewModel` | 203 | Keyframes, camera paths, turntables |
| Main shell | `MainViewModel` | 183 | Command routing, docking, status |
| Tool ribbon | `ToolRibbonViewModel` | 126 | Contextual tools |
| Collections | `CollectionsManagerViewModel` | 106 | Library/content management |
| **Ring Resizer** | `RingResizerViewModel` | 103 | Resize a finished ring (size + width + thickness) |
| Builders | `BuildersViewModel` / `BuilderViewModel` | 100 / 92 | The parametric builder catalog and one builder |
| Movie Maker | `MovieMakerViewModel` | 82 | Marketing video export |
| Metal Weights | `MetalWeightsViewModel` | 30 | Weight/estimation by metal |
| Gem Report | `GemReportViewModel` | 22 | Stone list, counts, sizes, costs |

**Minimum viable iPad app** (in order): Builders + viewport -> Ring Resizer -> Metal Weights + Gem Report -> Render -> Collections -> Projects -> Animation/Movie. The first three are what a jeweller uses daily; the last three are what sells the product.

---

## 4. Converters are behaviour, not cosmetics

The 107 converters encode domain rules. These are the ones with product meaning:

| Converter | Rule it encodes |
|---|---|
| `BooleanToDwtGramsConverter`, `BoolToUnitWeightConverter` | Weight shown in **pennyweight (dwt) or grams** per user preference |
| `FingerSizeComboBoxSizeVisibilityConverter`, `FingerSizeTextInputVisibilityConverter` | Ring size can be chosen by number **or** by measured text input |
| `GemShapeAndCutToIconConverter`, `GemCutToIconConverter`, `GemShapeNameToVectorGraphicConverter` | Stone picker is visual; shape+cut determine the icon |
| `HSLToSolidColorBrushConverter`, `HSLToLinearSolidGradientBrushConverter`, `HexColorToBrushConverter`, `IntColorToBrushConverter` | Material colour is authored in HSL, stored as int/hex |
| `EnumToLocalizedStringConverter`, `EnumDescriptionConverter` | Every enum is user-facing text and must be localised |
| `CollectionFolderTutorialVisibilityConverter` | First-run tutorial affordances |
| `IsLockedLayerToResourceConverter`, `IsVisibleLayerToResourceConverter`, `ExtraLayerGroupVisibilityConverter` | Layer tree state icons |
| `BuilderAndSliderToIconResourceConverter`, `ComboboxToIconResourceConverter` | Parameter controls carry icons derived from value+state |
| `ContextActionNameLocalizationConverter` | Context menu localisation |
| `IsFloatingToUIScaleConverter`, `DoubleToGridLengthConverter` | Docking/panel sizing |

**Port rule:** do not translate converters one-by-one into view code. Each converter above becomes either (a) a computed property on the model, or (b) a formatting concern in a `Formatter` type. Units (dwt/grams, mm/inch) belong in a `UnitSystem` value passed through the environment, not inside views.

---

## 5. Shell, docking and commands

* **Shell**: `MainViewModel` (183) + `ToolRibbonViewModel` (126) + `ViewToolRibbon` + kebab menus (`CommandKebabCommand`, `CommandToggleKebabMenu`). The app exposes hundreds of commands; most are only reachable from context menus and the ribbon.
* **Docking**: Actipro `Docking.Wpf` (312 types) + Xceed `AvalonDock` (389) — two docking libraries, i.e. a legacy migration mid-flight. Panels are floatable (hence `IsFloatingToUIScaleConverter`).
* **Layers**: `LayersViewModel` (57), `GroupLayerItem`, `LayerViewItem`, `CommandLockLayer`, `CommandSelectLayer`, `CommandIsolateSelected`, `CommandHideSelected`, `CommandShowSelected`, `CommandShowAll`, `CommandSetAsActiveLayer`, `CommandEnableLayerUnique`.
* **Job bags**: `JobBagType`, `CommandImportJobBag`, `CommandExportJobBag`, `CommandForceImportJobBag`, `CommandForceOpenJobBag`, `CommandDeleteJobBag`, `CommandSetJobbagFilter`, `CommandRenameJobBag`. A "job bag" is the manufacturing order (Stuller integration); projects and job bags are related but distinct.
* **Animation**: `AnimationPreset`, `CommandModifyCameraPath`, scrub control (`CommandScrubControl`), `MovieFrameGroup`.
* **Undo**: WPF command infrastructure + `CSUndoTable` (Dossier 02); iOS must use `UndoManager` with the same per-object granularity.

---

## 6. iOS/SwiftUI architecture

```
App
 ├ DocumentStore (@Observable)          // CSDocument equivalent
 ├ GraphEngine (actor / serial queue)   // evaluation, cancellation
 ├ ViewportView (RealityKit / Metal)    // tessellated B-rep cache
 ├ InspectorPanel                       // builder parameters
 ├ BlockOutliner                        // layers/categories
 ├ CommandPalette                       // 1,168 binding paths -> actions
 └ Reports (weights, gems, cost)
```

Layout for iPadOS:
* `NavigationSplitView` — sidebar = block outliner/categories; detail = viewport; **inspector = right column** (this maps 1:1 to the builder panel).
* Compact width (iPhone): viewport full-bleed, inspector as a `.sheet` with detents; command palette as search.
* Pencil: freehand curve input and direct manipulation gumball. MatrixGold's `FreehandComponentsVisible` user-data flag confirms freehand is a first-class mode.
* Selection: `CommandManageMultiSelectedItems`, `SuperSelectViewModel` (31) -> multi-select with a context menu (`ObjectContextMenu*`, 5 types).
* Units: `WindowPreferences` holds unit scale; surface dwt/grams and mm/inch everywhere.

**What not to port:** the docking system (replace with fixed tri-pane), WPF `DataTemplateSelector` machinery (replace with `@ViewBuilder` switch), and the 107 converters as types.

---

## 7. Accessibility and localisation hooks

The original ships **18 locales** and every enum is localised through `EnumToLocalizedStringConverter` / `ContextActionNameLocalizationConverter`. Two consequences:

1. Design strings as `LocalizedStringKey` from day one; do not hardcode English labels in views.
2. Dynamic Type: 1,168 binding paths include fixed widths (`BuilderWidthConverter`, `ElementWidthConverter`). Replace fixed widths with layout priorities so accessibility sizes do not clip.

---

## 8. Evidence

* XAML: `03-decompiled/xaml/` (117 files), inventory `04-index/xaml-bindings.csv`.
* Bindings summary: `04-index/summary.csv`, `04-index/coverage.csv`.
* Decompiled UI: `03-decompiled/raw/MatrixGold/MatrixGold.Views/**`, `MatrixGold.ViewModels/**`, `MatrixGold.Converters/**`.

```sql
select full_name, count(*) from properties p join types t on t.id=p.type_id
where t.namespace like 'MatrixGold.ViewModels%' group by t.id order by 2 desc;
```
