# Orbit — Personal Relationship Manager

Orbit is a lightweight, keyboard-centric Personal CRM for iOS and macOS. Built natively with SwiftUI and SwiftData, it helps you stay in touch with the people who matter most without the bloat, subscriptions, or privacy concerns of enterprise CRM tools.

Orbit is designed around "Orbit Zones" to manage your interaction cadence and features a powerful custom Command Palette to log interactions at the speed of thought.

---

## Table of Contents

1. [The Concept](#the-concept)
2. [Core Features](#core-features)
3. [Command Palette Syntax](#command-palette-syntax)
4. [Privacy & Data Ownership](#privacy--data-ownership)
5. [Design System](#design-system)
6. [Under the Hood](#under-the-hood)
7. [Installation & Requirements](#installation--requirements)
8. [License](#license)

---

## The Concept

Orbit models your relationships as a solar system. The people closest to you live in your **Inner Circle**; acquaintances float in **Deep Space**. Every logged interaction pulls a contact closer; silence lets them drift. The app watches for drift and surfaces the relationships that need your attention so you never lose touch.

| Zone | Orbit | Expected Cadence |
|------|-------|-------------------|
| **Inner Circle** | 0 | Weekly (7 days) |
| **Near Orbit** | 1 | Monthly (30 days) |
| **Mid Orbit** | 2 | Quarterly (90 days) |
| **Outer Orbit** | 3 | Yearly (365 days) |
| **Deep Space** | 4 | No threshold |

---

## Core Features

* **⚡️ Command Palette (`⌘K`):** A single-line input that uses a custom tokenizer to parse structured commands. Type `@Sarah !Coffee #catch-up "talked about the trip" ^yesterday` and a full interaction is logged in one keystroke. Features real-time syntax highlighting and autocomplete.
* **🚨 Drift Detection:** When time-since-last-contact exceeds a contact's expected orbit threshold, they are flagged as **drifting**. Severity coloring (yellow → orange → red) and priority sorting show you exactly who to reach out to first.
* **✨ Constellations:** Group contacts into named collections (e.g., `*Family`, `*Work Team`). Log an interaction for an entire constellation at once via the command palette (`*Family !Dinner`).
* **🧩 Custom Artifacts:** Add flexible, custom data to contacts without rigid forms. Supports singleton values (`> birthday: March 12`) and array values (`> likes + Jazz`). Category auto-detection intelligently groups artifacts.
* **🔍 System Integration:** Contacts are indexed via CoreSpotlight, making them searchable system-wide. Easily import names and metadata from your Apple Contacts with built-in deduplication.
* **🗄 Bulk Management:** Multi-select contacts to change orbit zones, archive, restore, or manage constellation memberships in bulk.

---

## Command Palette Syntax

Orbit features a custom, zero-dependency token parser that maps operator characters to typed tokens.

| Operator | Token Type | Example |
|----------|-----------|---------|
| `@` | Entity (Contact) | `@Sarah`, `@"Sarah Connor"` |
| `!` | Impulse (Action) | `!Coffee`, `!Call` |
| `#` | Tag | `#work`, `#catch-up` |
| `>` | Artifact | `> birthday: March 12`, `> likes + Jazz` |
| `^` | Time modifier | `^yesterday`, `^2d`, `^1w`, `^3m` |
| `*` | Constellation | `*Family`, `*-Family` (remove) |
| `"..."` | Quoted note | `"Discussed the new project"` |

### Command Examples

```text
@Sarah !Coffee #catch-up "fun chat" ^yesterday     → Log interaction
@Sarah > birthday: March 12                        → Set artifact
@Sarah > likes + Jazz                              → Append to list artifact
@Sarah > likes - Jazz                              → Remove from list artifact
@Sarah > city: void                                → Delete artifact
@Sarah *Family                                     → Add to constellation
@Sarah *-Family                                    → Remove from constellation
*Family !Dinner #holiday                           → Log for entire group
@Sarah                                             → Navigate to contact
!undo                                              → Undo last interaction

```

---

## Privacy & Data Ownership

Orbit is built on the philosophy that your relationships are your private business.

* **Local-First & Zero Tracking:** No analytics, no crash reporters, no telemetry.
* **iCloud Sync:** Data syncs seamlessly across your Apple devices using your own private iCloud account (via SwiftData/CloudKit). *I never see your data.*
* **Automatic Recovery:** Features an automatic fallback to a local-only store if iCloud initialization fails.
* **No Vendor Lock-in:** Export your complete database at any time as a comprehensive JSON file (preserving all relationships) or a flat CSV summary.

---

## Design System

Orbit uses a **Swiss/International Typographic Style** design system. The core principle is that typography *is* the interface—there are no decorative borders, cards, or shadows.

* **Weight encodes relationship strength:** Inner Circle contacts render in `.heavy`; Deep Space contacts render in `.ultraLight`. This creates immediate visual hierarchy.
* **Opacity encodes recency:** A contact seen today is fully opaque (1.0); someone unseen for over a year fades to 0.25.
* **Adaptive Layouts:** A three-column `NavigationSplitView` on macOS/iPadOS, and a `TabView` on iOS. Supports System, Light, and Dark modes with selectable accent tints.

---

## Under the Hood

### Architecture

Orbit follows a single-container SwiftData pattern. `OrbitApp` creates the `ModelContainer` once and passes it through the environment. A `CommandExecutor` acts as the single point of mutation for command-palette-driven writes.

```text
┌─────────────────────────────────────────────────────────┐
│                     OrbitApp                            │
│  ModelContainer · CommandExecutor · SpotlightIndexer    │
│  DataValidator · AppStorage (theme/tint)                │
└───────────────────────┬─────────────────────────────────┘
                        │
          ┌─────────────┼─────────────┐
          ▼             ▼             ▼
    ┌──────────┐  ┌──────────┐  ┌──────────┐
    │  Views   │  │  Parser  │  │ Helpers  │
    │          │  │          │  │          │
    │ Content  │  │ Command  │  │ Data     │
    │ People   │  │ Parser   │  │ Validator│
    │ Contact  │  │ Command  │  │ Exts.    │
    │ Detail   │  │ Executor │  │ Spotlight│
    │ Palette  │  │ Token    │  │ Indexer  │
    │ Settings │  │          │  │ Exporter │
    └──────────┘  └──────────┘  └──────────┘

```

### Data Model

Five SwiftData `@Model` entities under a single versioned schema (`OrbitSchemaV1`):

| Entity | Purpose | Key Relationships |
| --- | --- | --- |
| **Contact** | A person in your network | Has many `Interaction`, `Artifact`; Many-to-many `Constellation` |
| **Interaction** | A logged event (coffee, call, etc.) | Belongs to `Contact` |
| **Artifact** | Structured metadata | Belongs to `Contact` |
| **Tag** | Name registry for autocomplete | Standalone (assigned via `Interaction.tagNames` strings) |
| **Constellation** | Named group of contacts | Many-to-many with `Contact` |

---

## Installation & Requirements

* **Platform:** iOS 17.0+ and macOS 14.0+
* **Availability:** Orbit is available as a one-time purchase on the [Apple App Store](https://www.google.com/search?q=%23). There are no subscriptions and no ads.

---

## License

**Copyright (c) 2026 Zhi Zheng Yeo. All Rights Reserved.**

*Note: This repository serves as the public issue tracker and documentation hub for Orbit. The source code is proprietary and closed-source. You may not reproduce, distribute, or create derivative works from this software without explicit permission.*