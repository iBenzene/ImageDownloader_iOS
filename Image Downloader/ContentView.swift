//
//  ContentView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2023/12/26.
//  Copyright (c) 2023 iBenzene. All rights reserved.
//

import SwiftUI
import UIKit

final class MobileHomeState: ObservableObject {
    @Published var linkInput: String = ""
    @Published var feedbackMessage: String?
    @Published var isError: Bool = false
    @Published var isWarning: Bool = false
    @Published var isDownloading: Bool = false
    @Published var showingDuplicateAlert: Bool = false
    @Published var pendingSavedLinks: [String] = []
    @Published var pendingSavedLinksDownloader: ImageDownloaderType?
    @Published var selectedDownloader: ImageDownloaderType = .xhsLiveImg
}

struct ContentView: View {
    @ObservedObject var state: MobileHomeState
    var embedsInNavigationStack: Bool = true
    var showsToolNavigationInMenu: Bool = true

    @State private var showingLivePhotoConverter = false
    @State private var showingHistory = false
    
    @State private var editorContentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    
    @AppStorage("saveLinksOnly") private var saveLinksOnly: Bool = false
    @AppStorage("preheatResources") private var preheatResources: Bool = false

    init(
        state: MobileHomeState = MobileHomeState(),
        embedsInNavigationStack: Bool = true,
        showsToolNavigationInMenu: Bool = true
    ) {
        self.state = state
        self.embedsInNavigationStack = embedsInNavigationStack
        self.showsToolNavigationInMenu = showsToolNavigationInMenu
    }
    
    var body: some View {
        if embedsInNavigationStack {
            NavigationStack {
                homeContent
            }
        } else {
            homeContent
        }
    }
    
    private var homeContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    GeometryReader { geometryProxy in
                        Color.clear.preference(
                            key: HomeScrollOffsetPreferenceKey.self,
                            value: geometryProxy.frame(in: .named("HomeScroll")).minY
                        )
                    }
                    .frame(height: 0)
                    
                    VStack(alignment: .leading, spacing: 18) {
                        logoHeader
                        
                        ZStack(alignment: .topLeading) {
                            HomeExpandingTextView(
                                text: $state.linkInput,
                                measuredHeight: $editorContentHeight
                            )
                            .frame(
                                minHeight: max(editorContentHeight, minimumEditorHeight(for: proxy.size.height)),
                                maxHeight: .infinity
                            )
                            
                            if state.linkInput.isEmpty {
                                Text("请粘贴链接，每行一个")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, HomeEditorMetrics.textContainerInset.top)
                                    .padding(.leading, HomeEditorMetrics.textContainerInset.left)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 108)
                }
                .coordinateSpace(name: "HomeScroll")
                .scrollIndicators(.visible)
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(HomeScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = max(0, -value)
                }
                
                scrollEdgeGlass
                
                bottomActionBar
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .homeSeamlessTabBar()
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("下载器类型", selection: $state.selectedDownloader) {
                        ForEach(ImageDownloaderType.allCases, id: \.self) { downloaderType in
                            Text(downloaderType.rawValue)
                                .tag(downloaderType)
                        }
                    }
                    
                    if showsToolNavigationInMenu {
                        Divider()
                        
                        Button {
                            showingLivePhotoConverter = true
                        } label: {
                            Label("实况图片转换器", systemImage: "livephoto")
                        }

                        Button {
                            showingHistory = true
                        } label: {
                            Label("下载记录", systemImage: "clock.arrow.circlepath")
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(Color("AccentColor"))
                }
            }
        }
        .background {
            if showsToolNavigationInMenu {
                // 用于跳转到「实况图片转换器」页面
                NavigationLink(
                    destination: LivePhotoConverterView(),
                    isActive: $showingLivePhotoConverter,
                    label: { EmptyView() }
                )
                .hidden()
                
                // 用于跳转到「下载记录」页面
                NavigationLink(
                    destination: HistoryView(),
                    isActive: $showingHistory,
                    label: { EmptyView() }
                )
                .hidden()
            }
        }
        .alert("重复链接提醒", isPresented: $state.showingDuplicateAlert) {
            Button("取消", role: .cancel) {
                state.pendingSavedLinks = []
                state.pendingSavedLinksDownloader = nil
                state.feedbackMessage = "已取消收藏"
                state.isError = false
                state.isWarning = true
                state.isDownloading = false
            }
            Button("继续") {
                continueSavingPendingLinks()
            }
        } message: {
            Text("检测到收藏列表或本次输入中存在重复链接或相同内容，是否继续收藏？")
        }
    }
    
    private var logoHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("logo")
                .resizable()
                .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("苯苯存图")
                    .font(.title2.weight(.semibold))
                Text(state.selectedDownloader.rawValue)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var bottomActionBar: some View {
        VStack(alignment: .center, spacing: 12) {
            if let message = state.feedbackMessage {
                feedbackCapsule(message: message)
            }
            
            actionButtonsCapsule
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
    }
    
    private var actionButtonsCapsule: some View {
        HStack(spacing: 4) {
            Button(action: pasteButtonTapped) {
                HomeCapsuleActionItemLabel(
                    title: "粘贴",
                    systemImage: "doc.on.clipboard"
                )
            }
            .buttonStyle(.plain)
            
            Button(action: startPrimaryAction) {
                HomeCapsuleActionItemLabel(
                    title: saveLinksOnly ? "收藏" : "下载",
                    systemImage: saveLinksOnly ? "link.badge.plus" : "tray.and.arrow.down"
                )
            }
            .buttonStyle(.plain)
            .disabled(state.isDownloading)
            .opacity(state.isDownloading ? 0.6 : 1)
            
            Button {
                state.linkInput = ""
                state.feedbackMessage = nil
            } label: {
                HomeCapsuleActionItemLabel(
                    title: "删除",
                    systemImage: "trash"
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(.background.opacity(0.48))
                }
                .overlay {
                    Capsule()
                        .stroke(.white.opacity(0.72), lineWidth: 0.8)
                }
                .overlay {
                    Capsule()
                        .stroke(.primary.opacity(0.08), lineWidth: 0.6)
                }
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }
    
    private func feedbackCapsule(message: String) -> some View {
        Label(message, systemImage: feedbackIcon)
            .font(.callout)
            .foregroundStyle(feedbackColor)
            .lineLimit(2)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
    }
    
    private var scrollEdgeGlass: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(min(scrollOffset / 72, 1))
                .frame(height: 72)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.86), location: 0.62),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Spacer()
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
    
    private func minimumEditorHeight(for containerHeight: CGFloat) -> CGFloat {
        max(260, containerHeight - 170)
    }
    
    private var feedbackIcon: String {
        if state.isError { return "exclamationmark.triangle" }
        if state.isWarning { return "exclamationmark.circle" }
        if state.isDownloading { return "arrow.down.circle" }
        return "checkmark.circle"
    }
    
    private var feedbackColor: Color {
        if state.isError { return .red }
        if state.isWarning || state.isDownloading { return .yellow }
        return .green
    }
    
    @MainActor
    private func startPrimaryAction() {
        guard !state.isDownloading else { return }
        
        let input = state.linkInput
        let downloaderType = state.selectedDownloader
        let shouldSaveLinksOnly = saveLinksOnly
        
        state.feedbackMessage = shouldSaveLinksOnly ? "正在收藏..." : "准备下载..."
        state.isError = false
        state.isWarning = false
        state.isDownloading = true
        
        Task {
            if shouldSaveLinksOnly {
                await saveLinksButtonTapped(input: input, downloaderType: downloaderType)
            } else {
                await downloadButtonTapped(input: input, downloaderType: downloaderType)
            }
        }
    }
    
    @MainActor
    private func continueSavingPendingLinks() {
        guard !state.isDownloading else { return }
        
        let urls = state.pendingSavedLinks
        let downloaderType = state.pendingSavedLinksDownloader ?? state.selectedDownloader
        
        state.feedbackMessage = "正在收藏..."
        state.isError = false
        state.isWarning = false
        state.isDownloading = true
        
        Task {
            await saveLinks(urls, downloaderType: downloaderType)
        }
    }
    
    // 执行下载操作
    func downloadButtonTapped(input: String, downloaderType: ImageDownloaderType) async {
        let result = await DownloadManager.shared.performDownload(
            from: input,
            downloaderType: downloaderType,
            invalidLineHandling: .skipWithWarning,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )
        
        Task { @MainActor in
            applyWorkflowResult(result)
        }
    }

    private func applyFeedback(_ feedback: HomeWorkflowFeedback) {
        state.feedbackMessage = feedback.message
        state.isError = feedback.isError
        state.isWarning = feedback.isWarning
        state.isDownloading = feedback.isDownloading
    }

    private func applyWorkflowResult(_ result: HomeWorkflowResult) {
        if result.shouldClearInput {
            state.linkInput = ""
        }

        applyFeedback(result.feedback)
    }

    private func handleSavePreparation(
        _ preparation: HomeSavePreparation,
        downloaderType: ImageDownloaderType
    ) async {
        switch preparation {
        case .ready(let urls):
            await saveLinks(urls, downloaderType: downloaderType)
        case .needsDuplicateConfirmation(let urls):
            state.pendingSavedLinks = urls
            state.pendingSavedLinksDownloader = downloaderType
            state.showingDuplicateAlert = true
            state.feedbackMessage = "请确认是否继续收藏"
            state.isError = false
            state.isWarning = true
            state.isDownloading = false
        case .feedback(let feedback):
            applyFeedback(feedback)
        }
    }

    private func saveLinks(_ urls: [String], downloaderType: ImageDownloaderType) async {
        let result = await DownloadManager.shared.saveLinks(
            urls,
            downloaderType: downloaderType,
            shouldPreheatResources: preheatResources,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )

        Task { @MainActor in
            state.pendingSavedLinks = []
            state.pendingSavedLinksDownloader = nil
            applyWorkflowResult(result)
        }
    }

    // 执行粘贴操作
    func pasteButtonTapped() {
        if let clipboardContent = UIPasteboard.general.string {
            if state.linkInput.isEmpty {
                state.linkInput += clipboardContent
            }
            else {
                state.linkInput += "\n" + clipboardContent
            }
        } else {
            state.feedbackMessage = "剪贴板为空"
            state.isError = true
        }
    }
    
    // 执行收藏操作
    func saveLinksButtonTapped(input: String, downloaderType: ImageDownloaderType) async {
        await handleSavePreparation(
            await DownloadManager.shared.prepareSaveLinks(from: input, downloaderType: downloaderType),
            downloaderType: downloaderType
        )
    }
}

private struct HomeCapsuleActionItemLabel: View {
    let title: String
    let systemImage: String
    var tint: Color = Color("AccentColor")
    @State private var isHovered = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 52, height: 44)
            .background {
                if isHovered {
                    Capsule()
                        .fill(.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
            .accessibilityLabel(title)
            .onHover { isHovered = $0 }
    }
}

private struct HomeExpandingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    
    func makeUIView(context: Context) -> UITextView {
        let textView = HomeUITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.textContainerInset = HomeEditorMetrics.textContainerInset
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }
    
    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        
        recalculateHeight(for: textView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight)
    }
    
    private func recalculateHeight(for textView: UITextView) {
        DispatchQueue.main.async {
            let fittingWidth = max(textView.bounds.width, 1)
            let targetSize = CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
            let newHeight = textView.sizeThatFits(targetSize).height
            
            if abs(measuredHeight - newHeight) > 0.5 {
                measuredHeight = newHeight
            }
        }
    }
    
    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String
        @Binding private var measuredHeight: CGFloat
        
        init(text: Binding<String>, measuredHeight: Binding<CGFloat>) {
            _text = text
            _measuredHeight = measuredHeight
        }
        
        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            
            let fittingWidth = max(textView.bounds.width, 1)
            let targetSize = CGSize(width: fittingWidth, height: .greatestFiniteMagnitude)
            let newHeight = textView.sizeThatFits(targetSize).height
            
            if abs(measuredHeight - newHeight) > 0.5 {
                measuredHeight = newHeight
            }
        }
    }
}

private enum HomeEditorMetrics {
    static let textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
}

private final class HomeUITextView: UITextView {
    private var isHandlingSelectAll = false
    
    override var keyCommands: [UIKeyCommand]? {
        let selectAll = UIKeyCommand(
            input: "a",
            modifierFlags: .command,
            action: #selector(selectAllWithoutScrollJump(_:))
        )
        return (super.keyCommands ?? []) + [selectAll]
    }
    
    @objc private func selectAllWithoutScrollJump(_ sender: UIKeyCommand) {
        isHandlingSelectAll = true
        selectedRange = NSRange(location: 0, length: textStorage.length)
        isHandlingSelectAll = false
    }
    
    override func scrollRangeToVisible(_ range: NSRange) {
        guard !isHandlingSelectAll else { return }
        super.scrollRangeToVisible(range)
    }
}

private struct HomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension View {
    @ViewBuilder
    func homeSeamlessTabBar() -> some View {
        if #unavailable(iOS 26) {
            self.toolbarBackground(.hidden, for: .tabBar)
        } else {
            self
        }
    }
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDisplayName("Light Mode")
            
            ContentView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
