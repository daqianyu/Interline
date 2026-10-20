import SwiftUI

public struct TOCSheetView: View {
    public let book: Book
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0
    @State private var filter = ""
    public init(book: Book) { self.book = book }
    private var current: Book { appState.activeBook ?? book }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分类", selection: $selectedTab) {
                    Text("目录").tag(0)
                    Text("书签 (\(appState.currentBookBookmarks.count))").tag(1)
                    Text("笔记 (\(appState.currentBookAnnotations.count))").tag(2)
                }
                .pickerStyle(.segmented).padding()
                if selectedTab == 0 {
                    TextField("查找章节", text: $filter).textFieldStyle(.roundedBorder).padding(.horizontal)
                    ScrollViewReader { proxy in
                        List {
                            ForEach(Array(current.chapters.enumerated()).filter { filter.isEmpty || $0.element.title.localizedCaseInsensitiveContains(filter) }, id: \.element.id) { index, chapter in
                                Button {
                                    appState.jumpToChapter(index)
                                } label: {
                                    HStack {
                                        Text(chapter.title)
                                        Spacer()
                                        if index == current.currentChapterIndex { Image(systemName: "book.fill").accessibilityLabel("当前章节") }
                                    }
                                    .foregroundStyle(index == current.currentChapterIndex ? Color.accentColor : .primary)
                                    .padding(.vertical, 4)
                                }
                                .id(chapter.id)
                            }
                        }
                        .listStyle(.plain)
                        .onAppear { if let id = current.currentChapter?.id { proxy.scrollTo(id, anchor: .center) } }
                    }
                } else if selectedTab == 1 {
                    if appState.currentBookBookmarks.isEmpty { ContentUnavailableView("暂无书签", systemImage: "bookmark") }
                    else {
                        List(appState.currentBookBookmarks) { bookmark in
                            Button { appState.jumpToBookmark(bookmark) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(bookmark.chapterTitle).font(.headline)
                                    Text(bookmark.snippet).foregroundStyle(.secondary).lineLimit(3)
                                }
                            }
                            .swipeActions { Button("删除", role: .destructive) { appState.removeBookmark(id: bookmark.id) } }
                        }
                    }
                } else { AnnotationsListView(bookID: current.id) }
            }
            .navigationTitle("目录与笔记")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { appState.isTOCPresented = false } } }
        }
    }
}
