import SwiftUI

// MARK: - Toast Overlays View
// Lightweight, non-intrusive toast notifications with Undo capability.

public struct ToastOverlaysView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        if let message = appState.toastMessage {
            VStack {
                Spacer()

                HStack(spacing: ThemeTokens.Spacing.sm) {
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(ThemeTokens.Colors.label)

                    if message.contains("移出") {
                        Button(action: {
                            withAnimation {
                                appState.undoDelete()
                            }
                        }) {
                            Text("撤销")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(ThemeTokens.Colors.link)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .interlineGlass(cornerRadius: 18, isBordered: true)
                .padding(.bottom, 36)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.toastMessage)
        }
    }
}
