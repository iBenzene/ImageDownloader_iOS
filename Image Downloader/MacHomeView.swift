//
//  MacHomeView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/7/1.
//

import SwiftUI
import UIKit

#if targetEnvironment(macCatalyst)
struct MacHomeState {
    var linkInput: String = ""
    var feedbackMessage: String?
    var isError = false
    var isWarning = false
    var isDownloading = false
    var showingDuplicateAlert = false
    var pendingSavedLinks: [String] = []
    var selectedDownloader: ImageDownloaderType = .xhsImg
}

struct MacHomeView: View {
    @Binding var state: MacHomeState
    @State private var editorContentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    
    @AppStorage("saveLinksOnly") private var saveLinksOnly = false
    @AppStorage("preheatResources") private var preheatResources = false
    
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    GeometryReader { geometryProxy in
                        Color.clear.preference(
                            key: MacHomeScrollOffsetPreferenceKey.self,
                            value: geometryProxy.frame(in: .named("MacHomeScroll")).minY
                        )
                    }
                    .frame(height: 0)
                    
                    VStack(alignment: .leading, spacing: 18) {
                        logoHeader
                        
                        ZStack(alignment: .topLeading) {
                            MacExpandingTextView(
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
                                    .padding(.top, MacHomeEditorMetrics.textContainerInset.top)
                                    .padding(.leading, MacHomeEditorMetrics.textContainerInset.left)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 92)
                }
                .coordinateSpace(name: "MacHomeScroll")
                .scrollIndicators(.visible)
                .onPreferenceChange(MacHomeScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = max(0, -value)
                }
                
                scrollEdgeGlass
                
                bottomActionBar
            }
        }
        .navigationTitle("首页")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    ForEach(ImageDownloaderType.allCases, id: \.self) { downloaderType in
                        Button {
                            state.selectedDownloader = downloaderType
                        } label: {
                            if state.selectedDownloader == downloaderType {
                                Label(downloaderType.rawValue, systemImage: "checkmark")
                            } else {
                                Text(downloaderType.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .macToolbarSymbolStyle()
                }
                .help("选择下载器")
            }
        }
        .alert("重复链接提醒", isPresented: $state.showingDuplicateAlert) {
            Button("取消", role: .cancel) {
                state.pendingSavedLinks = []
                state.feedbackMessage = "已取消收藏"
                state.isWarning = true
            }
            Button("继续") {
                Task {
                    await saveLinks(state.pendingSavedLinks)
                }
            }
        } message: {
            Text("检测到收藏列表中已存在部分链接，是否继续收藏？")
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
        HStack(alignment: .bottom, spacing: 14) {
            if let message = state.feedbackMessage {
                Label(message, systemImage: feedbackIcon)
                    .font(.callout)
                    .foregroundStyle(feedbackColor)
                    .lineLimit(2)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 14, y: 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
            
            Button {
                Task {
                    if saveLinksOnly {
                        await saveLinksButtonTapped()
                    } else {
                        await downloadButtonTapped()
                    }
                }
            } label: {
                MacPrimaryActionButtonLabel(
                    title: saveLinksOnly ? "收藏" : "下载",
                    systemImage: saveLinksOnly ? "link.badge.plus" : "arrow.down"
                )
            }
            .buttonStyle(.plain)
            .disabled(state.isDownloading)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
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
    
    private func downloadButtonTapped() async {
        let result = await DownloadManager.shared.performDownload(
            from: state.linkInput,
            downloaderType: state.selectedDownloader,
            invalidLineHandling: .skipWithWarning,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )
        
        Task { @MainActor in
            applyWorkflowResult(result)
        }
    }
    
    private func saveLinksButtonTapped() async {
        await handleSavePreparation(DownloadManager.shared.prepareSaveLinks(from: state.linkInput))
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

    private func handleSavePreparation(_ preparation: HomeSavePreparation) async {
        switch preparation {
        case .ready(let urls):
            await saveLinks(urls)
        case .needsDuplicateConfirmation(let urls):
            state.pendingSavedLinks = urls
            state.showingDuplicateAlert = true
        case .feedback(let feedback):
            applyFeedback(feedback)
        }
    }

    private func saveLinks(_ urls: [String]) async {
        let result = await DownloadManager.shared.saveLinks(
            urls,
            downloaderType: state.selectedDownloader,
            shouldPreheatResources: preheatResources,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )

        Task { @MainActor in
            state.pendingSavedLinks = []
            applyWorkflowResult(result)
        }
    }
}

private struct MacPrimaryActionButtonLabel: View {
    let title: String
    let systemImage: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color("AccentColor"))
        }
        .frame(width: 58, height: 58)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(.background.opacity(isHovered ? 0.64 : 0.48))
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
        .contentShape(Capsule())
        .accessibilityLabel(title)
        .onHover { isHovered = $0 }
    }
}

private struct MacExpandingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    
    func makeUIView(context: Context) -> UITextView {
        let textView = MacHomeUITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.isScrollEnabled = false
        textView.alwaysBounceVertical = false
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.textContainerInset = MacHomeEditorMetrics.textContainerInset
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

private enum MacHomeEditorMetrics {
    static let textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 16, right: 0)
}

private final class MacHomeUITextView: UITextView {
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

private struct MacHomeScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
