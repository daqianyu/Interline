import SwiftUI

// MARK: - Safe Area Debug Overlay
// Useful for verifying inset margins and status bar / home bar distances.

public struct SafeAreaDebugOverlay: View {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public var body: some View {
        if isEnabled {
            GeometryReader { geo in
                ZStack {
                    // Safe Area Border
                    Rectangle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 1)
                        .padding(.top, geo.safeAreaInsets.top)
                        .padding(.bottom, geo.safeAreaInsets.bottom)
                        .padding(.leading, geo.safeAreaInsets.leading)
                        .padding(.trailing, geo.safeAreaInsets.trailing)

                    // Inset Indicator Label
                    VStack {
                        Text("Top: \(Int(geo.safeAreaInsets.top))pt | Bottom: \(Int(geo.safeAreaInsets.bottom))pt")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding(.top, geo.safeAreaInsets.top + 4)

                        Spacer()
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
