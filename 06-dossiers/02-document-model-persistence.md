# Dossier 02 — Document Model & Persistence

**Status:** implementation-grade · **Evidence:** `CS.dll` (653 types / 7,550 methods), `CS.JSonDoc`, `CSDatas`, decompiled bodies of `CSDocument.Read/Write` and `JSonDocumentReader/Writer`
**Headline finding:** a MatrixGold design is **JSON** (`.json`) or **gzipped JSON** (`.csj`). It is *not* a `.3dm` file. This removes the single biggest risk from the iOS port — no Rhino file-format dependency for documents.

---

## 1. Two documents, one design

| Layer | Type | Owns |
|---|---|---|
| **Design document** | `CS.CSDocument` | `Graph` (`CSParaGraph`), `GemTable`, `UndoTable`, `DocumentUserData`, `DocumentIterations`, `CategoryTable`, `Filename`, display flags |
| **Geometry host** | Rhino document (`RhinoDoc.ActiveDoc`) | Tessellation, viewport, selection, `.3dm` interchange for content/components |

The design is authoritative. Rhino is a renderer/geometry host. On iOS, the `CSDocument` equivalent is the app's single source of truth; there is no host document.

`CSDocument` public state (17 properties, all recovered):
`Filename`, `Graph`, `GemTable`, `UndoTable`, `DocumentUserData`, `DocumentIterations`, `CurrentDisplayComponents`, `FileGuidList`, `IsReloading`, `SetupTemplateName`, `EnablePreviewRenderShading`, `IsWireframeQuickUpdateEnabled`, `DrawingObjectsEnabled`, `DrawingCurvesEnabled`, `DrawingPointsEnabed`, `DrawingStartsEnabed`, `DrawingBackfacesEnabled`.

---

## 2. File format (exact)

`CSDocument.Read(string filePath)` accepts **only** `.json` and `.csj`; anything else throws `ArgumentException("Invalid file format. Valid formats are .json and .csj")`.

```
.json : UTF-8 JSON text, first byte '{' (0x7B)
.csj  : [0x7A 0x00 0x00] [gzip stream of UTF-8 JSON] [int32 LE uncompressedLength]
```

Read algorithm, verbatim:
1. Read first 3 bytes.
2. If `byte[0] == 123` ('{'): read whole file as text.
3. Else if `byte[0] != 122` ('z'): return false (corrupt).
4. Else: seek to `-4` from end, read `int32` uncompressed length, seek to offset 3, wrap in `GZipStream`, read exactly that many bytes, UTF-8 decode.
5. `JSonDocumentReader.ReadCSFile(json, Graph, DocumentUserData, GemTable, DocumentIterations, BlockList, out fileGuidList)`.
6. `PostRead()`.

Write algorithm:
* `.json` -> `JObject.ToString()` written as text (UTF-8, indented by Newtonsoft default).
* `.csj` -> 3-byte header `7A 00 00`, then `GZipStream` over the UTF-8 JSON. **Note:** the writer in this build does not append the 4-byte length trailer that the reader expects. Treat the trailer as optional when reading (fall back to reading the gzip stream to EOF) and always write it for your own files. This asymmetry is a real compatibility bug in the original and must be handled, not reproduced.

iOS: `JSONSerialization`/`Codable` for `.json`; `Compression` framework (zlib raw deflate inside gzip wrapper) or `libcompression` gzip for `.csj`. Preserve the magic and trailer exactly so files round-trip between platforms.

---

## 3. Document schema

`JSonDocumentWriter.WriteCSFile` emits exactly these top-level keys, in this order:

| Key | Writer | Reader | Content |
|---|---|---|---|
| `PreviewBitmap` | `CSUtilIO.BitmapToString` | ignored | Base64 PNG preview (CounterSketch/StyleSheet saves) |
| `StyleSheetDescription` | string | ignored | Style-sheet metadata |
| `FileInformation` | `CSFileInformation` | `ReadFileInformation` | `Name:"Render"`, `Company:"Gemvision"`, `Year`, `Month`, `Day`, `Revision`, `GuidList` |
| `DocumentIterations` | `GCIterations.WriteJson` | `.ReadJSon` | Iteration/parametric history state |
| `MaterialGroups` | `MaterialGroupHelper.WriteJson` | `.ReadJson` | Material group table (Dossier 06) |
| `ImportedObjects` | `graph.WriteImportedObjectJson` | `graph.ReadImportedObjectDataJson` | Imported/reference geometry records |
| `DocumentUserData` | `CSUserData.WriteJSon` | `.ReadJSon` | Sectioned key/value store (`Display/CurrentComponents`, `Display/FreehandComponentsVisible`, `UI/Template`, ...) |
| `GemTable` | `gemTable.WriteJSon` | `gemTable.ReadJson` | Gem instances in the design |
| `CategoryTable` | `graph.CategoryTable.WriteJSon` | `.ReadJson` | UI/outliner categories |
| `Graph` | `graph.WriteGraphItemsJSon(blockList, activeOnly: true, selection)` | `graph.ReadGraphItemsJson` | The parametric blocks |

Writer ordering matters for byte-comparable diffs but not for correctness. Reader tolerance matters: it indexes by key, so unknown keys are ignored and missing optional keys must not crash.

---

## 4. The graph container (`CSParaGraph`)

`CSParaGraph` (91 methods) is the in-memory design. Recovered public surface:

| Member | Role |
|---|---|
| `Add(CSObject)`, `Delete(CSObject)`, `Clean()` | Mutation, with tombstone cleanup |
| `AllObjects()`, `ActiveObjects()`, `ActiveOutputObjects()`, `DisplayObjects()` | Enumeration for save/regenerate/draw |
| `ActiveObjectsWithGuid(IEnumerable<Guid>)` | Selection resolution |
| `FindAllChildren(CSObject, List<...>)`, `FindAllGroupChildren(...)` | Dependency traversal |
| `Generate(bool)`, `GenerateAll()`, `GenerateConcurrent(bool)` | Evaluation entry points |
| `AddCustomObjectsJustUpdated(int)` | Pushes regenerated custom objects into the Rhino document |
| `BlockDescriptionSearch(IReadOnlyList<...>)` | Maps saved block type strings to registered block factories |
| `RemoveDeleted()` | Called immediately before serialisation |

**Serialisation rule:** objects marked `Deleted` exist in memory until `RemoveDeleted()`; only active items are written (`activeOnly: true`). A port that serialises tombstones produces files the original cannot open cleanly (duplicate GUIDs).

---

## 5. Import, merge and identity

`JSonDocumentReader.ImportCSFile` is a separate path from `ReadCSFile`, and it is the *only* correct model for "open a component into an existing design":

1. `Application.InImport = true`, `Application.ImportOffset = Document.Graph.GraphList.Count` (a positional offset applied to imported graph references).
2. Reads `FileInformation`, `DocumentIterations`, `MaterialGroups`, `ImportedObjects`, `DocumentUserData`.
3. Builds a **temporary** `CSGemInstanceDefinitionTable` and `CSUICategoryTable`, then **merges** gems into the document table and appends categories.
4. `graph.ReadGraphItemsJson(..., isFreehandPart, documentUserData, importedCategories)`.
5. `ImportCategories` / `ImportOffset` reset to 0.

GUID collision is handled by three lookup dictionaries:
`RhinoObjectGuidsLookup`, `BlockGuidsLookup`, `PatchwireIdentifierGuidsLookup`, all `Dictionary<Guid,Guid>` with `dictionaryLookup(lookup, find)` returning the remapped GUID when present. Any importer must remap **block IDs, patchwire IDs and Rhino object IDs independently**; a single global remap corrupts cross-references.

---

## 6. Undo, iterations and integrity

* **Undo**: `CSUndoTable` on the document; each object participates via `CSObject.SetUndo(CSObject)`. Undo entries store pre-edit state per object, not per command. `UndoTable.Reset()` is called on new document.
* **Iterations**: `GCIterations` (`DocumentIterations`) stores the generative-history state; `CleanUp()` is called on both read and write, so stale iterations are pruned silently.
* **Integrity checks available**: `TestDuplicateGuids()`, `RemoveUnusedGeometry()`, `CheckFontSourceErrors(...)`, `CheckObsoleteFontSourceErrors(...)`, `CategoryTableRemoveDupes()`.
* **Post-load**: `PostRead()` re-links parents, rebuilds category indexes, and validates fonts; failure is surfaced as a toast (`MatrixEventHelper.RaiseShowToastMessageWarningEvent`), not an exception. The document still opens. Match this: a design with missing fonts must open with a warning, never fail.
* **`PostProcessFile(bool)`** performs the final cleanup pass; `StartGenerate(bool)` kicks evaluation; `InterruptUpdate(double offsetInMs)` aborts an update if it exceeds 100 ms + offset — the responsiveness mechanism for large designs.

---

## 7. iOS mapping

```
Document (Codable)
 ├ fileInformation: FileInformation
 ├ documentIterations: IterationState
 ├ materialGroups: [MaterialGroup]
 ├ importedObjects: [ImportedObject]
 ├ documentUserData: UserDataStore        // section -> key -> value
 ├ gemTable: [GemRecord]
 ├ categoryTable: [Category]
 └ graph: [BlockRecord]                   // type + id + channels + params
```

Rules:
1. **Decode by key, never by order.** Unknown keys ignored; missing optional keys defaulted.
2. **Preserve GUIDs verbatim** and implement the three remap tables for import.
3. **`BlockRecord.type` is the assembly-qualified type name**; map it through a registry, and keep unknown types as opaque records so a newer file opens read-only instead of failing.
4. **Do not re-serialise a document you only viewed.** Round-trip fidelity requires `RemoveDeleted`, channel index preservation and the exact `FileInformation` block; partial writers corrupt originals.
5. **File coordination/iCloud**: use `NSFileCoordinator` and write atomically (temp + rename). The original writes directly, which can truncate on crash.

**Acceptance test for this dossier:** take 20 real design files, `Read` -> `Write` -> `Read` in the iOS model and diff the canonical JSON (excluding `PreviewBitmap` and key order). Zero semantic differences required.

---

## 8. Evidence

Decompiled: `03-decompiled/raw/CS/CS/CSDocument.cs` (615 lines), `03-decompiled/raw/CS/CS.JSonDoc/JSonDocumentReader.cs`, `JSonDocumentWriter.cs`.

```sql
select m.name, m.signature from methods m join types t on t.id=m.type_id
where t.full_name='CS.CSDocument' and m.is_obf=0 order by m.name;

select m.name, m.signature from methods m join types t on t.id=m.type_id
where t.full_name='CS.CSParaGraph' and m.is_obf=0 order by m.name;
```
