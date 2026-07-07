//
//  MacMainView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/7/1.
//

import SwiftUI

#if targetEnvironment(macCatalyst)
struct MacMainView: View {
    @State private var selectedItem: MacSidebarItem? = .home
    @State private var detailPath = NavigationPath()
    @State private var homeState = MacHomeState()
    @StateObject private var clipboardMonitor = MacClipboardMonitor()
    @AppStorage("macClipboardListeningEnabled") private var clipboardListeningEnabled = false
    @AppStorage("saveLinksOnly") private var saveLinksOnly = false
    @AppStorage("preheatResources") private var preheatResources = false
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("导航") {
                    ForEach(MacSidebarItem.primaryItems, id: \.self) { item in
                        Label(item.title, systemImage: item.icon)
                            .lineLimit(1)
                            .tag(item)
                    }
                }
                
                Section("工具") {
                    ForEach(MacSidebarItem.toolItems, id: \.self) { item in
                        Label(item.title, systemImage: item.icon)
                            .lineLimit(1)
                            .tag(item)
                    }
                }
            }
            .navigationTitle("苯苯存图")
            .listStyle(.sidebar)
            .font(.title3.weight(.medium))
            .environment(\.defaultMinListRowHeight, 38)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            NavigationStack(path: $detailPath) {
                switch selectedItem ?? .home {
                case .home:
                    MacHomeView(
                        state: $homeState,
                        isClipboardListening: clipboardListeningEnabled
                    )
                case .savedLinks:
                    SavedLinksView()
                case .history:
                    HistoryView()
                case .livePhotoConverter:
                    LivePhotoConverterView()
                case .settings:
                    SettingsView()
                }
            }
        }
        .tint(Color("AccentColor"))
        .onChange(of: selectedItem) { _ in
            detailPath = NavigationPath()
        }
        .onAppear {
            clipboardMonitor.setListening(clipboardListeningEnabled)
        }
        .onChange(of: clipboardListeningEnabled) { enabled in
            clipboardMonitor.setListening(enabled)
        }
        .onChange(of: clipboardMonitor.recognizedTextRequest) { request in
            guard let request else { return }
            let shouldSubmitImmediately = homeState.appendClipboardText(request.text)
            guard shouldSubmitImmediately else { return }

            submitAccumulatedClipboardInput()
        }
        .alert("重复链接提醒", isPresented: $homeState.showingDuplicateAlert) {
            Button("取消", role: .cancel) {
                homeState.pendingSavedLinks = []
                homeState.pendingSavedLinksDownloader = nil
                homeState.pendingSubmittedInput = nil
                homeState.feedbackMessage = "已取消收藏"
                homeState.isError = false
                homeState.isWarning = true
                homeState.isDownloading = false
            }
            Button("继续") {
                MacHomeWorkflow.continueSavingPendingLinks(
                    state: $homeState,
                    preheatResources: preheatResources,
                    onWorkflowFinished: submitAccumulatedClipboardInput
                )
            }
        } message: {
            Text("检测到收藏列表中已存在部分链接，是否继续收藏？")
        }
    }

    @MainActor
    private func submitAccumulatedClipboardInput() {
        guard clipboardListeningEnabled,
              !homeState.isDownloading,
              !homeState.showingDuplicateAlert,
              DownloadManager.shared.hasRecognizedLinks(in: homeState.linkInput) else {
            return
        }

        MacHomeWorkflow.submitCurrentInput(
            state: $homeState,
            saveLinksOnly: saveLinksOnly,
            preheatResources: preheatResources,
            onWorkflowFinished: submitAccumulatedClipboardInput
        )
    }
}

enum MacSidebarItem: String, CaseIterable {
    case home
    case savedLinks
    case history
    case livePhotoConverter
    case settings
    
    static let primaryItems: [MacSidebarItem] = [.home, .savedLinks, .history, .settings]
    static let toolItems: [MacSidebarItem] = [.livePhotoConverter]
    
    var title: String {
        switch self {
        case .home:
            return "首页"
        case .savedLinks:
            return "已收藏"
        case .history:
            return "下载记录"
        case .livePhotoConverter:
            return "实况图片转换器"
        case .settings:
            return "设置"
        }
    }
    
    var icon: String {
        switch self {
        case .home:
            return "house"
        case .savedLinks:
            return "archivebox"
        case .history:
            return "clock.arrow.circlepath"
        case .livePhotoConverter:
            return "livephoto"
        case .settings:
            return "gearshape"
        }
    }
}

extension View {
    func macToolbarSymbolStyle() -> some View {
        self
            .font(.system(size: 16, weight: .medium))
    }
}

struct MacToolbarCircleIconButton: View {
    let systemName: String
    let tint: Color
    var isDisabled = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                    .frame(width: 24)
                Image(systemName: systemName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(tint)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .opacity(isDisabled ? 0.5 : 1.0)
        .disabled(isDisabled)
    }
}

#endif
