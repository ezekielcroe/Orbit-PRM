import SwiftUI

// MARK: - Orbit Design System
// Swiss/International Typographic Style: grid-based layout, left-aligned text,
// hierarchy through weight and size alone, zero decorative chrome.
// Typography IS the interface — font weight encodes relationship strength,
// opacity encodes recency.

// MARK: - Spacing (8-point grid)
enum OrbitSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64
}

// MARK: - Colors
// Maximum two accent colors. Hierarchy is created through weight and opacity.
enum OrbitColors {
    // Primary text — high contrast
    static let textPrimary = Color.primary

    // Secondary text — for metadata, timestamps, keys
    static let textSecondary = Color.secondary

    // Muted — for archived, inactive elements
    static let textMuted = Color.secondary.opacity(0.5)

    // Syntax highlighting colors for the command palette
    static let syntaxEntity = Color.blue          // @contacts
    static let syntaxImpulse = Color.orange       // !actions
    static let syntaxTag = Color.green            // #tags
    static let syntaxArtifact = Color.purple      // >artifacts
    static let syntaxQuote = Color.brown          // "quoted text"
    static let syntaxTime = Color.cyan            // ^time modifiers
    static let syntaxConstellation = Color.pink   // *constellations
    static let syntaxInvalid = Color.secondary.opacity(0.4) // Unparsed text

    // Status colors — used sparingly
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red

    // Background for the command palette
    #if os(iOS)
    static let commandBackground = Color(UIColor.systemBackground)
    #else
    static let commandBackground = Color(NSColor.windowBackgroundColor)
    #endif
}

// MARK: - Color Convenience
// SwiftUI doesn't have a built-in light/dark initializer like this,
// so we use conditional compilation for each platform.
#if os(iOS)
extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(dark)
                : UIColor(light)
        })
    }
}
#endif

// MARK: - Typography
// One encoding everywhere: a contact's name weight reflects their closeness
// (the orbit the user chose). Recency and drift are said in words and, where
// it matters, a single colour — never by fading the name, so the people you
// most need to see are never the hardest to read.
enum OrbitTypography {

    // MARK: Contact Name Display

    /// Contact name styled by closeness. Inner circle = bold, deep space = regular.
    static func contactName(orbit: Int) -> Font {
        .system(size: 17, weight: weightForOrbit(orbit), design: .default)
    }

    /// Large contact name for detail views
    static func contactNameLarge(orbit: Int) -> Font {
        .system(size: 28, weight: weightForOrbit(orbit), design: .default)
    }

    /// Map orbit zone (0–4) to font weight. The floor is .regular so names
    /// always meet contrast and legibility expectations.
    private static func weightForOrbit(_ orbit: Int) -> Font.Weight {
        switch orbit {
        case 0: return .bold
        case 1: return .semibold
        case 2: return .medium
        default: return .regular
        }
    }

    // MARK: Standard Text Styles

    static let body = Font.system(size: 15, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 15, weight: .medium, design: .default)
    static let caption = Font.system(size: 13, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let footnote = Font.system(size: 11, weight: .regular, design: .default)
    static let title = Font.system(size: 22, weight: .semibold, design: .default)
    static let headline = Font.system(size: 17, weight: .semibold, design: .default)

    // MARK: Command Palette
    static let commandInput = Font.system(size: 17, weight: .regular, design: .monospaced)
    static let commandSuggestion = Font.system(size: 15, weight: .regular, design: .default)

    // MARK: Artifact Display
    static let artifactKey = Font.system(size: 13, weight: .medium, design: .default)
    static let artifactValue = Font.system(size: 15, weight: .regular, design: .default)
}

// MARK: - Orbit Zone Helpers
enum OrbitZone {
    static let allZones: [(id: Int, name: String, description: String)] = [
        (0, "Inner Circle", "Your closest people — partners, family, best friends. Weekly."),
        (1, "Near Orbit", "Close friends you see regularly. Monthly."),
        (2, "Mid Orbit", "Good friends and active colleagues. Every few months."),
        (3, "Outer Orbit", "Acquaintances and distant friends. Yearly."),
        (4, "Deep Space", "People you don't need reminders about."),
    ]

    static func name(for orbit: Int) -> String {
        allZones.first(where: { $0.id == orbit })?.name ?? "Unknown"
    }
}

// MARK: - View Modifiers

/// Applies the Swiss-style card treatment: no borders, no shadows, just spacing
struct OrbitCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(OrbitSpacing.md)
    }
}

extension View {
    func orbitCard() -> some View {
        modifier(OrbitCardModifier())
    }
}

// MARK: - Platform Abstraction
#if os(macOS)
extension Color {
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                ? NSColor(dark)
                : NSColor(light)
        })
    }
}
#endif
