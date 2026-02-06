//
//  MainTabView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/6.
//

import SwiftUI

// Main Tab View
struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    
    enum Tab: String, CaseIterable {
        case home = "主页"
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
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Image(systemName: selectedTab == .home ? Tab.home.selectedIcon : Tab.home.icon)
                        .environment(\.symbolVariants, .none)
                    Text(Tab.home.rawValue)
                }
                .tag(Tab.home)
            
            NavigationView {
                SavedLinksView()
            }
            .tabItem {
                Image(systemName: selectedTab == .savedLinks ? Tab.savedLinks.selectedIcon : Tab.savedLinks.icon)
                    .environment(\.symbolVariants, .none)
                Text(Tab.savedLinks.rawValue)
            }
            .tag(Tab.savedLinks)
            
            NavigationView {
                SettingsView()
            }
            .tabItem {
                Image(systemName: selectedTab == .settings ? Tab.settings.selectedIcon : Tab.settings.icon)
                    .environment(\.symbolVariants, .none)
                Text(Tab.settings.rawValue)
            }
            .tag(Tab.settings)
        }
        .tint(Color("AccentColor"))
    }
}

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
