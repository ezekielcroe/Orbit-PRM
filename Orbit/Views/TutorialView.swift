//
//  TutorialView.swift
//  Orbit
//
//  A page-by-page walkthrough that teaches the command palette syntax
//  and core app concepts. Presented as a sheet, typically triggered from
//  Settings or on first launch.
//

import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0

    private let pages = TutorialPage.allPages

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        TutorialPageView(page: page)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif
                .animation(.easeInOut(duration: 0.3), value: currentPage)

                // Navigation controls
                tutorialControls
            }
            .navigationTitle("Learn Orbit")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Controls

    private var tutorialControls: some View {
        VStack(spacing: OrbitSpacing.md) {
            // Page indicator dots
            HStack(spacing: OrbitSpacing.sm) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .scaleEffect(index == currentPage ? 1.2 : 1.0)
                        .animation(.spring(response: 0.3), value: currentPage)
                }
            }

            // Buttons
            HStack(spacing: OrbitSpacing.lg) {
                if currentPage > 0 {
                    Button {
                        withAnimation { currentPage -= 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(OrbitTypography.bodyMedium)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentPage < pages.count - 1 {
                    Button {
                        withAnimation { currentPage += 1 }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                        .font(OrbitTypography.bodyMedium)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("Get Started")
                            .font(OrbitTypography.bodyMedium)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.bottom, OrbitSpacing.lg)
        }
    }
}

// MARK: - Tutorial Page Data

struct TutorialPage: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let subtitle: String
    let commandExamples: [CommandExample]
    let tip: String?

    struct CommandExample: Identifiable {
        let id = UUID()
        let command: String
        let explanation: String
        let highlightSegments: [HighlightSegment]
    }

    struct HighlightSegment: Identifiable {
        let id = UUID()
        let text: String
        let color: Color
    }
}

extension TutorialPage {
    static let allPages: [TutorialPage] = [
        // Page 1: Welcome
        TutorialPage(
            icon: "globe.desk",
            title: "Welcome to Orbit",
            subtitle: "Orbit is a personal relationship manager. It helps you stay in touch with the people who matter by tracking your interactions, storing details, and nudging you when someone is drifting out of reach.\n\nEverything revolves around the Command Palette — a fast, text-based way to log interactions and manage your contacts.",
            commandExamples: [],
            tip: "Swipe through to learn the command syntax, or jump straight in and load the sample data from Settings."
        ),

        // Page 2: Contacts & Orbits
        TutorialPage(
            icon: "person.2",
            title: "Contacts & Orbit Zones",
            subtitle: "Every contact lives in an orbit zone that reflects how close the relationship is. Closer orbits expect more frequent contact — if you fall behind, the contact starts \"drifting\" and Orbit will let you know.",
            commandExamples: [
                .init(
                    command: "Inner Circle → weekly",
                    explanation: "Your closest people: partners, family, best friends",
                    highlightSegments: [.init(text: "Inner Circle", color: .primary), .init(text: " → weekly", color: .secondary)]
                ),
                .init(
                    command: "Near Orbit → monthly",
                    explanation: "Close friends you see regularly",
                    highlightSegments: [.init(text: "Near Orbit", color: .primary), .init(text: " → monthly", color: .secondary)]
                ),
                .init(
                    command: "Mid Orbit → quarterly",
                    explanation: "Good friends and active colleagues",
                    highlightSegments: [.init(text: "Mid Orbit", color: .primary), .init(text: " → quarterly", color: .secondary)]
                ),
                .init(
                    command: "Outer Orbit → yearly",
                    explanation: "Acquaintances and distant connections",
                    highlightSegments: [.init(text: "Outer Orbit", color: .primary), .init(text: " → yearly", color: .secondary)]
                ),
                .init(
                    command: "Deep Space → no cadence",
                    explanation: "Dormant contacts — no drift warnings",
                    highlightSegments: [.init(text: "Deep Space", color: .primary), .init(text: " → no cadence", color: .secondary)]
                ),
            ],
            tip: "Font weight reflects orbit: Inner Circle names appear bold, Deep Space names appear light."
        ),

        // Page 3: Logging Interactions
        TutorialPage(
            icon: "text.bubble",
            title: "Log an Interaction",
            subtitle: "Use the Command Palette to quickly log interactions. The @ symbol picks a contact, ! sets the action, # adds tags, quotes add a note, and ^ sets the time.",
            commandExamples: [
                .init(
                    command: "@Alex !Coffee",
                    explanation: "Log a coffee with Alex — simplest form",
                    highlightSegments: [
                        .init(text: "@Alex", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!Coffee", color: OrbitColors.syntaxImpulse)
                    ]
                ),
                .init(
                    command: "@Maya !Run #fitness \"New PR!\"",
                    explanation: "Add a tag and a note",
                    highlightSegments: [
                        .init(text: "@Maya", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!Run", color: OrbitColors.syntaxImpulse),
                        .init(text: " ", color: .clear),
                        .init(text: "#fitness", color: OrbitColors.syntaxTag),
                        .init(text: " ", color: .clear),
                        .init(text: "\"New PR!\"", color: OrbitColors.syntaxQuote)
                    ]
                ),
                .init(
                    command: "@Jordan !Lunch ^yesterday",
                    explanation: "Backdate to yesterday",
                    highlightSegments: [
                        .init(text: "@Jordan", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!Lunch", color: OrbitColors.syntaxImpulse),
                        .init(text: " ", color: .clear),
                        .init(text: "^yesterday", color: OrbitColors.syntaxTime)
                    ]
                ),
                .init(
                    command: "@Sam !Call ^2w",
                    explanation: "Backdate by 2 weeks (also: ^3d, ^1m)",
                    highlightSegments: [
                        .init(text: "@Sam", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!Call", color: OrbitColors.syntaxImpulse),
                        .init(text: " ", color: .clear),
                        .init(text: "^2w", color: OrbitColors.syntaxTime)
                    ]
                ),
            ],
            tip: "For multi-word names, use quotes: @\"Sarah Connor\" !Coffee"
        ),

        // Page 4: Artifacts
        TutorialPage(
            icon: "gift",
            title: "Store Details with Artifacts",
            subtitle: "Artifacts are key-value pairs attached to a contact — birthdays, cities, companies, links, anything. Use > to set, + to append to a list, - to remove, and : void to delete.",
            commandExamples: [
                .init(
                    command: "@Alex >birthday: 3/15",
                    explanation: "Store a birthday",
                    highlightSegments: [
                        .init(text: "@Alex", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: ">birthday: 3/15", color: OrbitColors.syntaxArtifact)
                    ]
                ),
                .init(
                    command: "@Alex >interests + climbing",
                    explanation: "Append to a list artifact",
                    highlightSegments: [
                        .init(text: "@Alex", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: ">interests + climbing", color: OrbitColors.syntaxArtifact)
                    ]
                ),
                .init(
                    command: "@Alex >interests - ramen",
                    explanation: "Remove an item from a list",
                    highlightSegments: [
                        .init(text: "@Alex", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: ">interests - ramen", color: OrbitColors.syntaxArtifact)
                    ]
                ),
                .init(
                    command: "@Alex >birthday: void",
                    explanation: "Delete the artifact entirely",
                    highlightSegments: [
                        .init(text: "@Alex", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: ">birthday: void", color: OrbitColors.syntaxArtifact)
                    ]
                ),
            ],
            tip: "Artifacts with date-like keys (birthday, anniversary) are recognized automatically."
        ),

        // Page 5: Constellations
        TutorialPage(
            icon: "star",
            title: "Group with Constellations",
            subtitle: "Constellations are named groups of contacts. You can add people to a group and log interactions for the entire group at once — perfect for team meetings, friend groups, or book clubs.",
            commandExamples: [
                .init(
                    command: "@Jordan *\"Work Crew\"",
                    explanation: "Add Jordan to the Work Crew constellation",
                    highlightSegments: [
                        .init(text: "@Jordan", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "*\"Work Crew\"", color: OrbitColors.syntaxConstellation)
                    ]
                ),
                .init(
                    command: "@Jordan *-\"Work Crew\"",
                    explanation: "Remove Jordan from the constellation",
                    highlightSegments: [
                        .init(text: "@Jordan", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "*-\"Work Crew\"", color: OrbitColors.syntaxConstellation)
                    ]
                ),
                .init(
                    command: "*\"Work Crew\" !Standup #work",
                    explanation: "Log an interaction for every member at once",
                    highlightSegments: [
                        .init(text: "*\"Work Crew\"", color: OrbitColors.syntaxConstellation),
                        .init(text: " ", color: .clear),
                        .init(text: "!Standup", color: OrbitColors.syntaxImpulse),
                        .init(text: " ", color: .clear),
                        .init(text: "#work", color: OrbitColors.syntaxTag)
                    ]
                ),
            ],
            tip: "Single-word constellations don't need quotes: @Alex *Friends"
        ),

        // Page 6: Archive & Undo
        TutorialPage(
            icon: "archivebox",
            title: "Archive, Restore & Undo",
            subtitle: "Archive contacts you no longer need, restore them later, or quickly undo the last action you took.",
            commandExamples: [
                .init(
                    command: "@Daniil !archive",
                    explanation: "Archive a contact (hides from main list)",
                    highlightSegments: [
                        .init(text: "@Daniil", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!archive", color: OrbitColors.syntaxImpulse)
                    ]
                ),
                .init(
                    command: "@Daniil !restore",
                    explanation: "Bring an archived contact back",
                    highlightSegments: [
                        .init(text: "@Daniil", color: OrbitColors.syntaxEntity),
                        .init(text: " ", color: .clear),
                        .init(text: "!restore", color: OrbitColors.syntaxImpulse)
                    ]
                ),
                .init(
                    command: "!undo",
                    explanation: "Undo the last logged interaction",
                    highlightSegments: [
                        .init(text: "!undo", color: OrbitColors.syntaxImpulse)
                    ]
                ),
            ],
            tip: "Archived contacts keep all their data — nothing is lost."
        ),

        // Page 7: Quick Reference
        TutorialPage(
            icon: "command",
            title: "Quick Reference",
            subtitle: "Here's a cheat sheet of every operator in the command palette.",
            commandExamples: [
                .init(
                    command: "@  Contact",
                    explanation: "Select a contact (or create one)",
                    highlightSegments: [.init(text: "@", color: OrbitColors.syntaxEntity), .init(text: "  Contact", color: .primary)]
                ),
                .init(
                    command: "!  Action",
                    explanation: "The type of interaction (Coffee, Call, etc.)",
                    highlightSegments: [.init(text: "!", color: OrbitColors.syntaxImpulse), .init(text: "  Action", color: .primary)]
                ),
                .init(
                    command: "#  Tag",
                    explanation: "Categorize with tags",
                    highlightSegments: [.init(text: "#", color: OrbitColors.syntaxTag), .init(text: "  Tag", color: .primary)]
                ),
                .init(
                    command: ">  Artifact",
                    explanation: "Store a detail (key: value)",
                    highlightSegments: [.init(text: ">", color: OrbitColors.syntaxArtifact), .init(text: "  Artifact", color: .primary)]
                ),
                .init(
                    command: "^  Time",
                    explanation: "Backdate (^yesterday, ^2d, ^1w, ^3m)",
                    highlightSegments: [.init(text: "^", color: OrbitColors.syntaxTime), .init(text: "  Time", color: .primary)]
                ),
                .init(
                    command: "*  Constellation",
                    explanation: "Group contacts together",
                    highlightSegments: [.init(text: "*", color: OrbitColors.syntaxConstellation), .init(text: "  Constellation", color: .primary)]
                ),
                .init(
                    command: "\"  Note",
                    explanation: "Free-text note in quotes",
                    highlightSegments: [.init(text: "\"", color: OrbitColors.syntaxQuote), .init(text: "  Note", color: .primary)]
                ),
            ],
            tip: nil
        ),
    ]
}

// MARK: - Tutorial Page View

struct TutorialPageView: View {
    let page: TutorialPage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrbitSpacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    Image(systemName: page.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)

                    Text(page.title)
                        .font(.system(size: 24, weight: .bold))

                    Text(page.subtitle)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Command examples
                if !page.commandExamples.isEmpty {
                    VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                        ForEach(page.commandExamples) { example in
                            CommandExampleRow(example: example)
                        }
                    }
                }

                // Tip
                if let tip = page.tip {
                    HStack(alignment: .top, spacing: OrbitSpacing.sm) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(.yellow)
                            .font(.callout)
                        Text(tip)
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(OrbitSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Spacer(minLength: OrbitSpacing.xxl)
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.top, OrbitSpacing.lg)
        }
    }
}

// MARK: - Command Example Row

struct CommandExampleRow: View {
    let example: TutorialPage.CommandExample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Syntax-highlighted command
            HStack(spacing: 0) {
                ForEach(example.highlightSegments) { segment in
                    Text(segment.text)
                        .foregroundStyle(segment.color)
                }
            }
            .font(.system(size: 16, weight: .medium, design: .monospaced))
            .padding(.horizontal, OrbitSpacing.md)
            .padding(.vertical, OrbitSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Explanation
            Text(example.explanation)
                .font(OrbitTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, OrbitSpacing.sm)
        }
    }
}

// MARK: - Preview

#Preview {
    TutorialView()
}
