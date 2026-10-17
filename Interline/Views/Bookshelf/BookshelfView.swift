import SwiftUI

// MARK: - Bookshelf View
// Strict adherence to AGENTS.md Section 5 (Bookshelf core experience).

public struct BookshelfView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xl) {
                    
                    // Search bar when active or always available
                    if !appState.searchText.isEmpty || appState.isEditingBookshelf {
                        searchBar
                    }

                    // 1. Continue Reading (最优先：最近阅读的书籍与清晰的继续阅读行动)
                    if let featured = appState.featuredBook {
                        continueReadingSection(book: featured)
                    }

                    // 2. Collection of saved books
                    savedBooksSection

                }
                .padding(.horizontal, ThemeTokens.Spacing.lg)
                .padding(.top, ThemeTokens.Spacing.md)
                .padding(.bottom, 60)
            }
            .background(ThemeTokens.Colors.systemBackground)
            .navigationTitle("书架")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: {
                        withAnimation {
                            if appState.searchText.isEmpty {
                                appState.searchText = " "
                            } else {
                                appState.searchText = ""
                            }
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(ThemeTokens.Colors.label)
                    }

                    Button(action: {
                        withAnimation {
                            appState.isEditingBookshelf.toggle()
                        }
                    }) {
                        Text(appState.isEditingBookshelf ? "完成" : "编辑")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(appState.isEditingBookshelf ? ThemeTokens.Colors.link : ThemeTokens.Colors.label)
                    }
                }
            }
        }
    }

    // MARK: - Search Bar
    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(ThemeTokens.Colors.secondaryLabel)
            TextField("搜索书名或作者...", text: $appState.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))

            if !appState.searchText.isEmpty {
                Button(action: { appState.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ThemeTokens.Colors.tertiarySystemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Continue Reading Card
    @ViewBuilder
    private func continueReadingSection(book: Book) -> some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.xs) {
            Text("继续阅读")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(ThemeTokens.Colors.secondaryLabel)

            Button(action: {
                appState.openBook(book)
            }) {
                HStack(spacing: ThemeTokens.Spacing.md) {
                    BookCoverView(book: book, width: 78, height: 108)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.system(size: 17, weight: .semibold, design: .serif))
                            .foregroundColor(ThemeTokens.Colors.label)
                            .lineLimit(1)

                        Text(book.author)
                            .font(.system(size: 13))
                            .foregroundColor(ThemeTokens.Colors.secondaryLabel)

                        Spacer()

                        if let currentChapter = book.currentChapter {
                            Text(currentChapter.title)
                                .font(.system(size: 12))
                                .foregroundColor(ThemeTokens.Colors.tertiaryLabel)
                                .lineLimit(1)
                        }

                        // Progress indicator
                        HStack(spacing: 8) {
                            ProgressView(value: book.progressPercentage, total: 100.0)
                                .progressViewStyle(.linear)
                                .tint(ThemeTokens.Colors.label)
                                .frame(maxWidth: 120)

                            Text(String(format: "%.1f%%", book.progressPercentage))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(ThemeTokens.Colors.tertiaryLabel)
                }
                .padding(ThemeTokens.Spacing.md)
                .background(ThemeTokens.Colors.secondarySystemBackground)
                .clipShape(RoundedRectangle(cornerRadius: ThemeTokens.Radius.card, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Saved Books Grid
    private var savedBooksSection: some View {
        VStack(alignment: .leading, spacing: ThemeTokens.Spacing.sm) {
            HStack {
                Text("全部书目 (\(appState.filteredBooks.count))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ThemeTokens.Colors.secondaryLabel)

                Spacer()
            }

            LazyVGrid(columns: columns, spacing: ThemeTokens.Spacing.lg) {
                ForEach(appState.filteredBooks) { book in
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack(alignment: .topTrailing) {
                            Button(action: {
                                if !appState.isEditingBookshelf {
                                    appState.openBook(book)
                                }
                            }) {
                                BookCoverView(book: book, width: 102, height: 140)
                            }
                            .buttonStyle(.plain)

                            // Edit Mode Delete Button
                            if appState.isEditingBookshelf {
                                Button(action: {
                                    withAnimation {
                                        appState.deleteBook(id: book.id)
                                    }
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundColor(ThemeTokens.Colors.danger)
                                        .background(Color.white.clipShape(Circle()))
                                }
                                .offset(x: 6, y: -6)
                            }
                        }

                        Text(book.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(ThemeTokens.Colors.label)
                            .lineLimit(1)

                        Text(String(format: "%.0f%%", book.progressPercentage))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                    }
                }
            }
        }
    }
}
