# Orbit — Personal Relationship Manager

Orbit is a lightweight, keyboard-centric Personal CRM for iOS and macOS. Built natively with SwiftUI and SwiftData, it helps you stay in touch with the people who matter most without the bloat, subscriptions, or privacy concerns of enterprise CRM tools.

Orbit is designed around "Orbit Zones" to manage your interaction cadence and features a powerful custom Command Palette to log interactions at the speed of thought.

---

## Table of Contents

1. [The Concept](#the-concept)
2. [Core Features](#core-features)
3. [Shortcut Syntax](#shortcut-syntax)
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

* **☀️ Today:** Up to five people to reach out to each day, chosen once so the list doesn't reshuffle while you work through it. Each row says why in plain words ("You used to talk every 2 weeks — it's been 6") and has visible Log, Snooze and Closeness actions. Birthdays and anniversaries from your facts show up under *Coming up*.
* **✍️ Log tab — plain words, chat-style:** The second tab is a running history of everything you've logged with the composer docked at the bottom, next to the keyboard (`⌘K` opens the same composer on iPad and Mac). Type `Texted my siblings about Mama going overseas` and Orbit shows who, what, when and the note before saving: anything after *about* is the note, *my siblings* finds your group (or everyone whose relationship is sister/brother), ambiguous names get a picker, unknown names can be created on the spot. Corrections are remembered as nicknames or relationship facts.
* **🧠 Facts in plain words:** `Sarah's birthday is 3 March`, `Tom works at Google`, `Sam likes jazz`, `Jo has a dog called Rex`. Logs that mention a fact ("he's moving to Berlin") offer to save it too.
* **✨ Re-read with Apple Intelligence (iOS 26 / macOS 26):** Optional second opinion from Apple's on-device model, checked against your real contacts and shown in the preview before anything is saved.
* **↩️ Undo everywhere:** Every change shows a banner with Undo — logs, edits, facts, group membership, closeness, archive and snooze.
* **🎯 Closeness:** Each person's orbit zone sets how often you'd like to be in touch. Imported people stay quiet until you set their closeness, so day one isn't a wall of 200 "overdue" contacts.
* **✨ Groups:** Named groups of people (a team, a family, a book club). Log once for everyone.
* **🧩 Facts:** Flexible details on each person — single values or lists. Search in People covers facts, notes, tags and groups ("google", "jazz").
* **🔔 Reminders:** Optional Sunday digest of who could use a hello, plus a heads-up on birthdays. Local notifications only.
* **🔍 System Integration:** CoreSpotlight indexing and import from Apple Contacts.

---

## Shortcut Syntax

Plain language is the default. For people who prefer exact commands, the palette also understands operators at the start of a word:

| Operator | Meaning | Example |
|----------|---------|---------|
| `@` | Person | `@Sarah`, `@"Sarah Connor"` |
| `!` | Action | `!Coffee`, `!Call` |
| `#` | Tag (also works in plain words) | `#work`, `#catch-up` |
| `>` | Fact | `> birthday: 3 March`, `> likes + Jazz` |
| `^` | When | `^yesterday`, `^2d`, `^1w`, `^last-monday`, `^"last monday"` |
| `*` | Group | `*Family`, `*-Family` (remove) |
| `"..."` | Note (unquoted leftover text is kept as the note too) | `"Discussed the new project"` |

Operators only count at the start of a word, so values like `tom@gmail.com`, `Rock & Roll!` or a `t-shirt size` key are kept intact. An unknown `^` time is an error rather than silently "now".

```text
Coffee with Sarah yesterday, talked about her move  → Log (plain language)
@Sarah !Coffee #catch-up "fun chat" ^yesterday      → Log (shortcut syntax)
@Sarah coffee yesterday                             → Mix: person by @, rest in plain words
@Sarah > birthday: 3 March                          → Set fact
@Sarah > likes + Jazz   /   > likes - Jazz          → Add to / remove from a list fact
@Sarah > city: void                                 → Delete fact
@Sarah *Family   /   @Sarah *-Family                → Add to / remove from group
*Family !Dinner #holiday                            → Log for the whole group
Sarah                                               → Open Sarah
!undo                                               → Undo the last change
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

* **Weight encodes closeness, and only closeness:** Inner Circle names render bold, down to regular for Outer Orbit and Deep Space. The floor is `.regular` so every name stays legible.
* **Recency is said in words:** "It's been 6 weeks" rather than fading the name, so the people you most need to see are never the hardest to read. Colour appears only where someone is overdue.
* **Actions are visible:** Primary actions are buttons and swipe actions, not long-press-only menus.
* **Adaptive Layouts:** A three-column `NavigationSplitView` on macOS/iPadOS, and a `TabView` on iOS. Supports System, Light, and Dark modes with selectable accent tints.

---

## Under the Hood

### Architecture

`OrbitApp` creates one `ModelContainer`, one `OrbitStore` and one `AppRouter` and passes them through the environment.

* **`OrbitStore`** (`Orbit/Store`) is the only place that writes data. Every write refreshes the affected contacts' cached fields and Spotlight entries, saves (surfacing errors as a banner), and registers an undo step.
* **`AppRouter`** (`Orbit/Navigation`) holds the selected tab, one selection per tab, and the app-wide sheets (palette, log composer, new contact, onboarding).
* **`Orbit/Core`** is pure Foundation and unit-tested: `DatePhraseParser`, `CaptureParser` / `NaturalLanguageParser`, `FactParser`, `Relationships`, the sigil `CommandParser`, `NameMatcher`, `ActionVocabulary`, `AttentionEngine`, `Birthdays`, and the `CaptureReader` contract for Re-read.
* **`CapturePanel`** is the capture UI, used docked in the Log tab and as the ⌘K sheet. `AppleIntelligenceReader` (compiled only when the SDK has FoundationModels) implements Re-read.
* **`LogComposer`** is the single logging form used from every screen.

```text
input ─► CaptureParser ─► CaptureDraft ─► resolve names (OrbitStore) ─► preview ─► OrbitStore.log
                                                                                  └─► undo step + banner
```

### Data Model

Five SwiftData `@Model` entities. V2 adds fields only (all with defaults), so SwiftData's automatic lightweight migration and the CloudKit schema both accept them:

| Entity | Purpose | V2 additions |
| --- | --- | --- |
| **Contact** | A person | `snoozedUntil`, `closenessConfirmed`, `searchText`, `aliases` |
| **Interaction** | A logged event | — |
| **Artifact** | A fact | `dateValue` (parsed birthdays/anniversaries) |
| **Tag** | Name registry for autocomplete | — |
| **Constellation** | A group | `aliases` |

Model and property names stay as they are (CloudKit can't rename fields); the UI calls them people, logs, facts and groups. A one-time maintenance pass on first launch merges action spellings ("Text" → "Message"), lowercases tags and backfills the new fields.

### Tests

```bash
swift test
```

Runs the `OrbitCoreTests` package target against `Orbit/Core`.

---

## Installation & Requirements

* **Platform:** iOS 17.0+ and macOS 14.0+
* **Availability:** Orbit is available as a one-time purchase on the [Apple App Store](https://www.google.com/search?q=%23). There are no subscriptions and no ads.

---

## License

**Copyright (c) 2026 Zhi Zheng Yeo. All Rights Reserved.**

*Note: This repository serves as the public issue tracker and documentation hub for Orbit. The source code is proprietary and closed-source. You may not reproduce, distribute, or create derivative works from this software without explicit permission.*