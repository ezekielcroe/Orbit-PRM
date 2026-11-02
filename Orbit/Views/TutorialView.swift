//
//  TutorialView.swift
//  Orbit
//
//  A single-page reference for how Orbit works, opened from Settings.
//  First-run onboarding lives in OnboardingView; this page is for looking
//  things up later, including the optional shortcut syntax.
//

import SwiftUI

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
                    topic("Today", icon: "sun.max",
                          "Each day Orbit picks up to five people to reach out to, and says why — for example “You used to talk every 2 weeks — it's been 6.” Log, snooze or change closeness right from the row. The list stays the same all day so you can work through it.")

                    topic("Logging", icon: "text.cursor",
                          "Open the Log tab (⌘K on iPad and Mac) and type what happened in plain words. Orbit shows who, what, when and the note before saving. Anything after “about” is the note. Say “my sister” or “my siblings” once you've set a relationship fact, or just pick the person when asked — Orbit remembers. On devices with Apple Intelligence, Re-read asks the on-device model for a second opinion.")
                    examples([
                        "Coffee with Sarah yesterday, talked about her move",
                        "Called Mum about her surgery #health",
                        "Dinner with the Book Club on Friday",
                        "Sarah's birthday is 3 March",
                        "Tom works at Google",
                    ])

                    topic("Closeness", icon: "circle.dotted",
                          "Closeness sets how often you'd like to be in touch. Only people whose closeness you've chosen, or whom you've logged with, appear on Today.")
                    VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
                        ForEach(OrbitZone.allZones, id: \.id) { zone in
                            HStack {
                                Text(zone.name).font(OrbitTypography.contactName(orbit: zone.id))
                                Spacer()
                                Text(AttentionEngine.cadenceWord(forOrbit: zone.id))
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    topic("Facts and groups", icon: "star",
                          "Facts are details worth remembering — birthday, kids' names, favourite food. Birthdays and anniversaries show up under Coming Up on Today. Groups let you log once for everyone, like a team or a book club.")

                    topic("Undo", icon: "arrow.uturn.backward",
                          "Every change shows a banner with Undo. You can also type !undo in the palette, or press ⌥⌘Z on a Mac.")

                    VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                        Label("Shortcut syntax (optional)", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(OrbitTypography.headline)
                        Text("For people who prefer exact commands. Start a word with one of these:")
                            .font(OrbitTypography.caption)
                            .foregroundStyle(.secondary)
                        syntax("@Sarah", "a person — @\"Sarah Connor\" for full names")
                        syntax("!Coffee", "the action")
                        syntax("#work", "a tag (works in plain words too)")
                        syntax("\"note\"", "a note — or just type it")
                        syntax("^yesterday  ^3d  ^last-monday", "when")
                        syntax("*Family", "a group — *-Family to remove")
                        syntax("> birthday: 3 March", "set a fact · + adds to a list · - removes · : void deletes")
                        syntax("!archive  !restore  !undo", "other commands")
                    }
                }
                .padding(OrbitSpacing.lg)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("How Orbit works")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 560)
        #endif
    }

    private func topic(_ title: String, icon: String, _ body: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Label(title, systemImage: icon).font(OrbitTypography.headline)
            Text(body).font(OrbitTypography.body).foregroundStyle(.secondary)
        }
    }

    private func examples(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xs) {
            ForEach(lines, id: \.self) { Text($0).font(OrbitTypography.bodyMedium) }
        }
        .padding(OrbitSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func syntax(_ code: String, _ meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(code).font(.system(size: 14, design: .monospaced))
            Text(meaning).font(OrbitTypography.footnote).foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TutorialView()
}
