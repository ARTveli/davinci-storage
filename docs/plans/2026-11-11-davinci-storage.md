# DaVinci Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Native macOS app (+ CLI) that maps DaVinci Resolve leftovers (cache, backups, stills, Magic Mask, proxies, service caches) to projects by UUID and moves selected ones to the Trash.

**Architecture:** SwiftPM package. `StorageCore` library (config parsing, read-only SQLite project reader, filesystem scanner, analyzer, cleaner) is shared by a CLI (`davinci-storage report`) and a SwiftUI app. Everything links on project UUID (`SM_Project.SM_Project_id`) or on paths stored inside `Project.db`.

**Tech Stack:** Swift 6.4 (CLT only, no Xcode), SwiftPM, `import SQLite3`, SwiftUI/AppKit, Swift Testing (`import Testing`). Language mode v5 to avoid strict-concurrency friction.

**Spec:** `docs/specs/2026-11-11-davinci-storage-design.md`

## Global Constraints
- macOS 27 / Apple Silicon; `platforms: [.macOS(.v14)]`; build with `swift build`, test with `swift test`; no third-party dependencies.
- Project databases are **read-only**: open with `sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)` on URI `file:<path>?mode=ro`. Never write anywhere inside a library folder.
- Deletion = `FileManager.default.trashItem(at:resultingItemURL:)` only. Never `removeItem`.
- Cleanup disabled while an app with bundle id `com.blackmagic-design.DaVinciResolve` is running.
- UI language Ukrainian. Section titles exactly: «Проєкти», «Видалені проєкти і дублі», «Службові кеші». Button: «Перемістити в Кошик…». Filter: «старші за N місяців» (default 3).
- Code lives in `/Users/artveli/CLAUDE_PROJECT/DAVINCI_STORAGE`; app installed to `~/Applications/DaVinci Storage.app`, bundle id `pro.artveli.davinci-storage`, ad-hoc signed (`codesign -s -`).
- All path comparisons use `standardizedFileURL.path.precomposedStringWithCanonicalMapping` (Cyrillic folder names, NFD vs NFC).

## Review Focus
1. A `Project.db` that cannot be read (locked, corrupt) → none of the leftovers can be proven "deleted"; deleted groups are marked `uncertain` and not preselected. (Task 5 test `unreadableProjectMakesDeletedUncertain`)
2. Magic Mask folder named differently from its project (real data: FC27_DIR_CUT → `MAGIC_MASK_2_DAVINCI/АС27_ВШК_СГЕ/Magic Mask`, UNDER_ARMOR → `UNDDER_ARMOR`) → attributed to the project, never listed as deleted. (Task 4 test `magicMaskAttributedByDbPathNotName`)
3. Two projects referencing the same Magic Mask dir (UNDER_ARMOR + UNDER_ARMOR_DIR_CUT) → one item with both project IDs, counted once in totals. (Task 5 test `sharedItemCountedOnce`)
4. A Cyrillic path in NFD on disk vs NFC in the DB still matches. (Task 4 test `nfdPathMatchesNfcReference`)
5. Item vanishes between scan and cleanup → reported as failed, no crash, others still trashed. (Task 6 test `missingItemReportedAsFailure`)

## File Structure
```
Package.swift
Sources/StorageCore/Model.swift          – Category, MatchKind, Library, Project, StorageItem, Report types
Sources/StorageCore/ResolveConfig.swift  – parse dblist.conf / config.user.xml
Sources/StorageCore/Locations.swift      – all scan roots (real defaults + test init)
Sources/StorageCore/ProjectReader.swift  – find + read Project.db (SQLite3, read-only)
Sources/StorageCore/DirectorySize.swift  – allocated size of a file/dir (du-like)
Sources/StorageCore/StorageScanner.swift – produce [StorageItem]
Sources/StorageCore/Analyzer.swift       – build Report
Sources/StorageCore/Cleaner.swift        – validate + trash
Sources/StorageCore/ReportPrinter.swift  – text table for CLI
Sources/davinci-storage/main.swift       – CLI entry
Sources/DaVinciStorageApp/*.swift        – SwiftUI app
Tests/StorageCoreTests/*.swift           – Swift Testing + Fixtures.swift (temp dirs, SQLite fixture builder)
scripts/build-app.sh                     – bundle .app into ~/Applications
```

---

### Task 1: Package skeleton + model + config parsing

**Files:** Create `Package.swift`, `Sources/StorageCore/Model.swift`, `Sources/StorageCore/ResolveConfig.swift`, `Tests/StorageCoreTests/ResolveConfigTests.swift`

**Interfaces – Produces:**
```swift
public enum Category: String, CaseIterable, Sendable { case cache, backups, stills, magicMask, proxy, service }
public enum MatchKind: Sendable { case uuidFolder, dbPath, stillID, byName, unlinked }
public struct Library: Hashable, Sendable { public let name: String; public let root: URL }
public struct Project: Hashable, Sendable { id: String /*lowercased UUID*/; name: String; library: String; dbURL: URL; lastModified: Date; stillIDs: Set<String>; magicMaskDirs: Set<String> /*normalized paths*/ }
public struct StorageItem: Hashable, Sendable { category: Category; url: URL; bytes: Int64; projectIDs: [String]; match: MatchKind; label: String }
public struct ResolveConfig: Sendable { libraries: [Library]; backupRoot: URL? }
public enum ResolveConfigParser {
  static func parseDBList(_ text: String) -> [Library]          // only entries whose last field is DISK
  static func parseBackupLocation(_ xml: String) -> String?     // <ProjectBackupLocation> trimmed
  static func load(prefsDir: URL) throws -> ResolveConfig
}
public func normalizedPath(_ url: URL) -> String
```

- [ ] **Step 1: Failing tests** (`ResolveConfigTests`)
  - `parseDBListReadsDiskLibraries`: input `"2026_new:/Users/artveli/DAVINCI_DATA_BASE:*:::DISK\nARTveli_COLOR_COURSE:/Users/artveli/DAVINCI_DATA_BASE/ARTveli_COLOR_COURSE::::DISK\nPG:host:5432:::PG\n"` → 2 libraries, names `["2026_new","ARTveli_COLOR_COURSE"]`, roots match.
  - `parseBackupLocationTrimsNewline`: `"<ProjectBackupLocation>/Users/artveli/Movies/Resolve Project Backups\n</ProjectBackupLocation>"` → `"/Users/artveli/Movies/Resolve Project Backups"`.
  - `parseBackupLocationMissingIsNil`.
- [ ] **Step 2:** `swift test --filter ResolveConfigTests` → fails (types missing).
- [ ] **Step 3:** Implement. `Package.swift`: tools 6.0, targets `StorageCore`, executable `davinci-storage`, executable `DaVinciStorageApp`, test target `StorageCoreTests`; `swiftLanguageModes: [.v5]`. `load` reads `dblist.conf` and `config.user.xml` from `prefsDir`.
- [ ] **Step 4:** `swift test --filter ResolveConfigTests` → PASS.
- [ ] **Step 5:** Commit `feat: package skeleton, model, Resolve config parser`.

### Task 2: ProjectReader (read-only SQLite) + fixture builder

**Files:** Create `Sources/StorageCore/ProjectReader.swift`, `Tests/StorageCoreTests/Fixtures.swift`, `Tests/StorageCoreTests/ProjectReaderTests.swift`

**Interfaces:**
- Consumes: `Library`, `Project`, `normalizedPath` (Task 1)
- Produces:
```swift
public enum ProjectReadError: Error { case open(String), query(String), noProjectRow }
public enum ProjectReader {
  static func findProjectDBs(in library: Library) -> [URL]   // <root>/Resolve Projects/Users/*/Projects/**/Project.db
  static func read(dbURL: URL, library: String) -> Result<Project, ProjectReadError>
  static func extractMagicMaskDirs(from blob: [UInt8]) -> Set<String>
}
// Fixtures (test target):
func makeTempDir() -> URL
func makeProjectDB(at url: URL, id: String, name: String, lastMod: Int64, stillIDs: [String], clipBlobs: [[UInt8]]) throws
```
Data sources (verified): `SM_Project(SM_Project_id, ProjectName, LastModTimeInSecs)`; `"Gallery::GyStill"("Gallery::GyStill_id")`; `BtVideoInfo(Clip BLOB)`. Magic Mask dirs = regex over raw blob bytes `/(?:Users|Volumes)/[^\x00-\x1f]*?/Magic Mask` (blobs are zstd frames with raw blocks; paths appear verbatim). Decode UTF-8, normalize.

- [ ] **Step 1: Failing tests**
  - `readsIdNameAndDate`: fixture id `"585BBD4A-BA19-4D98-B863-18E2F5F4B8C0"`, name `"UKRAVIT"`, lastMod `1794331426` → `id == "585bbd4a-ba19-4d98-b863-18e2f5f4b8c0"`, `lastModified == Date(timeIntervalSince1970: 1794331426)`.
  - `readsStillIDs`: 2 still ids → `stillIDs.count == 2`, lowercased.
  - `extractsMagicMaskDirFromBlob`: blob bytes `[0,0,0,2] + "\n7/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask\u{12}\u{1b}Ukravit_02.mov"` → `["/Users/artveli/DaVinci Resolve Media/UKRAVIT/Magic Mask"]`.
  - `extractsCyrillicMagicMaskDir`: `/Users/artveli/MAGIC_MASK_2_DAVINCI/АС27_ВШК_СГЕ/Magic Mask` extracted intact.
  - `missingFileIsError`: nonexistent path → `.failure`.
  - `findsNestedProjects`: library with `Projects/AD/A/Project.db` and `Projects/B/Project.db` → 2 URLs.
  - `readDoesNotModifyDB`: file mtime and bytes identical before/after `read`.
- [ ] **Step 2:** run → fail.
- [ ] **Step 3:** Implement with `SQLite3`; missing tables (e.g. no BtVideoInfo) are not errors → empty sets.
- [ ] **Step 4:** `swift test --filter ProjectReaderTests` → PASS.
- [ ] **Step 5:** Commit `feat: read-only Project.db reader`.

### Task 3: Locations + DirectorySize

**Files:** Create `Sources/StorageCore/Locations.swift`, `Sources/StorageCore/DirectorySize.swift`, `Tests/StorageCoreTests/DirectorySizeTests.swift`

**Interfaces – Produces:**
```swift
public struct Locations: Sendable {
  public var cacheRoots: [URL]; public var backupRoot: URL?; public var galleryProjectRoot: URL; public var galleryLegacyRoot: URL
  public var magicMaskRoots: [URL]; public var proxyRoots: [URL]; public var serviceItems: [(label: String, url: URL)]
  public static func real(home: URL, config: ResolveConfig) -> Locations
}
public func allocatedSize(of url: URL) -> Int64   // sum of totalFileAllocatedSize, recursive, 0 if missing
```
Real defaults (S = `/Library/Application Support/Blackmagic Design/DaVinci Resolve`, U = `~/Library/Application Support/Blackmagic Design/DaVinci Resolve`):
cacheRoots `~/Movies/CacheClip`, `S/CacheClip`; backupRoot from config; galleryProjectRoot `~/Movies/.gallery`; galleryLegacyRoot `S/.gallery`; magicMaskRoots `~/MAGIC_MASK_2_DAVINCI`, `~/DaVinci Resolve Media`; proxyRoots `S/ProxyMedia`, `~/Movies/ProxyMedia`, `~/Movies/CacheClip/OptimizedMedia`, `~/Movies/CacheClip/ProxyMedia`; serviceItems `("LUT-кеш (.LUT)", U/.LUT)`, `("Кеш програми", ~/Library/Caches/com.blackmagic-design.DaVinciResolve)`.

- [ ] **Step 1: Failing tests** `sizeOfMissingIsZero`; `sizeSumsNestedFiles` (two 4096-byte files in nested dirs → `>= 8192`).
- [ ] **Step 2–4:** fail → implement (`FileManager.enumerator(at:includingPropertiesForKeys:[.totalFileAllocatedSizeKey,.isRegularFileKey])`) → PASS.
- [ ] **Step 5:** Commit `feat: scan locations and directory size`.

### Task 4: StorageScanner

**Files:** Create `Sources/StorageCore/StorageScanner.swift`, `Tests/StorageCoreTests/StorageScannerTests.swift`

**Interfaces:** Consumes `Locations`, `Project`, `allocatedSize`. Produces `public func scanStorage(_ loc: Locations, projects: [Project]) -> [StorageItem]`.

Rules:
- cache/backups: each subdir of cacheRoots/backupRoot whose name parses as `UUID` → item `.uuidFolder`, `projectIDs [lowercased name]`, label = project name or the UUID. Non-UUID subdirs (`audio`, `OptimizedMedia`) ignored.
- stills: each `galleryProjectRoot/<UUID>` → `.uuidFolder`; label from `Info.txt` line `Project Name: …` when present. Legacy root: files `<uuid>.dpx` whose stem is in some project's `stillIDs` → one item per file (`.stillID`, projectIDs [that project], label "Стіл <project name>"); unmatched dpx → one item per file, `.unlinked`.
- magicMask: for each distinct dir in `projects.flatMap(magicMaskDirs)` that exists → item `.dbPath`, `projectIDs` = all projects referencing it. Then for each subdir X of each magicMaskRoot: if X (or X/"Magic Mask") is already claimed → skip; else item url = X, `.byName` if X's name equals a project name (case-insensitive), else `.unlinked`, label = X's name. Skip empty dirs (0 bytes).
- proxy: subdirs of proxyRoots → `.byName` / `.unlinked` like above.
- service: one item per `serviceItems` entry that exists, `projectIDs []`, `.unlinked`, category `.service`.

- [ ] **Step 1: Failing tests** (build a temp tree mirroring real layout):
  - `cacheFolderMappedByUUID`
  - `nonUUIDCacheFoldersIgnored` (`audio`)
  - `galleryInfoTxtGivesLabel` (`Project Name: COURSE_TEST` → label `COURSE_TEST`)
  - `magicMaskAttributedByDbPathNotName`: project FC27_DIR_CUT references `<root>/АС27_ВШК_СГЕ/Magic Mask` → item has that project id, match `.dbPath`; no `.unlinked` item for `АС27_ВШК_СГЕ`.
  - `unreferencedMagicMaskIsUnlinked`: `<root>/PROM_709` with a file, no project → `.unlinked`, label `PROM_709`.
  - `nfdPathMatchesNfcReference`: create dir with `"АС27_ВШК_СГЕ".decomposedStringWithCanonicalMapping`, project references NFC form → claimed.
  - `legacyStillMatchedByStillID`.
- [ ] **Step 2–4:** fail → implement → `swift test --filter StorageScannerTests` PASS.
- [ ] **Step 5:** Commit `feat: storage scanner`.

### Task 5: Analyzer

**Files:** Create `Sources/StorageCore/Analyzer.swift`, `Tests/StorageCoreTests/AnalyzerTests.swift`

**Interfaces – Produces:**
```swift
public struct ProjectRow: Identifiable, Sendable { id: String; project: Project; items: [StorageItem]; bytes: [Category: Int64]; total: Int64 }
public struct LeftoverGroup: Identifiable, Sendable { id: String; title: String; reason: String; items: [StorageItem]; total: Int64; uncertain: Bool }
public struct Report: Sendable { rows: [ProjectRow]; deleted: [LeftoverGroup]; duplicates: [LeftoverGroup]; service: [StorageItem]; unreadable: [URL]; grandTotal: Int64 }
public func analyze(projects: [Project], unreadable: [URL], items: [StorageItem]) -> Report
public func scanAll(home: URL, prefsDir: URL) -> Report   // config → projects → locations → scan → analyze
```
Rules: item with ≥1 known project id → that project's row(s) (bytes added to each row, `grandTotal` counts each item once by url). Items whose ids are all unknown, or `.unlinked`/`.byName`-unknown → `deleted`, grouped by id (or label), reason Ukrainian e.g. «проєкту з таким ID немає в жодній базі» / «жоден проєкт не посилається на цю папку». Duplicates: an unlinked magicMask item whose set of (filename, size) overlaps ≥ 90 % of a claimed magicMask item's set → moved from `deleted` to `duplicates`, title «Копія: <label>», reason «ті самі файли, що й у <claimed path>». All `deleted` groups get `uncertain = !unreadable.isEmpty`.

- [ ] **Step 1: Failing tests**
  - `itemsGroupedIntoProjectRows` (bytes per category correct)
  - `unknownUUIDGoesToDeleted`
  - `sharedItemCountedOnce`: one item with 2 project ids, 100 bytes → both rows show 100, `grandTotal == 100`.
  - `magicMaskCopyDetectedAsDuplicate` (unlinked dir with same 3 files as claimed dir → in `duplicates`, not in `deleted`).
  - `unreadableProjectMakesDeletedUncertain`.
- [ ] **Step 2–4:** fail → implement → PASS.
- [ ] **Step 5:** Commit `feat: analyzer`.

### Task 6: Cleaner

**Files:** Create `Sources/StorageCore/Cleaner.swift`, `Tests/StorageCoreTests/CleanerTests.swift`

**Interfaces – Produces:**
```swift
public enum CleanerRefusal: Error, Equatable { case outsideAllowedRoots, isRoot, insideLibrary, notFound }
public struct CleanResult: Sendable { trashed: [URL]; failed: [(URL, String)] }
public struct Cleaner { init(allowedRoots: [URL], libraryRoots: [URL], trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })
  func validate(_ url: URL) -> CleanerRefusal?
  func clean(_ urls: [URL]) -> CleanResult }
public extension Locations { var allowedRoots: [URL] }   // all roots + serviceItems urls; project magicMaskDirs added by caller
```
Symlinks resolved (`resolvingSymlinksInPath`) before checks. A url equal to a root is refused (`isRoot`) except service item urls (they are deletable as a whole).

- [ ] **Step 1: Failing tests** `refusesOutsideRoots` (`/Users/x/Documents/a`), `refusesRootItself`, `refusesInsideLibrary`, `refusesSymlinkEscapingRoot`, `trashesAllowedItem` (injected trash closure records the url), `missingItemReportedAsFailure` (2 urls, one deleted before clean → 1 trashed, 1 failed).
- [ ] **Step 2–4:** fail → implement → PASS.
- [ ] **Step 5:** Commit `feat: safe cleaner (Trash only)`.

### Task 7: CLI report + real-data check

**Files:** Create `Sources/StorageCore/ReportPrinter.swift`, `Sources/davinci-storage/main.swift`, `Tests/StorageCoreTests/ReportPrinterTests.swift`

**Interfaces:** Produces `public func renderReport(_ r: Report) -> String`; sizes via `ByteCountFormatter` (`.file`). CLI: `davinci-storage report` → prints; anything else → usage.

- [ ] **Step 1:** Test `rendersSectionsAndTotals`: output contains «Проєкти», «Видалені проєкти і дублі», «Службові кеші», project name, and the formatted grand total.
- [ ] **Step 2–4:** fail → implement → PASS.
- [ ] **Step 5: Real-data verification:** `swift run davinci-storage report`. Expected (from manual survey on 2026-11-11): UKRAVIT has cache (~118 MB) + backups (~63 MB) + Magic Mask at `~/DaVinci Resolve Media/UKRAVIT/Magic Mask` (~5.3 GB); FC27_DIR_CUT owns `АС27_ВШК_СГЕ`; UNDER_ARMOR + DIR_CUT share `UNDDER_ARMOR`; deleted includes ANTYTILA_OK, ARTEM_RID, BOLT_NY_2026, FC_JJ, HEAD_SHAKER_JAPAN, PROM_709, KORAIL_MAQUETTE (MAGIC_MASK_2 copy); duplicates include `MAGIC_MASK_2_DAVINCI/UKRAVIT`; `.LUT` ≈ 4.5 GB. Spot-check 3 numbers with `du -sh`.
- [ ] **Step 6:** Commit `feat: CLI report`. **Checkpoint: show report to Artem before UI.**

### Task 8: SwiftUI app

**Files:** Create `Sources/DaVinciStorageApp/DaVinciStorageApp.swift`, `AppModel.swift`, `ProjectsView.swift`, `LeftoversView.swift`, `ServiceView.swift`, `CleanupBar.swift`

**Interfaces:** Consumes `scanAll`, `Report`, `Cleaner`, `Locations.allowedRoots`.
- `AppModel: ObservableObject` — `@Published report: Report?`, `isScanning`, `selected: Set<URL>`, `monthsFilter: Int = 3`, `resolveRunning: Bool` (NSWorkspace `runningApplications` + `didLaunch/didTerminate` notifications); `rescan()` runs `scanAll` off main thread; `selectOlderThanFilter()`; `trashSelected() -> CleanResult` then `rescan()`.
- Window: `NavigationSplitView`, sidebar three sections (exact titles). Projects: `Table` with sortable columns Назва · Бібліотека · Остання зміна · Кеш · Бекапи · Стіли · Magic Mask · Проксі · Разом; toggle per row; toolbar Stepper «старші за N місяців» + button «Позначити старі». Leftovers: list of groups with reason, «неточно» badge for `uncertain`/`.byName`; uncertain groups never auto-selected. Service: items with explanation for `.LUT` «DaVinci відтворить цей кеш сам при наступному використанні LUT»; plus a static row «Frame.io — папку ще не знайдено (з'явиться після першого рендеру в Frame.io)». Toolbar button «Сканувати знову» → `rescan()`.
- `CleanupBar`: «Вибрано: X» + «Перемістити в Кошик…» (disabled when nothing selected or `resolveRunning`); orange banner «Закрий DaVinci Resolve, щоб очищати» when running; confirmation sheet lists every path; after cleaning shows trashed/failed counts.

- [ ] **Step 1:** `swift build --product DaVinciStorageApp` → succeeds.
- [ ] **Step 2:** Commit `feat: SwiftUI app`.

### Task 9: App bundle + visual check

**Files:** Create `scripts/build-app.sh`, `Resources/Info.plist`

- [ ] **Step 1:** Script: `swift build -c release --product DaVinciStorageApp`; assemble `~/Applications/DaVinci Storage.app/Contents/{MacOS/DaVinciStorageApp,Info.plist}`; `CFBundleIdentifier pro.artveli.davinci-storage`, `CFBundleName "DaVinci Storage"`, `LSMinimumSystemVersion 14.0`, `NSHighResolutionCapable true`; `codesign --force -s - "…app"`.
- [ ] **Step 2:** Run script → `codesign -v` passes; `open ~/Applications/"DaVinci Storage.app"`.
- [ ] **Step 3:** Screenshot each section; numbers match the CLI report; Cleanup button disabled while Resolve runs.
- [ ] **Step 4:** Commit `build: app bundle script`.
