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
        case history = "历史记录"
        
        var icon: String {
            switch self {
            case .home:
                return "house"
            case .history:
                return "clock.arrow.circlepath"
            }
        }
        
        var selectedIcon: String {
            switch self {
            case .home:
                return "house.fill"
            case .history:
                return "clock.arrow.circlepath"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ContentView()
                .tabItem {
                    Label {
                        Text(Tab.home.rawValue)
                    } icon: {
                        Image(systemName: selectedTab == .home ? Tab.home.selectedIcon : Tab.home.icon)
                    }
                }
                .tag(Tab.home)
            
            HistoryView()
                .tabItem {
                    Label {
                        Text(Tab.history.rawValue)
                    } icon: {
                        Image(systemName: selectedTab == .history ? Tab.history.selectedIcon : Tab.history.icon)
                    }
                }
                .tag(Tab.history)
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
