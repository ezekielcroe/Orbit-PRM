//
//  TodayView.swift
//  Orbit
//
//  Created by Yeo Zhi Zheng on 12/7/26.
//


//
//  TodayView.swift
//  Orbit
//
//  The home surface. Answers one question — who needs me — before
//  anything else in the app. Same editorial grammar as the detail
//  pages: masthead, status sentence, hairline-ruled sections, flush
//  rows, color only where drift is.
//
//  Sections:
//    NEEDS ATTENTION — drifting contacts, ranked by driftPriority.
//    LOSING MOMENTUM — on time but fading (momentum below the healthy
//                      band), ranked coldest first.
//    LATEST          — the most recent interactions, for review.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SpotlightIndexer.self) private var spotlightIndexer

    @Binding var selectedContact: Contact?

    @Query(filter: #Predicate<Contact> { !$0.isArchived }, sort: \Contact.name)
    private var contacts: [Contact]

    @Query(
        filter: #Predicate<Interaction> { !$0.isDeleted },
        sort: \Interaction.date,
        order: .reverse
    )
    private var allInteractions: [Interaction]

    private let dateGutterWidth: CGFloat = 52

    // MARK: - Computed Data

    /// Drifting contacts, most urgent first. driftPriority weights how far
    /// past cadence by how close the orbit — this is its first consumer.
    private var needsAttention: [Contact] {
        contacts.filter(\.isDrifting).sorted { $0.driftPriority > $1.driftPriority }
    }

    /// On time but fading, coldest first.
    private var losingMomentum: [Contact] {
        contacts.filter(\.isSlipping).sorted { $0.cachedMomentum < $1.cachedMomentum }
    }

    private var latest: [InteractionGroup] {
        InteractionGroup.group(Array(allInteractions.prefix(24))).prefix(5).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.top, OrbitSpacing.lg)
                    .padding(.bottom, OrbitSpacing.xl)

                if !needsAttention.isEmpty {
                    attentionSection
                }
                if !losingMomentum.isEmpty {
                    momentumSection
                }
                if !latest.isEmpty {
                    latestSection
                }
            }
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.bottom, OrbitSpacing.xxxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle("Today")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            MomentumEngine.recomputeAll(in: modelContext)
        }
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.system(size: 28, weight: .semibold, design: .default))

            Text(statusSentence)
                .font(OrbitTypography.body)
                .foregroundStyle(needsAttention.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
        }
    }

    private var statusSentence: String {
        guard !contacts.isEmpty else {
            return "No contacts yet — open the command palette to add one."
        }
        var clauses: [String] = []
        if !needsAttention.isEmpty {
            clauses.append("\(needsAttention.count) of \(contacts.count) contacts need attention")
        } else {
            clauses.append("Everyone is on cadence")
        }
        if !losingMomentum.isEmpty {
            clauses.append("\(losingMomentum.count) losing momentum")
        }
        return clauses.joined(separator: " — ") + "."
    }

    // MARK: - Needs Attention

    private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "NEEDS ATTENTION") {
                Text("\(needsAttention.count)")
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.quaternary)
            }

            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                ForEach(needsAttention) { contact in
                    attentionRow(contact)
                }
            }
            .padding(.top, OrbitSpacing.md)
            .padding(.bottom, OrbitSpacing.xl)
        }
    }

    private func attentionRow(_ contact: Contact) -> some View {
        contactRow(contact) {
            Text(attentionLine(for: contact))
                .font(OrbitTypography.caption)
                .foregroundStyle(contact.driftColor)
        }
    }

    private func attentionLine(for contact: Contact) -> String {
        guard let days = contact.daysSinceLastContact else {
            return "Never contacted — \(contact.orbitZoneName.lowercased()) expects \(cadenceWord(for: contact)) contact."
        }
        let over = days - contact.cadenceThreshold
        return "\(over) day\(over == 1 ? "" : "s") past the \(cadenceWord(for: contact)) cadence for \(contact.orbitZoneName.lowercased())."
    }

    private func cadenceWord(for contact: Contact) -> String {
        switch contact.cadenceThreshold {
        case 7: return "weekly"
        case 30: return "monthly"
        case 90: return "quarterly"
        case 365: return "yearly"
        default: return "expected"
        }
    }

    // MARK: - Losing Momentum

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "LOSING MOMENTUM") {
                Text("\(losingMomentum.count)")
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(.quaternary)
            }

            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                ForEach(losingMomentum) { contact in
                    momentumRow(contact)
                }
            }
            .padding(.top, OrbitSpacing.md)
            .padding(.bottom, OrbitSpacing.xl)
        }
    }

    private func momentumRow(_ contact: Contact) -> some View {
        contactRow(contact) {
            Text(momentumLine(for: contact))
                .font(OrbitTypography.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func momentumLine(for contact: Contact) -> String {
        var line = String(format: "momentum %.1f", contact.cachedMomentum)
        if contact.cachedCadenceDays > 0 {
            let usual = Int(contact.cachedCadenceDays.rounded())
            line += " · usually every \(usual) day\(usual == 1 ? "" : "s")"
            if let days = contact.daysSinceLastContact, days > usual {
                line += ", now \(days)"
            }
        }
        return line
    }

    // MARK: - Shared Contact Row
    // Name weight encodes momentum (Phase 3), opacity encodes recency.
    // Tap opens the contact; long-press logs without leaving the page.

    private func contactRow<Detail: View>(_ contact: Contact, @ViewBuilder detail: () -> Detail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(momentum: contact.cachedMomentum))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))
                detail()
            }

            Spacer(minLength: OrbitSpacing.md)

            Text(contact.recencyDescription)
                .font(OrbitTypography.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedContact = contact }
        .contextMenu {
            Section("Quick Log") {
                Button("Call", systemImage: "phone") { quickLog(contact: contact, impulse: "Call") }
                Button("Text", systemImage: "message") { quickLog(contact: contact, impulse: "Text") }
                Button("Coffee", systemImage: "cup.and.saucer") { quickLog(contact: contact, impulse: "Coffee") }
            }
            Button("Open", systemImage: "arrow.right") { selectedContact = contact }
        }
    }

    private func quickLog(contact: Contact, impulse: String) {
        let interaction = Interaction(impulse: impulse, date: Date())
        interaction.contact = contact
        modelContext.insert(interaction)
        contact.refreshCachedFields()
        spotlightIndexer.index(contact: contact)
        try? modelContext.save()
    }

    // MARK: - Latest

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionRule(label: "LATEST") {
                EmptyView()
            }

            VStack(alignment: .leading, spacing: OrbitSpacing.md) {
                ForEach(latest) { group in
                    latestRow(group)
                }
            }
            .padding(.top, OrbitSpacing.md)
        }
    }

    private func latestRow(_ group: InteractionGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrbitSpacing.md) {
            Text(group.date.formatted(.dateTime.day().month(.abbreviated)))
                .font(OrbitTypography.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: dateGutterWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(latestHeadline(for: group))
                    .font(OrbitTypography.body)
                if !group.content.isEmpty {
                    Text(group.content)
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let contact = group.contacts.first {
                selectedContact = contact
            }
        }
    }

    private func latestHeadline(for group: InteractionGroup) -> String {
        let names: String
        if group.isGroup {
            names = group.mutualConstellationName.map { "✦ \($0)" } ?? "\(group.contacts.count) contacts"
        } else {
            names = group.contacts.first?.name ?? "—"
        }
        return "\(group.impulse) with \(names)"
    }

    // MARK: - Section Rule

    private func sectionRule<Trailing: View>(label: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
            Divider()
            HStack {
                Text(label)
                    .font(OrbitTypography.captionMedium)
                    .tracking(2)
                    .foregroundStyle(.secondary)
                Spacer()
                trailing()
            }
        }
    }
}
