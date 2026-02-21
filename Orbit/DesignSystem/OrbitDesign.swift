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
// Contact names use variable weight to encode relationship strength.
// Phase 1: Maps targetOrbit to weight (simpler). Phase 3 will use cachedMomentum.
// Uses the system font (SF Pro) which has excellent variable weight support.
enum OrbitTypography {

    // MARK: Contact Name Display

    /// Contact name styled by orbit proximity.
    /// Inner circle = heavy, deep space = thin.
    static func contactName(orbit: Int) -> Font {
        let weight = weightForOrbit(orbit)
        return .system(size: 17, weight: weight, design: .default)
    }

    /// Large contact name for detail views
    static func contactNameLarge(orbit: Int) -> Font {
        let weight = weightForOrbit(orbit)
        return .system(size: 28, weight: weight, design: .default)
    }

    /// Map orbit zone (0–4) to font weight
    /// 0 (Inner Circle) → .bold
    /// 4 (Deep Space) → .ultraLight
    private static func weightForOrbit(_ orbit: Int) -> Font.Weight {
        switch orbit {
        case 0: return .bold
        case 1: return .semibold
        case 2: return .medium
        case 3: return .regular
        case 4: return .light
        default: return .regular
        }
    }

    // MARK: Opacity for Cadence

    /// Opacity based on days since last contact.
    /// Recently contacted → fully opaque. Neglected → translucent.
    static func opacityForRecency(daysSinceContact: Int?) -> Double {
        guard let days = daysSinceContact else { return 0.4 } // Never contacted
        switch days {
        case 0...7: return 1.0
        case 8...30: return 0.85
        case 31...90: return 0.65
        case 91...180: return 0.5
        case 181...365: return 0.35
        default: return 0.25
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
        (0, "Inner Circle", "Your closest relationships — partners, family, best friends"),
        (1, "Near Orbit", "Close friends you see regularly"),
        (2, "Mid Orbit", "Good friends and active colleagues"),
        (3, "Outer Orbit", "Acquaintances and distant friends"),
        (4, "Deep Space", "Archived or very distant connections"),
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
