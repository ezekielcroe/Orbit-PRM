//
//  Generates realistic sample data so new users can explore every feature
//  before committing their own contacts. Covers: contacts across all orbit
//  zones, interactions with varied impulses/tags/notes, artifacts, constellations,
//  drift states, and an archived contact.
//

import Foundation
import SwiftData

struct SampleDataGenerator {

    // MARK: - Public Entry Point

    /// Insert a complete sample dataset into the given context.
    /// Call this from SettingsView or an onboarding flow.
    @discardableResult
    static func generate(in context: ModelContext) -> SampleDataResult {

        // ── Contacts ───────────────────────────────────────────────
        let alex    = makeContact(name: "Alex Chen",       orbit: 0, notes: "Best friend since college. Always up for late-night ramen.", in: context)
        let maya    = makeContact(name: "Maya Thompson",   orbit: 1, notes: "Running buddy. Training for the Austin half-marathon together.", in: context)
        let jordan  = makeContact(name: "Jordan Rivera",   orbit: 1, notes: "Colleague on the design systems team.", in: context)
        let sam     = makeContact(name: "Sam Okafor",      orbit: 2, notes: "Met at the React conf last year. Great energy.", in: context)
        let priya   = makeContact(name: "Priya Mehta",     orbit: 2, notes: "Neighbor. Shares homemade chai every Diwali.", in: context)
        let luke    = makeContact(name: "Luke Andersen",   orbit: 3, notes: "College roommate. Lives in Copenhagen now.", in: context)
        let rachel  = makeContact(name: "Rachel Kim",      orbit: 4, notes: "Former manager at Pixel Labs. Great reference.", in: context)

        // Archived contact — demonstrates the archive feature
        let daniil  = makeContact(name: "Daniil Petrov",   orbit: 3, notes: "Summer internship contact. No longer at the company.", in: context)
        daniil.isArchived = true

        let allContacts = [alex, maya, jordan, sam, priya, luke, rachel, daniil]

        // ── Interactions ───────────────────────────────────────────
        // Each interaction is backdated to show realistic recency patterns.
        // Alex (Inner Circle) — frequent, recent
        addInteraction(to: alex, impulse: "Coffee",     tags: ["catch-up"],               note: "Talked about his new startup idea",           daysAgo: 1,   in: context)
        addInteraction(to: alex, impulse: "Call",        tags: ["catch-up", "advice"],     note: "Helped me think through the career move",     daysAgo: 5,   in: context)
        addInteraction(to: alex, impulse: "Dinner",      tags: ["social"],                 note: "Tried the new Thai place on 5th",             daysAgo: 14,  in: context)
        addInteraction(to: alex, impulse: "Text",        tags: [],                         note: nil,                                           daysAgo: 20,  in: context)

        // Maya (Near Orbit) — regular cadence
        addInteraction(to: maya, impulse: "Run",         tags: ["fitness"],                note: "10K along the river trail. New PR for her!",  daysAgo: 3,   in: context)
        addInteraction(to: maya, impulse: "Coffee",      tags: ["catch-up"],               note: "Talked about her trip to Kyoto",              daysAgo: 18,  in: context)
        addInteraction(to: maya, impulse: "Text",        tags: ["logistics"],              note: nil,                                           daysAgo: 25,  in: context)

        // Jordan (Near Orbit) — work-focused
        addInteraction(to: jordan, impulse: "Meeting",   tags: ["work", "design"],         note: "Reviewed the new component library",          daysAgo: 2,   in: context)
        addInteraction(to: jordan, impulse: "Lunch",     tags: ["work"],                   note: "Brainstormed the onboarding redesign",        daysAgo: 10,  in: context)
        addInteraction(to: jordan, impulse: "Slack",     tags: ["work", "feedback"],       note: "Sent feedback on their icon proposals",       daysAgo: 15,  in: context)

        // Sam (Mid Orbit) — occasional
        addInteraction(to: sam, impulse: "Coffee",       tags: ["networking", "tech"],      note: "Wants to collab on an open-source project",  daysAgo: 35,  in: context)
        addInteraction(to: sam, impulse: "Conference",   tags: ["tech"],                    note: "Ran into them at the Swift meetup",           daysAgo: 90,  in: context)

        // Priya (Mid Orbit) — seasonal
        addInteraction(to: priya, impulse: "Visit",      tags: ["social", "neighborhood"], note: "Dropped off cookies, chatted about gardens",  daysAgo: 40,  in: context)
        addInteraction(to: priya, impulse: "Text",       tags: ["neighborhood"],           note: nil,                                           daysAgo: 70,  in: context)

        // Luke (Outer Orbit) — drifting (last contact > 365 days for orbit 3)
        addInteraction(to: luke, impulse: "Call",        tags: ["catch-up"],               note: "Video call, met his new dog",                 daysAgo: 400, in: context)

        // Rachel (Deep Space) — very old
        addInteraction(to: rachel, impulse: "Email",     tags: ["career"],                 note: "Asked for a LinkedIn recommendation",         daysAgo: 500, in: context)

        // Daniil (Archived) — one old interaction
        addInteraction(to: daniil, impulse: "Lunch",     tags: ["work"],                   note: "Last day lunch before he left the company",   daysAgo: 600, in: context)

        // ── Artifacts ──────────────────────────────────────────────
        addArtifact(to: alex,   key: "Birthday",   value: "3/15",                       in: context)
        addArtifact(to: alex,   key: "City",       value: "Austin, TX",                 in: context)
        addArtifact(to: alex,   key: "Company",    value: "Stealth Startup",            in: context)

        addArtifact(to: maya,   key: "Birthday",   value: "8/22",                       in: context)
        addArtifact(to: maya,   key: "City",       value: "Austin, TX",                 in: context)

        addArtifact(to: jordan, key: "Company",    value: "Acme Design Co.",            in: context)
        addArtifact(to: jordan, key: "Role",       value: "Senior Design Engineer",     in: context)
        addArtifact(to: jordan, key: "Email",      value: "jordan.r@acmedesign.com",    in: context)

        addArtifact(to: sam,    key: "City",       value: "San Francisco, CA",          in: context)
        addArtifact(to: sam,    key: "GitHub",     value: "github.com/sokafor",         in: context)

        addArtifact(to: priya,  key: "Address",    value: "742 Maple Lane",             in: context)

        addArtifact(to: luke,   key: "City",       value: "Copenhagen, Denmark",        in: context)
        addArtifact(to: luke,   key: "Birthday",   value: "11/2",                       in: context)

        addArtifact(to: rachel, key: "Company",    value: "Pixel Labs (former)",        in: context)
        addArtifact(to: rachel, key: "LinkedIn",   value: "linkedin.com/in/rachelkim",  in: context)

        // Array artifact example — demonstrates the + append feature
        addArrayArtifact(to: alex, key: "Interests", values: ["climbing", "indie games", "ramen"],     in: context)
        addArrayArtifact(to: maya, key: "Interests", values: ["running", "photography", "bouldering"], in: context)

        // ── Tags (Registry) ────────────────────────────────────────
        let tagNames = ["catch-up", "social", "work", "fitness", "tech",
                        "advice", "networking", "design", "feedback",
                        "career", "logistics", "neighborhood"]
        for name in tagNames {
            registerTag(name: name, in: context)
        }

        // ── Constellations ─────────────────────────────────────────
        let workCrew = makeConstellation(name: "Work Crew", notes: "Design team and close colleagues", in: context)
        workCrew.contacts = [jordan, sam]

        let innerCircle = makeConstellation(name: "Austin Friends", notes: "Local crew for weekend hangs", in: context)
        innerCircle.contacts = [alex, maya, priya]

        // ── Refresh all cached fields ──────────────────────────────
        for contact in allContacts {
            contact.refreshCachedFields()
        }

        // ── Save ───────────────────────────────────────────────────
        PersistenceHelper.saveWithLogging(context, operation: "generate sample data")

        return SampleDataResult(
            contactCount: allContacts.count,
            interactionCount: 15,
            artifactCount: 16,
            constellationCount: 2,
            tagCount: tagNames.count
        )
    }

    // MARK: - Result

    struct SampleDataResult {
        let contactCount: Int
        let interactionCount: Int
        let artifactCount: Int
        let constellationCount: Int
        let tagCount: Int

        var summary: String {
            "\(contactCount) contacts, \(interactionCount) interactions, \(artifactCount) artifacts, \(constellationCount) constellations, and \(tagCount) tags."
        }
    }

    // MARK: - Private Helpers

    private static func makeContact(name: String, orbit: Int, notes: String, in context: ModelContext) -> Contact {
        let contact = Contact(name: name, notes: notes, targetOrbit: orbit)
        context.insert(contact)
        return contact
    }

    private static func addInteraction(
        to contact: Contact,
        impulse: String,
        tags: [String],
        note: String?,
        daysAgo: Int,
        in context: ModelContext
    ) {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let interaction = Interaction(impulse: impulse, content: note ?? "", date: date)
        interaction.tagNames = tags.joined(separator: ", ")
        interaction.contact = contact
        context.insert(interaction)
    }

    private static func addArtifact(to contact: Contact, key: String, value: String, in context: ModelContext) {
        let artifact = Artifact(key: key, value: value)
        artifact.contact = contact
        context.insert(artifact)
    }

    private static func addArrayArtifact(to contact: Contact, key: String, values: [String], in context: ModelContext) {
        let jsonString = (try? JSONEncoder().encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let artifact = Artifact(key: key, value: jsonString, isArray: true)
        artifact.contact = contact
        context.insert(artifact)
    }

    private static func registerTag(name: String, in context: ModelContext) {
        // Only register if it doesn't already exist
        let searchName = name.lowercased()
        let predicate = #Predicate<Tag> { $0.searchableName == searchName }
        let descriptor = FetchDescriptor<Tag>(predicate: predicate)

        if let count = try? context.fetchCount(descriptor), count > 0 {
            return // Already registered
        }

        let tag = Tag(name: name)
        context.insert(tag)
    }

    private static func makeConstellation(name: String, notes: String, in context: ModelContext) -> Constellation {
        let constellation = Constellation(name: name, notes: notes)
        context.insert(constellation)
        return constellation
    }
}
