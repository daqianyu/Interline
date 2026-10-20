import SwiftUI
import UIKit

/// Selection is intentionally a separate system text surface: native selection,
/// copying and lookup don't conflict with the reading canvas's page gestures.
struct TextSelectionSheet: View {
    let snapshot: ReadingSelectionSnapshot
    private var bookID: String { snapshot.bookID }
    private var chapterID: String { snapshot.page.chapterID }
    private var page: PageSlice { snapshot.page }
    private var text: String { snapshot.text }
    private var preferences: ReadingPreferences { snapshot.preferences }
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var note = ""
    @State private var writingNote = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("长按正文选择文字，可复制、查询、标注或写笔记。")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                SelectableTextView(text: text, preferences: preferences, selection: $selection)
                    .accessibilityIdentifier("selectableText")
            }
            .navigationTitle("选字与标注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("标注", systemImage: "highlighter") { save() }.disabled(selection.length == 0)
                    Spacer()
                    Button("写笔记", systemImage: "square.and.pencil") { writingNote = true }.disabled(selection.length == 0)
                }
            }
            .toolbar { ToolbarItem(placement: .bottomBar) { Text(selection.length > 0 ? "已选 \(selectedQuote.count) 字" : "请选择文字").font(.caption) } }
            .sheet(isPresented: $writingNote) {
                NavigationStack {
                    Form {
                        Section("摘录") { Text(selectedQuote).textSelection(.enabled) }
                        Section("笔记") { TextEditor(text: $note).frame(minHeight: 160).accessibilityLabel("笔记内容") }
                    }
                    .navigationTitle("写笔记")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { writingNote = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
                    }
                }
            }
        }
        .onChange(of: writingNote) { _, value in if value && selection.length == 0 { writingNote = false } }
    }

    private var selectedQuote: String {
        guard selection.location >= 0, selection.length > 0, NSMaxRange(selection) <= text.utf16.count else { return "" }
        return (text as NSString).substring(with: selection)
    }

    private func save() {
        guard !selectedQuote.isEmpty else { return }
        let range = NSRange(location: page.range.location + selection.location, length: selection.length)
        if appState.addAnnotation(bookID: bookID, chapterID: chapterID, range: range, note: note) {
            writingNote = false
            dismiss()
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String
    let preferences: ReadingPreferences
    @Binding var selection: NSRange

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.accessibilityIdentifier = "selectableText"
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = UIColor(preferences.theme.backgroundColor)
        view.textColor = UIColor(preferences.theme.textColor)
        view.textContainerInset = UIEdgeInsets(top: 16, left: 20, bottom: 24, right: 20)
        let base = UIFont.systemFont(ofSize: preferences.fontSize)
        let descriptor = preferences.fontFamily == .serif ? (base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor) : base.fontDescriptor
        let baseFont = UIFont(descriptor: descriptor, size: preferences.fontSize)
        let font = (preferences.usesDynamicType ?? true) ? UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont) : baseFont
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = preferences.lineSpacing
        view.attributedText = NSAttributedString(string: text, attributes: [.font: font,
            .foregroundColor: UIColor(preferences.theme.textColor), .paragraphStyle: paragraph])
        view.adjustsFontForContentSizeCategory = preferences.usesDynamicType ?? true
        view.delegate = context.coordinator
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) { context.coordinator.selection = $selection }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selection: Binding<NSRange>
        init(selection: Binding<NSRange>) { self.selection = selection }
        func textViewDidChangeSelection(_ textView: UITextView) { selection.wrappedValue = textView.selectedRange }
    }
}
