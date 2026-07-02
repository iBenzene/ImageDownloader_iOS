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
            homeState.submitClipboardText(request.text)
        }
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
