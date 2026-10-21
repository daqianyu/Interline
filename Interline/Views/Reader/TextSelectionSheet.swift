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
    @State private var editingDraft: NoteDraft?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("长按正文选择文字，可复制、查询、标注或写笔记。")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal)
                Button("选中本段") { selectParagraph() }
                    .padding(.horizontal).accessibilityIdentifier("selectParagraph")
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
                    Button("写笔记", systemImage: "square.and.pencil") { beginNote() }.accessibilityIdentifier("writeNote").disabled(selection.length == 0)
                }
            }
            .toolbar { ToolbarItem(placement: .bottomBar) { Text(selection.length > 0 ? "已选 \(selectedQuote.count) 字" : "请选择文字").font(.caption) } }
            .sheet(item: $editingDraft) { draft in
                NoteEditorView(draft: appState.draft(for: draft.id) ?? draft) { dismiss() }
            }
        }
    }

    private func beginNote() {
        guard !selectedQuote.isEmpty else { return }
        editingDraft = NoteDraft(bookID: bookID, chapterID: chapterID,
            range: NSRange(location: page.range.location + selection.location, length: selection.length), quote: selectedQuote)
    }
    private func selectParagraph() {
        let source = text as NSString
        guard source.length > 0 else { return }
        let separator = source.range(of: "\n\n")
        let start = page.range.location == 0 && separator.location != NSNotFound ? NSMaxRange(separator) : 0
        guard start < source.length else { return }
        let end = source.range(of: "\n\n", range: NSRange(location: start, length: source.length - start))
        let length = end.location == NSNotFound ? source.length - start : end.location - start
        selection = source.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: length))
    }

    private var selectedQuote: String {
        guard selection.location >= 0, selection.length > 0, NSMaxRange(selection) <= text.utf16.count else { return "" }
        return (text as NSString).substring(with: selection)
    }

    private func save() {
        guard !selectedQuote.isEmpty else { return }
        let range = NSRange(location: page.range.location + selection.location, length: selection.length)
        if appState.addAnnotation(bookID: bookID, chapterID: chapterID, range: range) {
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
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.selection = $selection
        if view.selectedRange != selection, NSMaxRange(selection) <= view.text.utf16.count {
            view.selectedRange = selection
            if selection.length > 0 { view.becomeFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var selection: Binding<NSRange>
        init(selection: Binding<NSRange>) { self.selection = selection }
        func textViewDidChangeSelection(_ textView: UITextView) {
            if selection.wrappedValue != textView.selectedRange { selection.wrappedValue = textView.selectedRange }
        }
    }
}
