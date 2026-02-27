//
//  ConstellationDetailView.swift
//  Orbit
//
//  Created by Zhi Zheng Yeo on 27/2/26.
//

import SwiftUI
import SwiftData

// MARK: - Constellation Detail View

struct ConstellationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var constellation: Constellation
    
    // Facet State
        enum DetailTab { case members, activity }
        @State private var selectedTab: DetailTab = .members
        
        // Add this new state:
        @State private var showAddInteraction = false

    // MARK: - Computed Data
    
    private var activeMembers: [Contact] {
        constellation.contacts
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var driftingMembers: [Contact] {
        activeMembers.filter { $0.isDrifting }
    }

    private var avgDaysSinceContact: Int? {
        let days = activeMembers.compactMap { $0.daysSinceLastContact }
        guard !days.isEmpty else { return nil }
        return days.reduce(0, +) / days.count
    }

    private var groupInteractions: [Interaction] {
        activeMembers
            .flatMap { $0.activeInteractions }
            .sorted { $0.date > $1.date }
    }

    private var sharedTagStats: [(name: String, count: Int)] {
        var tagCounts: [String: Int] = [:]
        for contact in activeMembers {
            for tag in contact.aggregatedTags {
                tagCounts[tag.name, default: 0] += tag.count
            }
        }
        return tagCounts
            .sorted { $0.value > $1.value }
            .map { (name: $0.key, count: $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                
                // 1. The Sticky Hero Header
                constellationHeader
                    .padding(.bottom, OrbitSpacing.md)

                // 2. The Pinned Facet Toggle
                Section {
                    switch selectedTab {
                    case .members:
                        membersFacet
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    case .activity:
                        activityFacet
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                } header: {
                    facetPicker
                }
            }
            
            .background(OrbitColors.commandBackground.ignoresSafeArea())
                    .navigationTitle(constellation.name)
                    .navigationBarTitleDisplayMode(.inline)
                    // 1. ADD TOOLBAR
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Log Activity", systemImage: "plus.bubble") {
                                showAddInteraction = true
                            }
                        }
                    }
                    // 2. ADD SHEET
                    .sheet(isPresented: $showAddInteraction) {
                        ConstellationInteractionSheet(constellation: constellation)
                    }
        }
        .background(OrbitColors.commandBackground.ignoresSafeArea())
        .navigationTitle(constellation.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero Header

    private var constellationHeader: some View {
        VStack(spacing: OrbitSpacing.md) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "star.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.purple)
            }
            .padding(.top, OrbitSpacing.md)

            // Title & Notes
            VStack(spacing: OrbitSpacing.xs) {
                Text(constellation.name)
                    .font(.system(size: 28, weight: .semibold, design: .default))
                    .multilineTextAlignment(.center)

                if !constellation.notes.isEmpty {
                    Text(constellation.notes)
                        .font(OrbitTypography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OrbitSpacing.lg)
                }
            }

            // Group Stats
            HStack(spacing: OrbitSpacing.lg) {
                statBadge("\(activeMembers.count)", label: "Members", icon: "person.2")

                if let avg = avgDaysSinceContact {
                    statBadge("\(avg)d", label: "Avg gap", icon: "clock")
                }

                if !driftingMembers.isEmpty {
                    statBadge("\(driftingMembers.count)", label: "Drifting", icon: "exclamationmark.circle", color: .orange)
                }
                
                statBadge("\(groupInteractions.count)", label: "Total logs", icon: "text.bubble")
            }
            .padding(.top, OrbitSpacing.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private func statBadge(_ value: String, label: String, icon: String, color: Color = .secondary) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                Text(value)
                    .font(OrbitTypography.captionMedium)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(OrbitTypography.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Facet Picker

    private var facetPicker: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab.animation(.easeInOut(duration: 0.2))) {
                Text("Members").tag(DetailTab.members)
                Text("Activity").tag(DetailTab.activity)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, OrbitSpacing.lg)
            .padding(.vertical, OrbitSpacing.sm)
            
            Divider()
        }
        .background(.regularMaterial)
    }

    // MARK: - Members Facet

    private var membersFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
            
            // Current Members
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                Text("CURRENT MEMBERS")
                    .font(OrbitTypography.captionMedium)
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, OrbitSpacing.lg)

                if activeMembers.isEmpty {
                    Text("No active members.")
                        .font(OrbitTypography.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, OrbitSpacing.lg)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(activeMembers) { contact in
                            memberRow(contact)
                        }
                    }
                }
            }
            .padding(.top, OrbitSpacing.md)
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }

    private func memberRow(_ contact: Contact) -> some View {
        HStack(spacing: OrbitSpacing.md) {
            if contact.isDrifting {
                Circle()
                    .fill(contact.driftColor)
                    .frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6) // Alignment spacer
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(OrbitTypography.contactName(orbit: contact.targetOrbit))
                    .opacity(OrbitTypography.opacityForRecency(daysSinceContact: contact.daysSinceLastContact))

                Text(contact.recencyDescription)
                    .font(OrbitTypography.footnote)
                    .foregroundStyle(contact.isDrifting ? contact.driftColor : .secondary)
            }

            Spacer()

            Button {
                withAnimation {
                    constellation.contacts.removeAll { $0.id == contact.id }
                    try? modelContext.save()
                }
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, OrbitSpacing.sm)
        .padding(.horizontal, OrbitSpacing.lg)
        .background(Color.secondary.opacity(0.02))
        .padding(.vertical, 1)
    }

    // MARK: - Activity Facet

    private var activityFacet: some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.xl) {
            
            // Shared Group Tags
            if !sharedTagStats.isEmpty {
                VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                    Text("SHARED TAGS")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)

                    FlowLayout(spacing: OrbitSpacing.sm) {
                        ForEach(sharedTagStats.prefix(10), id: \.name) { tag in
                            HStack(spacing: 2) {
                                Text("#\(tag.name)")
                                    .font(OrbitTypography.caption)
                                    .foregroundStyle(OrbitColors.syntaxTag)
                                Text("×\(tag.count)")
                                    .font(OrbitTypography.footnote)
                                    .foregroundStyle(OrbitColors.syntaxTag.opacity(0.6))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(OrbitColors.syntaxTag.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, OrbitSpacing.lg)
                .padding(.top, OrbitSpacing.md)
            }

            // Timeline
            VStack(alignment: .leading, spacing: OrbitSpacing.sm) {
                HStack {
                    Text("TIMELINE")
                        .font(OrbitTypography.captionMedium)
                        .tracking(1.5)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    Button {
                        showAddInteraction = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, OrbitSpacing.lg)

                if groupInteractions.isEmpty {
                    // UPDATE THE EMPTY STATE
                    ContentUnavailableView {
                        Label("No Activity", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                    } description: {
                        Text("Log a group interaction to see it appear here and on every member's timeline.")
                    } actions: {
                        Button("Log Interaction") {
                            showAddInteraction = true
                        }
                        .buttonStyle(.borderedProminent)
                        }
                    .padding(.top, OrbitSpacing.md)
                } else {
                    LazyVStack(alignment: .leading, spacing: OrbitSpacing.md) {
                        ForEach(groupInteractions) { interaction in
                            InteractionRowView(interaction: interaction)
                                .padding(OrbitSpacing.sm)
                                .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                                .padding(.horizontal, OrbitSpacing.lg)
                        }
                    }
                }
            }
        }
        .padding(.bottom, OrbitSpacing.xxxl)
    }
}
