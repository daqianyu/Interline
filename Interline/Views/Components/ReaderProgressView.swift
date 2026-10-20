import SwiftUI

/// Commit a seek on release, avoiding repeated chapter layout during a drag.
struct ReaderProgressView: View {
    @EnvironmentObject private var appState: AppState
    @State private var fraction = 0.0
    @State private var isScrubbing = false

    private var currentFraction: Double { (appState.activeBook?.progressPercentage ?? 0) / 100 }

    var body: some View {
        VStack(spacing: 4) {
            Text(String(format: "全书进度 · %.1f%%", (isScrubbing ? fraction : currentFraction) * 100))
                .font(.caption.monospacedDigit())
            Slider(value: Binding(
                get: { isScrubbing ? fraction : currentFraction },
                set: { fraction = $0 }
            ), in: 0...1, onEditingChanged: { editing in
                if editing { fraction = currentFraction }
                isScrubbing = editing
                if !editing { appState.jumpToProgress(fraction) }
            })
            .disabled(appState.pagination == nil)
            .accessibilityLabel("全书阅读进度")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .interlineGlass(cornerRadius: ThemeTokens.Radius.glassBar)
    }
}
