import SwiftUI

// MARK: - Root Content View & Immersive Reader
// Strict adherence to AGENTS.md Section 5 (Reader & Bookshelf) and Section 6 (Interaction Rules).

public struct RootContentView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        ZStack {
            // Main Bookshelf View
            BookshelfView()

            // Immersive Reader Screen
            if appState.isReaderPresented, let book = appState.activeBook {
                ReaderContainerView(book: book)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(10)
            }

            // Global Toast Overlays
            ToastOverlaysView()
                .zIndex(100)
        }
        .preferredColorScheme(appState.preferences.isDarkMode ? .dark : (appState.preferences.theme.isDark ? .dark : .light))
    }
}

// MARK: - Immersive Reader Container View
public struct ReaderContainerView: View {
    public let book: Book
    @EnvironmentObject private var appState: AppState

    public init(book: Book) {
        self.book = book
    }

    private var theme: ReaderThemePreset {
        appState.preferences.theme
    }

    public var body: some View {
        ZStack {
            // 1. Reading Canvas Background
            theme.backgroundColor
                .ignoresSafeArea()

            // 2. Reading Text Canvas & Tap Detection
            VStack(spacing: 0) {
                // Header spacing placeholder
                Spacer().frame(height: 54)

                // Chapter Content
                if let currentChapter = book.currentChapter {
                    VStack(alignment: .leading, spacing: appState.preferences.lineSpacing + 8) {
                        // Chapter Title (First page only)
                        if book.currentPageIndex == 0 {
                            Text(currentChapter.title)
                                .font(appState.preferences.fontFamily.font(size: appState.preferences.fontSize + 4).weight(.semibold))
                                .foregroundColor(theme.textColor)
                                .padding(.bottom, 6)
                        }

                        // Paragraphs
                        ForEach(Array(currentChapter.content.enumerated()), id: \.offset) { _, para in
                            Text(para)
                                .font(appState.preferences.fontFamily.font(size: appState.preferences.fontSize))
                                .foregroundColor(theme.textColor)
                                .lineSpacing(appState.preferences.lineSpacing)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                }

                // Bottom Page Number & Chapter Info
                HStack {
                    Text(book.currentChapter?.title ?? "")
                        .lineLimit(1)
                    Spacer()
                    Text("第 \(book.currentPageIndex + 1) 页")
                        .font(.system(size: 10, design: .monospaced))
                }
                .font(.system(size: 11))
                .foregroundColor(theme.secondaryTextColor)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location)
            }

            // 3. Top Floating Glass Navigation Header
            if appState.areControlsVisible {
                VStack {
                    HStack {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                appState.closeReader()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("书架")
                                    .font(.system(size: 15))
                            }
                            .foregroundColor(ThemeTokens.Colors.label)
                            .frame(minHeight: 44)
                        }

                        Spacer()

                        Text(book.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                            .lineLimit(1)

                        Spacer()

                        Button(action: {
                            appState.toggleBookmark()
                        }) {
                            Image(systemName: appState.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 16))
                                .foregroundColor(appState.isCurrentPageBookmarked ? ThemeTokens.Colors.link : ThemeTokens.Colors.label)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .interlineGlass(cornerRadius: 22, isBordered: false)
                    .padding(.horizontal, ThemeTokens.Spacing.safeInsetSides)
                    .padding(.top, 8)

                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 4. Bottom Floating Glass Control Bar (21pt Inset, 22pt Radius)
            if appState.areControlsVisible {
                VStack {
                    Spacer()

                    // Secondary Progress Indicator (10pt, non-intercepting)
                    Text(String(format: "全书进度 · %.1f%%", book.progressPercentage))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                        .padding(.bottom, 6)

                    HStack {
                        // TOC Button
                        Button(action: {
                            appState.isTOCPresented = true
                        }) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(ThemeTokens.Colors.label)
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        // Prev / Next Chapter Buttons
                        HStack(spacing: 20) {
                            Button(action: { appState.prevChapter() }) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ThemeTokens.Colors.label)
                                    .frame(width: 44, height: 44)
                            }
                            .disabled(book.currentChapterIndex <= 0)
                            .opacity(book.currentChapterIndex <= 0 ? 0.35 : 1.0)

                            Button(action: { appState.nextChapter() }) {
                                Image(systemName: "chevron.forward")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ThemeTokens.Colors.label)
                                    .frame(width: 44, height: 44)
                            }
                            .disabled(book.currentChapterIndex >= book.chapters.count - 1)
                            .opacity(book.currentChapterIndex >= book.chapters.count - 1 ? 0.35 : 1.0)
                        }

                        Spacer()

                        // Typography Settings Button
                        Button(action: {
                            appState.isSettingsPresented = true
                        }) {
                            Text("Aa")
                                .font(.system(size: 17, weight: .medium, design: .serif))
                                .foregroundColor(ThemeTokens.Colors.label)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .interlineGlass(cornerRadius: 22, isBordered: false)
                    .padding(.horizontal, ThemeTokens.Spacing.safeInsetSides)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $appState.isTOCPresented) {
            TOCSheetView(book: book)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            ReaderSettingsSheetView()
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleTap(at point: CGPoint) {
        let screenWidth = UIScreen.main.bounds.width
        if appState.areControlsVisible {
            appState.hideControls()
            return
        }
        if point.x < screenWidth * 0.25 {
            appState.prevPage()
        } else if point.x > screenWidth * 0.75 {
            appState.nextPage()
        } else {
            appState.toggleControls()
        }
    }
}

// MARK: - Table of Contents & Bookmarks Sheet
public struct TOCSheetView: View {
    public let book: Book
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: Int = 0

    public init(book: Book) {
        self.book = book
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分类", selection: $selectedTab) {
                    Text("目录").tag(0)
                    Text("书签 (\(appState.currentBookBookmarks.count))").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if selectedTab == 0 {
                    List {
                        ForEach(Array(book.chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(action: {
                                appState.jumpToChapter(index)
                            }) {
                                HStack {
                                    Text(chapter.title)
                                        .font(.system(size: 15, weight: index == book.currentChapterIndex ? .semibold : .regular))
                                        .foregroundColor(index == book.currentChapterIndex ? ThemeTokens.Colors.link : ThemeTokens.Colors.label)
                                    Spacer()
                                    if index == book.currentChapterIndex {
                                        Image(systemName: "bookmark.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(ThemeTokens.Colors.link)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    if appState.currentBookBookmarks.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Image(systemName: "bookmark")
                                .font(.system(size: 36))
                                .foregroundColor(ThemeTokens.Colors.tertiaryLabel)
                            Text("暂无书签")
                                .font(.system(size: 14))
                                .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(appState.currentBookBookmarks) { bookmark in
                                Button(action: {
                                    appState.jumpToChapter(bookmark.chapterIndex)
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(bookmark.chapterTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(ThemeTokens.Colors.label)
                                        Text(bookmark.snippet)
                                            .font(.system(size: 12))
                                            .foregroundColor(ThemeTokens.Colors.secondaryLabel)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .navigationTitle("目录与书签")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        appState.isTOCPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - Typography & Reading Settings Sheet
public struct ReaderSettingsSheetView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Font Size Adjuster
                HStack {
                    Text("字号")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ThemeTokens.Colors.secondaryLabel)

                    Spacer()

                    HStack(spacing: 20) {
                        Button(action: {
                            if appState.preferences.fontSize > ReadingPreferences.minFontSize {
                                appState.updatePreferences { $0.fontSize -= 1.0 }
                            }
                        }) {
                            Text("A-")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(width: 44, height: 36)
                                .background(ThemeTokens.Colors.tertiarySystemBackground)
                                .cornerRadius(8)
                        }

                        Text("\(Int(appState.preferences.fontSize))")
                            .font(.system(size: 14, design: .monospaced))
                            .frame(minWidth: 24)

                        Button(action: {
                            if appState.preferences.fontSize < ReadingPreferences.maxFontSize {
                                appState.updatePreferences { $0.fontSize += 1.0 }
                            }
                        }) {
                            Text("A+")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 44, height: 36)
                                .background(ThemeTokens.Colors.tertiarySystemBackground)
                                .cornerRadius(8)
                        }
                    }
                }

                // Font Family (黑体 vs 宋体)
                HStack {
                    Text("字体")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ThemeTokens.Colors.secondaryLabel)

                    Spacer()

                    Picker("字体", selection: Binding(
                        get: { appState.preferences.fontFamily },
                        set: { newFont in appState.updatePreferences { $0.fontFamily = newFont } }
                    )) {
                        ForEach(ReadingFontFamily.allCases) { font in
                            Text(font.displayName).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }

                // Themes Preset Swatches
                HStack {
                    Text("背景")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ThemeTokens.Colors.secondaryLabel)

                    Spacer()

                    HStack(spacing: 12) {
                        ForEach(ReaderThemePreset.allCases) { theme in
                            Circle()
                                .fill(theme.backgroundColor)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(appState.preferences.theme == theme ? ThemeTokens.Colors.link : Color.gray.opacity(0.3), lineWidth: appState.preferences.theme == theme ? 2.5 : 1)
                                )
                                .onTapGesture {
                                    appState.updatePreferences { $0.theme = theme }
                                }
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .navigationTitle("排版设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        appState.isSettingsPresented = false
                    }
                }
            }
        }
    }
}
