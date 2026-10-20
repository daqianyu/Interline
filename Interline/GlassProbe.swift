import SwiftUI

public enum GlassProbe {
    public static var isLiquidGlassSupported: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

public struct GlassEffectViewModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    public var cornerRadius: CGFloat
    public var isBordered: Bool
    public var shadowRadius: CGFloat

    public init(cornerRadius: CGFloat = ThemeTokens.Radius.glassBar, isBordered: Bool = false, shadowRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        self.isBordered = isBordered
        self.shadowRadius = shadowRadius
    }

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

public extension View {
    func interlineGlass(cornerRadius: CGFloat = ThemeTokens.Radius.glassBar, isBordered: Bool = false) -> some View {
        modifier(GlassEffectViewModifier(cornerRadius: cornerRadius, isBordered: isBordered))
    }
    func glassSheet(cornerRadius: CGFloat = ThemeTokens.Radius.sheet) -> some View {
        background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius))
    }
}
