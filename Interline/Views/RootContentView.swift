import SwiftUI

// MARK: - Root Content View & Immersive Reader
// Strict adherence to AGENTS.md Section 5 (Reader & Bookshelf) and Section 6 (Interaction Rules).

public struct RootContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, phase in if phase != .active { appState.persistSession() } }
        .preferredColorScheme((appState.preferences.followsSystemAppearance ?? true) ? nil : (appState.preferences.isDarkMode ? .dark : .light))
        .transaction { transaction in
            if reduceMotion { transaction.animation = nil; transaction.disablesAnimations = true }
        }
    }
}

// MARK: - Immersive Reader Container View
public struct ReaderContainerView: View {
    public let book: Book
    @EnvironmentObject private var appState: AppState

    @ScaledMetric(relativeTo: .body) private var readingScale: CGFloat = 1

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

            // Measure precisely the canvas that will draw Core Text's frames.
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    ZStack {
                        Color.clear
                        if let layout = appState.pagination {
                            ReaderPageView(pagination: layout, pageIndex: book.currentPageIndex, annotations: appState.currentBookAnnotations, searchHighlight: appState.searchHighlight)
                                .accessibilityHidden(true)
                        } else if let error = appState.paginationError {
                            ContentUnavailableView(error, systemImage: "text.badge.xmark")
                        } else if appState.isLoadingBook {
                            ProgressView("正在加载正文")
                        } else if book.chapters.isEmpty {
                            ContentUnavailableView("本书暂无章节", systemImage: "book.closed")
                        } else {
                            ProgressView("正在排版")
                        }
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                        appState.presentTextSelection()
                    })
                    .onTapGesture { point in handleTap(at: point, width: geometry.size.width) }
                    .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                        if appState.areControlsVisible { appState.hideControls(); return }
                        if value.translation.width < 0 { appState.nextPage() }
                        else { appState.prevPage() }
                    })
                    .accessibilityHint("轻点中间显示工具，左右翻页；长按可选字与标注")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(appState.paginationError ?? (appState.currentPageText.isEmpty ? "正在排版" : appState.currentPageText))
                    .accessibilityAction(named: Text("下一页")) { appState.nextPage() }
                    .accessibilityAction(named: Text("上一页")) { appState.prevPage() }
                    .accessibilityAction(named: Text("显示阅读工具")) { appState.toggleControls() }
                    .accessibilityAction(named: Text("选字与标注")) { appState.presentTextSelection() }
                    .accessibilityIdentifier("readerCanvas")
                    .onChange(of: geometry.size, initial: true) { _, size in
                        appState.prepareReader(size: size, scale: readingScale)
                    }
                    .onChange(of: readingScale) { _, scale in appState.prepareReader(size: geometry.size, scale: scale) }
                }
                HStack {
                    Text(book.currentChapterTitle ?? "")
                        .lineLimit(1)
                    Spacer()
                    Text(appState.pagination == nil ? "正在排版" : "\(book.currentPageIndex + 1) / \(appState.pagination?.pages.count ?? 1)")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(theme.secondaryTextColor)
                .accessibilityLabel("本章第 \(book.currentPageIndex + 1) 页，共 \(appState.pagination?.pages.count ?? 1) 页")
            }
            .padding(.horizontal, appState.preferences.horizontalMargin ?? 24)
            .padding(.top, 12)
            .padding(.bottom, 12)

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

                        Button {
                            appState.isBookSearchPresented = true
                        } label: {
                            Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("搜索正文")
                        .accessibilityIdentifier("readerSearch")
                        .disabled(appState.isLoadingBook || book.chapters.isEmpty)
                        Button {
                            appState.presentTextSelection()
                        } label: {
                            Image(systemName: "text.cursor").frame(width: 44, height: 44)
                        }
                        .disabled(appState.currentPage == nil)
                        .accessibilityLabel("选字与标注")
                        .accessibilityIdentifier("readerSelection")

                        Button(action: {
                            appState.toggleBookmark()
                        }) {
                            Image(systemName: appState.isCurrentPageBookmarked ? "bookmark.fill" : "bookmark")
                                .font(.system(size: 16))
                                .foregroundColor(appState.isCurrentPageBookmarked ? ThemeTokens.Colors.link : ThemeTokens.Colors.label)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(appState.isCurrentPageBookmarked ? "移除书签" : "添加书签")
                        .disabled(appState.currentPage == nil)
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

                    if !appState.navigationHistory.isEmpty {
                        Button("返回刚才位置", systemImage: "arrow.uturn.backward") { appState.returnToPreviousLocation() }
                            .padding(.horizontal, 12).frame(minHeight: 44).interlineGlass(cornerRadius: 16)
                            .accessibilityIdentifier("returnToReadingLocation")
                    }
                    ReaderProgressView()
                        .padding(.horizontal, ThemeTokens.Spacing.safeInsetSides)

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

                        .accessibilityLabel("目录、书签与笔记")
                        .accessibilityIdentifier("readerTOC")

                        Spacer()

                        // Prev / Next Chapter Buttons
                        HStack(spacing: 20) {
                            Button(action: { appState.prevChapter() }) {
                                Image(systemName: "chevron.backward")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ThemeTokens.Colors.label)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("上一章")
                            .disabled(book.currentChapterIndex <= 0)
                            .opacity(book.currentChapterIndex <= 0 ? 0.35 : 1.0)

                            Button(action: { appState.nextChapter() }) {
                                Image(systemName: "chevron.forward")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(ThemeTokens.Colors.label)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("下一章")
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
                        .accessibilityLabel("排版设置")
                        .accessibilityIdentifier("readerSettings")
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
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .sheet(isPresented: $appState.isBookSearchPresented) { BookSearchView(book: book) }
        .sheet(item: $appState.selectionSnapshot) { snapshot in
            TextSelectionSheet(snapshot: snapshot).id(snapshot.id)
        }
        .sheet(isPresented: $appState.isTOCPresented) {
            TOCSheetView(book: book)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            ReaderSettingsSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func handleTap(at point: CGPoint, width: CGFloat) {
        if appState.areControlsVisible {
            appState.hideControls()
            return
        }
        let zone = min(0.4, max(0.15, appState.preferences.tapZoneFraction ?? 0.25))
        if point.x < width * zone {
            appState.prevPage()
        } else if point.x > width * (1 - zone) {
            appState.nextPage()
        } else {
            appState.toggleControls()
        }
    }
}

// MARK: - Typography & Reading Settings Sheet
public struct ReaderSettingsSheetView: View {
    @EnvironmentObject private var appState: AppState

    public init() {}

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Toggle("正文跟随系统文字大小", isOn: Binding(
                        get: { appState.preferences.usesDynamicType ?? true },
                        set: { value in appState.updatePreferences { $0.usesDynamicType = value } }
                    ))
                    Picker("应用外观", selection: Binding(
                        get: { (appState.preferences.followsSystemAppearance ?? true) ? 0 : (appState.preferences.isDarkMode ? 2 : 1) },
                        set: { mode in appState.updatePreferences { $0.followsSystemAppearance = mode == 0; $0.isDarkMode = mode == 2 } }
                    )) {
                        Text("跟随系统").tag(0)
                        Text("浅色").tag(1)
                        Text("深色").tag(2)
                    }
                    Text("应用外观与下面的阅读纸张背景分别设置。")
                        .font(.caption).foregroundStyle(.secondary)

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
                                    .frame(width: 44, height: 44)
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
                                    .frame(width: 44, height: 44)
                                    .background(ThemeTokens.Colors.tertiarySystemBackground)
                                    .cornerRadius(8)
                            }
                        }
                    }

                    HStack {
                        Text("行距")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(ThemeTokens.Colors.secondaryLabel)
                        Slider(value: Binding(
                            get: { appState.preferences.lineSpacing },
                            set: { spacing in appState.updatePreferences { $0.lineSpacing = spacing } }
                        ), in: 0...20, step: 2)
                        .accessibilityLabel("行距")
                        Text("\(Int(appState.preferences.lineSpacing))")
                            .monospacedDigit()
                            .frame(minWidth: 24)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("页边距").font(.callout)
                        Slider(value: Binding(get: { appState.preferences.horizontalMargin ?? 24 }, set: { value in appState.updatePreferences { $0.horizontalMargin = value } }), in: 12...48, step: 4)
                            .accessibilityLabel("页边距")
                        Text("段间距").font(.callout)
                        Slider(value: Binding(get: { appState.preferences.paragraphSpacing ?? 0.5 }, set: { value in appState.updatePreferences { $0.paragraphSpacing = value } }), in: 0...1.5, step: 0.25)
                            .accessibilityLabel("段间距")
                        Picker("翻页热区", selection: Binding(get: { appState.preferences.tapZoneFraction ?? 0.25 }, set: { value in appState.updatePreferences { $0.tapZoneFraction = value } })) {
                            Text("较窄").tag(0.2)
                            Text("标准").tag(0.25)
                            Text("较宽").tag(0.35)
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
                                Button {
                                    appState.updatePreferences { $0.theme = theme }
                                } label: {
                                    Circle()
                                    .fill(theme.backgroundColor)
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Circle()
                                            .stroke(appState.preferences.theme == theme ? ThemeTokens.Colors.link : Color.gray.opacity(0.3), lineWidth: appState.preferences.theme == theme ? 2.5 : 1)
                                    )
                                }
                                .frame(width: 44, height: 44)
                                .buttonStyle(.plain)
                                .accessibilityLabel(theme.displayName)
                                .accessibilityAddTraits(appState.preferences.theme == theme ? .isSelected : [])
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
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

