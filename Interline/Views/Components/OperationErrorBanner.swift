import SwiftUI

struct OperationErrorBanner: View {
    let message: String
    let retry: () -> Void
    let close: () -> Void
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .callout) private var messageHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(message)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("pageOperationError")
            }
            .frame(height: min(messageHeight, verticalSizeClass == .compact ? 80 : 180))
            HStack {
                Button("重试", action: retry).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("retryPageOperation")
                Spacer()
                Button("关闭提示", action: close).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("dismissPageOperationError")
            }
        }
        .font(.callout).padding(.horizontal).padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .background(.background)
    }
}
