import SwiftUI

public struct ToastOverlaysView: View {
    @EnvironmentObject private var appState: AppState
    public init() {}
    public var body: some View {
        if let notice = appState.notice {
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: notice.isError ? "exclamationmark.triangle" : "checkmark.circle")
                    Text(notice.message).font(.callout)
                    if let action = notice.action {
                        Button(action == .undoRemoval ? "撤销" : "重试") {
                            switch action {
                            case .undoRemoval: appState.undoDelete()
                            case .retryCleanup: appState.retryPendingDeletions()
                            }
                        }
                    }
                    Button { appState.notice = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                        .accessibilityLabel("关闭提示")
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .interlineGlass(cornerRadius: 18, isBordered: true)
                .padding(.horizontal, 16).padding(.bottom, 24)
                .accessibilityElement(children: .contain)
            }
        }
    }
}
