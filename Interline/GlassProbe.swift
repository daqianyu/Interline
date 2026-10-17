import SwiftUI

// MARK: - Glass Probe & Liquid Glass Policy
// Strict adherence to AGENTS.md Section 4 (Liquid Glass Policy).
// Never covers text permanently; hides nonessential controls in immersive state;
// Uses native material with graceful fallback.

public enum GlassProbe {
    /// Probes availability of Liquid Glass runtime capabilities.
    public static var isLiquidGlassSupported: Bool {
        #if canImport(LiquidGlass)
        return true
        #else
        return false
        #endif
    }
}

public struct GlassEffectViewModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var isBordered: Bool
    public var shadowRadius: CGFloat

    public init(cornerRadius: CGFloat = ThemeTokens.Radius.glassBar, isBordered: Bool = false, shadowRadius: CGFloat = 16) {
        self.cornerRadius = cornerRadius
        self.isBordered = isBordered
        self.shadowRadius = shadowRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if isBordered {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                        }
                    }
                    .shadow(color: Color.black.opacity(0.08), radius: shadowRadius, x: 0, y: 8)
            }
    }
}

public struct GlassSheetViewModifier: ViewModifier {
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = ThemeTokens.Radius.sheet) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: cornerRadius,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: cornerRadius,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 0, y: -4)
            }
    }
}

public extension View {
    /// Floating inset glass container for navigation and reader controls.
    func interlineGlass(cornerRadius: CGFloat = ThemeTokens.Radius.glassBar, isBordered: Bool = false) -> some View {
        modifier(GlassEffectViewModifier(cornerRadius: cornerRadius, isBordered: isBordered))
    }

    /// Bottom sheet glass backdrop.
    func glassSheet(cornerRadius: CGFloat = ThemeTokens.Radius.sheet) -> some View {
        modifier(GlassSheetViewModifier(cornerRadius: cornerRadius))
    }
}
