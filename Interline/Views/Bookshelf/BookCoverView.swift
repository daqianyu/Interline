import SwiftUI

// MARK: - Book Cover Component
// Strict adherence to AGENTS.md Section 3 & Section 5 (Bookshelf cover aesthetics)
// Elegant Chinese book cover with subtle shadow, restrained styling, no garish borders.

public struct BookCoverView: View {
    public let book: Book
    public var width: CGFloat
    public var height: CGFloat

    public init(book: Book, width: CGFloat = 86, height: CGFloat = 118) {
        self.book = book
        self.width = width
        self.height = height
    }

    private var themeColor: Color {
        Color(hex: book.themeColorHex) ?? Color(red: 0.12, green: 0.12, blue: 0.14)
    }

    private var textColor: Color {
        Color(hex: book.textColorHex) ?? Color(red: 0.95, green: 0.95, blue: 0.96)
    }

    public var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Book cover base
            Rectangle()
                .fill(themeColor)

            // Subtle paper spine shadow gradient on left edge
            LinearGradient(
                colors: [Color.black.opacity(0.24), Color.clear],
                startPoint: .leading,
                endPoint: UnitPoint(x: 0.15, y: 0.5)
            )

            // Book Cover Content (Title and Author)
            VStack(alignment: .leading, spacing: 3) {
                Spacer()

                Text(book.title)
                    .font(.system(size: max(11, width * 0.14), weight: .bold, design: .serif))
                    .foregroundColor(textColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(2)

                Text(book.author)
                    .font(.system(size: max(9, width * 0.10), weight: .regular))
                    .foregroundColor(textColor.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(max(6, width * 0.08))
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.cover, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 3)
    }
}

// MARK: - Hex Color Helper
private extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let intVal = UInt64(cleanHex, radix: 16) else { return nil }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
