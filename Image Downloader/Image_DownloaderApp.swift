//
//  Image_DownloaderApp.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2023/12/26.
//

import SwiftUI
import UIKit

@main
struct Image_DownloaderApp: App {
    init() {
        // Ensure UIKit components (like Alerts) use the accent color
        if let accentColor = UIColor(named: "AccentColor") {
            UIView.appearance().tintColor = accentColor
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }
}
