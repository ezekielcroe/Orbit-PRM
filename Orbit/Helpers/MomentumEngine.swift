//
//  MomentumEngine.swift
//  Orbit
//
//  Created by Yeo Zhi Zheng on 12/7/26.
//


//
//  Momentum.swift
//  Orbit
//
//  Phase 3: momentum computation.
//
//  Momentum is exponentially decayed interaction history. Each active
//  interaction contributes 0.5^(age / halfLife), where the half-life is
//  the contact's cadence threshold — so a Call logged one full cadence
//  period ago is worth half a Call logged today, regardless of whether
//  that period is a week (Inner Circle) or a year (Outer Orbit).
//
//  Calibration: a contact touched exactly once per cadence period sits
//  between 1.0 (a full period since last contact, next touch due) and
//  2.0 (touched today, full history behind it). This gives stable bands:
//
//      >= 1.0   on rhythm — history is carrying the relationship
//      0.5–1.0  slipping — roughly one missed cycle
//      <  0.5   cold — the history has decayed away
//
//  cachedCadenceDays is the observed rhythm: the mean gap in days between
//  the last several interactions. targetOrbit states the intended rhythm;
//  cachedCadenceDays reports the actual one.
//
//  gravityScore is untouched: it remains a reserved, user-tunable field
//  and is not derived from momentum.

import Foundation
import SwiftUI
import SwiftData

// MARK: - Contact Momentum

extension Contact {

    /// Half-life for momentum decay, in days. Uses the cadence threshold
    /// for the contact's orbit zone; Deep Space (no threshold) decays on
    /// a yearly half-life rather than not at all.
    var momentumHalfLife: Double {
        let threshold = cadenceThreshold
        guard threshold != Int.max else { return 365 }
        return Double(threshold)
    }

    /// Recompute cachedMomentum and cachedCadenceDays from the given
    /// active (non-deleted) interactions. Called by refreshCachedFields()
    /// on every write, and by MomentumEngine on launch/foreground so the
    /// values decay with the passage of time.
    func recomputeMomentum(using active: [Interaction]) {
        let now = Date()
        let halfLife = momentumHalfLife

        // Contributions below 0.5^4 = 6.25% are noise; skip interactions
        // older than four half-lives.
        let horizon = halfLife * 4

        var momentum = 0.0
        for interaction in active {
            let age = now.timeIntervalSince(interaction.date) / 86_400
            guard age >= 0, age <= horizon else { continue }
            momentum += pow(0.5, age / halfLife)
        }
        cachedMomentum = momentum

        // Observed cadence: mean gap across the last ten interactions.
        let recent = active
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map(\.date)
        if recent.count >= 2 {
            var gaps: [Double] = []
            for i in 0..<(recent.count - 1) {
                gaps.append(recent[i].timeIntervalSince(recent[i + 1]) / 86_400)
            }
            cachedCadenceDays = gaps.reduce(0, +) / Double(gaps.count)
        } else {
            cachedCadenceDays = 0
        }
    }

    /// Convenience overload that gathers active interactions itself.
    func recomputeMomentum() {
        recomputeMomentum(using: (interactions ?? []).filter { !$0.isDeleted })
    }

    /// A relationship that is inside its cadence deadline but whose
    /// momentum has decayed below the healthy band — weakening trend,
    /// not yet a missed deadline. Drift and slipping are disjoint:
    /// drift is "past due", slipping is "fading while still on time".
    var isSlipping: Bool {
        guard targetOrbit < 4 else { return false }
        guard !isDrifting else { return false }
        guard cachedInteractionCount >= 2 else { return false }
        return cachedMomentum < 1.0
    }
}

// MARK: - Momentum Engine

enum MomentumEngine {

    /// Recompute momentum for every contact. Cheap at personal-CRM scale;
    /// run at launch and on return to foreground, since decay happens
    /// with time and not just with writes.
    static func recomputeAll(in context: ModelContext) {
        let descriptor = FetchDescriptor<Contact>()
        guard let contacts = try? context.fetch(descriptor) else { return }
        for contact in contacts {
            contact.recomputeMomentum()
            if contact.searchText.isEmpty { contact.refreshSearchText() }
        }
        try? context.save()
    }
}

// MARK: - Momentum Typography
// Phase 3 of "typography IS the interface": weight encodes maintained
// relationship strength (momentum) rather than intended strength (orbit).
// Adopted by TodayView; other views can migrate call sites from
// contactName(orbit:) as desired.

extension OrbitTypography {

    static func contactName(momentum: Double) -> Font {
        .system(size: 17, weight: weightForMomentum(momentum), design: .default)
    }

    static func contactNameLarge(momentum: Double) -> Font {
        .system(size: 28, weight: weightForMomentum(momentum), design: .default)
    }

    private static func weightForMomentum(_ momentum: Double) -> Font.Weight {
        switch momentum {
        case 1.5...: return .heavy
        case 1.0..<1.5: return .bold
        case 0.6..<1.0: return .medium
        case 0.3..<0.6: return .light
        default: return .ultraLight
        }
    }
}
