import SwiftUI

// MARK: - Theme Tokens & Design System
// Strict adherence to AGENTS.md Section 3 (Color, Typography, Spacing).

public enum ThemeTokens {
    // Spacing scale based on multiples of 4pt
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
        public static let safeInsetSides: CGFloat = 21 // Liquid glass inset
    }

    public enum Radius {
        public static let cover: CGFloat = 4
        public static let card: CGFloat = 12
        public static let glassBar: CGFloat = 22
        public static let sheet: CGFloat = 20
        public static let pill: CGFloat = 9999
    }

    public enum Colors {
        public static let accent = Color.primary
        public static let link = Color.blue
        public static let danger = Color.red
        public static let separator = Color(.separator)
        public static let secondarySeparator = Color(.opaqueSeparator)
        
        public static let systemBackground = Color(.systemBackground)
        public static let secondarySystemBackground = Color(.secondarySystemBackground)
        public static let tertiarySystemBackground = Color(.tertiarySystemBackground)
        
        public static let label = Color(.label)
        public static let secondaryLabel = Color(.secondaryLabel)
        public static let tertiaryLabel = Color(.tertiaryLabel)
    }
}

// MARK: - Reader Theme Definition
public enum ReaderThemePreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case paper = "paper"
    case warm = "warm"
    case mint = "mint"
    case night = "night"
    case oled = "oled"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .paper: return "纸白"
        case .warm: return "羊皮"
        case .mint: return "青草"
        case .night: return "暮夜"
        case .oled: return "极夜"
        }
    }

    public var isDark: Bool {
        switch self {
        case .night, .oled: return true
        default: return false
        }
    }

    public var backgroundColor: Color {
        switch self {
        case .paper: return Color(red: 0.97, green: 0.97, blue: 0.98) // #F8F8FA
        case .warm: return Color(red: 0.96, green: 0.94, blue: 0.90)  // #F4EFE6
        case .mint: return Color(red: 0.92, green: 0.95, blue: 0.92)  // #EBF2EB
        case .night: return Color(red: 0.11, green: 0.11, blue: 0.12) // #1C1C1E
        case .oled: return Color.black                                 // #000000
        }
    }

    public var textColor: Color {
        switch self {
        case .paper: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .warm: return Color(red: 0.21, green: 0.17, blue: 0.14)
        case .mint: return Color(red: 0.13, green: 0.20, blue: 0.15)
        case .night: return Color(red: 0.84, green: 0.84, blue: 0.86)
        case .oled: return Color(red: 0.82, green: 0.82, blue: 0.84)
        }
    }

    public var secondaryTextColor: Color {
        switch self {
        case .paper: return Color(red: 0.42, green: 0.42, blue: 0.44)
        case .warm: return Color(red: 0.50, green: 0.44, blue: 0.38)
        case .mint: return Color(red: 0.40, green: 0.50, blue: 0.42)
        case .night: return Color(red: 0.56, green: 0.56, blue: 0.58)
        case .oled: return Color(red: 0.50, green: 0.50, blue: 0.52)
        }
    }
}
