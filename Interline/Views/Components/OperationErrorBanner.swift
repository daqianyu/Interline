import SwiftUI

struct OperationErrorBanner: View {
    let message: String
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).foregroundStyle(.red).accessibilityIdentifier("pageOperationError")
            HStack {
                Button("重试", action: retry).frame(minHeight: 44).accessibilityIdentifier("retryPageOperation")
                Spacer()
                Button("关闭提示", action: close).frame(minHeight: 44).accessibilityIdentifier("dismissPageOperationError")
            }
        }
        .font(.callout).padding(.horizontal).padding(.top, 8)
        .background(Color.red.opacity(0.08))
    }
}
