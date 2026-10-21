import SwiftUI

// MARK: - Reading Preferences Model
public enum ReadingFontFamily: String, CaseIterable, Identifiable, Codable, Sendable {
    case sans = "sans"
    case serif = "serif"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sans: return "黑体"
        case .serif: return "宋体"
        }
    }

    public func font(size: CGFloat) -> Font {
        switch self {
        case .sans:
            return Font.system(size: size, weight: .regular, design: .default)
        case .serif:
            return Font.system(size: size, weight: .regular, design: .serif)
        }
    }
}

public struct ReadingPreferences: Codable, Sendable, Hashable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var fontFamily: ReadingFontFamily
    public var theme: ReaderThemePreset
    public var followsSystemAppearance: Bool?
    public var usesDynamicType: Bool?
    public var isDarkMode: Bool
    public var horizontalMargin: CGFloat?
    public var paragraphSpacing: CGFloat?
    public var tapZoneFraction: Double?

    public init(
        fontSize: CGFloat = 17.0,
        lineSpacing: CGFloat = 8.0,
        fontFamily: ReadingFontFamily = .serif,
        theme: ReaderThemePreset = .paper,
        isDarkMode: Bool = false
    ) {
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.fontFamily = fontFamily
        self.theme = theme
        self.isDarkMode = isDarkMode
        self.horizontalMargin = 24
        self.paragraphSpacing = 0.5
        self.tapZoneFraction = 0.25
        self.followsSystemAppearance = true
        self.usesDynamicType = true
    }

    public static let minFontSize: CGFloat = 13.0
    public static let maxFontSize: CGFloat = 28.0
}

