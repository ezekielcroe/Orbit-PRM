# Orbit: A Text-Prominent Personal Relationship Manager

## Quick Start — Setting Up in Xcode

### 1. Create a New Project

1. Open Xcode → **File → New → Project**
2. Choose **Multiplatform → App**
3. Product Name: `Orbit`
4. Team: Your Apple Developer account
5. Organization Identifier: `com.yourname` (e.g., `com.johndoe`)
6. Interface: **SwiftUI**
7. Storage: **None** (we configure SwiftData manually)
8. Check **Include Tests** (optional but recommended)
9. Click **Create**

### 2. Add Source Files

1. Delete the auto-generated `ContentView.swift` and `OrbitApp.swift` (or `Item.swift` if present)
2. In the project navigator, right-click the `Orbit` folder → **Add Files to "Orbit"**
3. Navigate to the downloaded source files and add the entire directory structure:

```
Orbit/
├── OrbitApp.swift              ← App entry point
├── Models/
│   └── OrbitSchema.swift       ← SwiftData models + versioned schema
├── Parser/
│   ├── Token.swift             ← Token types and parsed command enum
│   ├── CommandParser.swift     ← Hand-written tokenizer
│   └── CommandExecutor.swift   ← Executes commands against SwiftData
├── Views/
│   ├── ContentView.swift       ← Root navigation
│   ├── DashboardView.swift     ← Main dashboard (contacts by orbit)
│   ├── ContactListView.swift   ← Searchable contact list
│   ├── ContactDetailView.swift ← Contact profile (artifacts + interactions)
│   ├── ContactFormSheet.swift  ← Add/edit contact form
│   ├── CommandPaletteView.swift← Command palette with syntax highlighting
│   ├── ArtifactEditSheet.swift ← Add/edit artifacts via GUI
│   ├── ConstellationListView.swift ← Group management
│   └── TagListView.swift       ← Tag management
├── DesignSystem/
│   └── OrbitDesign.swift       ← Typography, colors, spacing system
├── Platform/
│   └── MenuCommands.swift      ← macOS menu bar commands
└── Helpers/
    └── Extensions.swift        ← Utilities and export helpers
```

4. Make sure "Copy items if needed" is checked and "Create groups" is selected

### 3. Configure iCloud (Required for Sync)

1. Select the project in the navigator → select the **Orbit** target
2. Go to **Signing & Capabilities**
3. Click **+ Capability** and add:
   - **iCloud** → Check **CloudKit** → Create or select a container (e.g., `iCloud.com.yourname.orbit`)
   - **Background Modes** → Check **Remote notifications**
4. **Important**: Before your first App Store release, go to the [CloudKit Dashboard](https://icloud.developer.apple.com/) and deploy the schema to the Production environment

### 4. Set Deployment Targets

1. In the project settings, set:
   - iOS Deployment Target: **17.0** (minimum for SwiftData)
   - macOS Deployment Target: **14.0**

### 5. Build and Run

1. Select an iOS simulator or your device
2. Press ⌘R to build and run
3. For macOS, switch the scheme to "My Mac" and run again

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    OrbitApp (Entry)                      │
│  • Configures ModelContainer with CloudKit               │
│  • Injects CommandExecutor into environment              │
├─────────────────────────────────────────────────────────┤
│                     ContentView                         │
│  • NavigationSplitView (adapts iOS ↔ macOS)             │
│  • Sidebar: Dashboard / Contacts / Constellations / Tags │
│  • Command Palette overlay (⌘K)                         │
├─────────────────────────────────────────────────────────┤
│                    Data Flow                            │
│                                                         │
│  User Input → CommandParser.tokenize() → [Token]        │
│                    ↓ (on submit)                        │
│            CommandParser.parse() → ParsedCommand         │
│                    ↓                                    │
│            CommandExecutor.execute() → CommandResult     │
│                    ↓                                    │
│            SwiftData ModelContext → iCloud Sync          │
├─────────────────────────────────────────────────────────┤
│                  SwiftData Models                       │
│                                                         │
│  Contact ──┬── Interaction (1:many, cascade delete)     │
│            ├── Artifact (1:many, cascade delete)        │
│            ├── Tag (many:many)                          │
│            └── Constellation (many:many)                │
└─────────────────────────────────────────────────────────┘
```

### Key Patterns

- **@Observable stores** (not MVVM ViewModels): `CommandExecutor` is injected via `.environment()` and accessed with `@Environment(CommandExecutor.self)`
- **@Query** for data fetching: SwiftUI views use `@Query` to reactively fetch from SwiftData
- **Feature-based organization**: Files are grouped by feature (Contacts, Parser, etc.) not by layer
- **VersionedSchema from day one**: The migration plan is set up even before there's a V2

### CloudKit Compatibility Rules (Already Applied)

1. ✅ All properties have default values or are optional
2. ✅ No `.unique` attributes (use manual duplicate checking)
3. ✅ No `.deny` delete rules
4. ✅ Explicit `@Relationship(inverse:)` on all relationships
5. ✅ No enum-typed properties in `#Predicate` filters (stored as `String`/`Int`)

---

## Command Palette Syntax Reference

| Command | Example | Result |
|---------|---------|--------|
| Log interaction | `@Sarah !Coffee` | Creates timestamped interaction |
| Detailed log | `@Sarah !Meeting #Work "Discussed merger"` | Log with tag and note |
| Retroactive log | `@Sarah !Call ^yesterday` | Log backdated to yesterday |
| Time modifiers | `^2d`, `^3h`, `^1w`, `^2m` | Days, hours, weeks, months ago |
| Set artifact | `@Tom > wife: Elena` | Sets singleton value |
| Append to list | `@Tom > likes + Jazz` | Adds to array |
| Remove from list | `@Tom > likes - Jazz` | Removes from array |
| Delete artifact | `@Tom > fax: void` | Deletes the key entirely |
| Archive | `@Sarah !archive` | Moves to Deep Space |
| Restore | `@Sarah !restore` | Restores from archive |
| Undo | `!undo` | Removes last interaction |
| Search | `@Tom gift` | Fuzzy search Tom's artifacts |

---

## Phase 2 Foundations (Already Laid)

### In the Schema
- `gravityScore`, `cachedMomentum`, `cachedCadenceDays` fields on Contact
- `lastContactDate` denormalized for fast sorting
- `isDateType` / `isLocationType` computed properties on Artifact
- Soft delete on Interaction (`isDeleted` flag)
- Export infrastructure (`OrbitExporter`)

### To Build Next
- [ ] iCloud sync testing on real devices
- [ ] macOS menu bar integration (enable `OrbitCommands`)
- [ ] Data export via Share Sheet (JSON + CSV)
- [ ] Performance profiling with Instruments
- [ ] Spotlight integration (CoreSpotlight)

### Phase 3: Orbital Mechanics
- [ ] Gravity from artifact count + interaction depth
- [ ] Cadence from interaction frequency rolling average
- [ ] Momentum = Gravity × (1 / Cadence)
- [ ] Drift detection: actual orbit vs target orbit
- [ ] Canvas-based orbital visualization
- [ ] Passive drift indicators (no push notifications)

---

## Design Principles

1. **Typography is the interface.** Font weight = orbit. Opacity = recency.
2. **No gamification.** No streaks, scores, or badges.
3. **Data ownership.** Local-first. JSON/CSV export from day one.
4. **Minimal required fields.** Only name is required.
5. **Pull, not push.** Surface info; don't guilt-trip.

---

## Troubleshooting

**CloudKit sync not working in simulator** — Use a real device signed into iCloud.

**"Failed to initialize ModelContainer"** — Schema mismatch. Delete the app and rebuild. In production, use the migration plan.

**Build errors on macOS target** — Check `#if os(iOS)` / `#if os(macOS)` guards in `OrbitDesign.swift`.

**Keyboard toolbar not showing on macOS** — `.toolbar { ToolbarItemGroup(placement: .keyboard) }` is iOS-only. macOS shows operator buttons inline.
# Orbit: Personal Relationship Manager

A native macOS and iOS application emphasizing intentional relationship tracking and privacy.

## Architecture (3,585 lines across 16 files)

```text
┌─────────────────────────────────────────────────┐
│  OrbitApp.swift           App entry point      │
│  ContentView.swift        Navigation layout  │
├─────────────────────────────────────────────────┤
│  Parser Subsystem                               │
│    CommandParser.swift    Syntax tokenizer    │
│    CommandExecutor.swift  Data mutation       │
│    Token.swift            Syntax definitions │
├─────────────────────────────────────────────────┤
│  Core Views                                     │
│    DashboardView.swift    Drift tracking     │
│    CommandPaletteView.swift Hybrid UI input  │
│    ReviewDashboardView.swift Reflective pull │
│    TabularView.swift      Batch editing      │
│    SettingsView.swift     Data management    │
├─────────────────────────────────────────────────┤
│  Helpers & Systems                              │
│    SpotlightIndexer.swift System search      │
│    DataValidator.swift    Data integrity     │
│  DesignSystem/                                  │
│    OrbitDesign.swift      Typographic grid    │
└─────────────────────────────────────────────────┘

```

## Interaction Flow

```text
USER INPUT  ──Cmd+K──▶  COMMAND PALETTE
                            │  ▲
                   Syntax Tokenization
                            ▼  │
                 Autocomplete Suggestions
                            │
                         EXECUTE
                            │
                  Command Executor
                            │
      ┌─────────────────────┴─────────────────────┐
      ▼                                           ▼
SWIFTDATA MUTATION             SPOTLIGHT RE-INDEX

```

## Command Reference

### Core Operators

| Operator | Purpose | Example |
| --- | --- | --- |
| `@` | Entity selection | `@Sarah` |
| `!` | Action logging | `!Coffee` |
| `#` | Tag assignment | `#Work` |
| `>` | Artifact assignment | `> city: London` |
| `^` | Time modification | `^yesterday` |
| `""` | Free text note | `"Great conversation"` |

### Artifact Syntax

| Syntax | Action | Example |
| --- | --- | --- |
| `> key: value` | Set singleton value | `@Tom > wife: Elena` |
| `> key + value` | Append to list | `@Tom > likes + Jazz` |
| `> key - value` | Remove from list | `@Tom > likes - Jazz` |
| `> key: void` | Delete key entirely | `@Tom > likes: void` |

### System Commands

| Command | Action |
| --- | --- |
| `!archive` | Archive a contact |
| `!restore` | Restore a contact |
| `!undo` | Soft delete last interaction |

## Key Design Decisions

**Typography as Interface.** Visual hierarchy replaces decorative chrome. Font weight directly encodes relationship strength. Visual opacity encodes contact recency. Fading text signals decaying relationships.

**Intentional Friction.** Automated synchronization is absent. The application demands manual accounting over automation. Required manual logging fosters active recall of individual interactions.

**Local Sovereignty.** Data resides entirely on the device. CloudKit enables private synchronization between native applications. The architecture prohibits third-party server transmission.

**Reflective Architecture.** The review system operates strictly as a pull mechanism. Push notifications are intentionally omitted. Users access neglected contact data on their own terms.