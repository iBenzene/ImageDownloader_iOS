//
//  MainTabView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/6.
//

import SwiftUI

// Main Tab View
struct MainTabView: View {
    #if !targetEnvironment(macCatalyst)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var homeState = MobileHomeState()
    @State private var selectedTab: Tab = .home
    @State private var selectedSidebarItem: MobileSidebarItem? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var detailPath = NavigationPath()
    #endif
    
    enum Tab: String, CaseIterable {
        case home = "首页"
        case savedLinks = "已收藏"
        case settings = "设置"
        
        var icon: String {
            switch self {
            case .home:
                return "house"
            case .savedLinks:
                return "archivebox"
            case .settings:
                return "gearshape"
            }
        }
        
        var selectedIcon: String {
            switch self {
            case .home:
                return "house.fill"
            case .savedLinks:
                return "archivebox.fill"
            case .settings:
                return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        #if targetEnvironment(macCatalyst)
        MacMainView()
        #else
        Group {
            if horizontalSizeClass == .regular {
                regularSplitView
            } else {
                compactTabView
            }
        }
        .tint(Color("AccentColor"))
        .onChange(of: selectedTab) { newTab in
            switch newTab {
            case .home:
                if selectedSidebarItem != .history && selectedSidebarItem != .livePhotoConverter {
                    selectedSidebarItem = .home
                }
            case .savedLinks:
                selectedSidebarItem = .savedLinks
            case .settings:
                selectedSidebarItem = .settings
            }
        }
        .onChange(of: selectedSidebarItem) { newItem in
            detailPath = NavigationPath()
            switch newItem ?? .home {
            case .home, .history, .livePhotoConverter:
                selectedTab = .home
            case .savedLinks:
                selectedTab = .savedLinks
            case .settings:
                selectedTab = .settings
            }
        }
        #endif
    }
    
    #if !targetEnvironment(macCatalyst)
    private var regularSplitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                Section("导航") {
                    ForEach(MobileSidebarItem.primaryItems, id: \.self) { item in
                        MobileSidebarRow(
                            item: item,
                            isSelected: (selectedSidebarItem ?? .home) == item
                        ) {
                            selectedSidebarItem = item
                        }
                    }
                }
                
                Section("工具") {
                    ForEach(MobileSidebarItem.toolItems, id: \.self) { item in
                        MobileSidebarRow(
                            item: item,
                            isSelected: (selectedSidebarItem ?? .home) == item
                        ) {
                            selectedSidebarItem = item
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .toolbarBackground(.hidden, for: .navigationBar)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 0.5)
                    .ignoresSafeArea()
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
        } detail: {
            NavigationStack(path: $detailPath) {
                switch selectedSidebarItem ?? .home {
                case .home:
                    ContentView(
                        state: homeState,
                        embedsInNavigationStack: false,
                        showsToolNavigationInMenu: false
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
        .navigationSplitViewStyle(.balanced)
    }
    
    private var compactTabView: some View {
        TabView(selection: $selectedTab) {
            ContentView(state: homeState)
                .tabItem {
                    Image(systemName: selectedTab == .home ? Tab.home.selectedIcon : Tab.home.icon)
                        .environment(\.symbolVariants, .none)
                    Text(Tab.home.rawValue)
                }
                .tag(Tab.home)
            
            NavigationStack {
                SavedLinksView()
            }
            .tabItem {
                Image(systemName: selectedTab == .savedLinks ? Tab.savedLinks.selectedIcon : Tab.savedLinks.icon)
                    .environment(\.symbolVariants, .none)
                Text(Tab.savedLinks.rawValue)
            }
            .tag(Tab.savedLinks)
            
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Image(systemName: selectedTab == .settings ? Tab.settings.selectedIcon : Tab.settings.icon)
                    .environment(\.symbolVariants, .none)
                Text(Tab.settings.rawValue)
            }
            .tag(Tab.settings)
        }
    }
    #endif
}

#if !targetEnvironment(macCatalyst)
private enum MobileSidebarItem: String, CaseIterable {
    case home
    case savedLinks
    case history
    case livePhotoConverter
    case settings
    
    static let primaryItems: [MobileSidebarItem] = [.home, .savedLinks, .history, .settings]
    static let toolItems: [MobileSidebarItem] = [.livePhotoConverter]
    
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

private struct MobileSidebarRow: View {
    let item: MobileSidebarItem
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isSelected ? Color.white : Color("AccentColor"))
                    .frame(width: 24, alignment: .center)
                
                Text(item.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color("AccentColor"))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        .listRowBackground(Color.clear)
    }
}
#endif

// 预览
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainTabView()
                .previewDisplayName("Light Mode")
            
            MainTabView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
