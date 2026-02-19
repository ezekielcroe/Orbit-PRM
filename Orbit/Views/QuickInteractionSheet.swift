import SwiftUI
import SwiftData

// MARK: - QuickInteractionSheet (Phase 2)
// Update: Re-indexes contact in Spotlight after logging an interaction.

struct QuickInteractionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    let contact: Contact

    @State private var impulse = ""
    @State private var content = ""
    @State private var date = Date()

    private let commonImpulses = ["Call", "Coffee", "Dinner", "Text", "Meeting", "Lunch", "Walk", "Video Call", "Email"]

    var body: some View {
        NavigationStack {
            Form {
                Section("What happened?") {
                    TextField("Action (e.g., Coffee, Call)", text: $impulse)

                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(commonImpulses, id: \.self) { imp in
                            Button(imp) {
                                impulse = imp
                            }
                            .buttonStyle(.bordered)
                            .tint(impulse == imp ? .orange : .secondary)
                            .controlSize(.small)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("What did you talk about?", text: $content, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                }
            }
            .navigationTitle("Log Interaction")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveInteraction()
                        dismiss()
                    }
                    .disabled(impulse.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveInteraction() {
        let interaction = Interaction(
            impulse: impulse.trimmingCharacters(in: .whitespaces),
            content: content.trimmingCharacters(in: .whitespaces),
            date: date
        )
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshLastContactDate()
        spotlightIndexer.index(contact: contact)
    }
}
