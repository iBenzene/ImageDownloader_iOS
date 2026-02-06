//
//  HistoryManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/6.
//

import Foundation
import SwiftUI

// History Item Model
struct HistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: String              // The original URL that was downloaded
    let downloaderType: String   // The downloader type used
    let timestamp: Date          // When the download occurred
    let isSuccess: Bool          // Whether the download was successful
    let mediaCount: Int          // Number of media items downloaded
    
    init(url: String, downloaderType: String, isSuccess: Bool, mediaCount: Int = 1) {
        self.id = UUID()
        self.url = url
        self.downloaderType = downloaderType
        self.timestamp = Date()
        self.isSuccess = isSuccess
        self.mediaCount = mediaCount
    }
}

// History Manager
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published private(set) var items: [HistoryItem] = []
    
    private let storageKey = "downloadHistory"
    private let maxItems = 500  // Maximum number of history items to keep
    
    private init() {
        loadItems()
    }
    
    // Public Methods
    
    // Add a new history record
    func addRecord(url: String, downloaderType: String, isSuccess: Bool, mediaCount: Int = 1) {
        let item = HistoryItem(
            url: url,
            downloaderType: downloaderType,
            isSuccess: isSuccess,
            mediaCount: mediaCount
        )
        
        // Insert at the beginning (newest first)
        items.insert(item, at: 0)
        
        // Trim if exceeds max items
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveItems()
    }
    
    // Delete a single history item
    func deleteItem(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }
    
    // Delete items at specific indices
    func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }
    
    // Clear all history
    func clearAll() {
        items.removeAll()
        saveItems()
    }
    
    // Private Methods
    
    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            items = []
            return
        }
        
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            print("⚠️ Failed to load history: \(error.localizedDescription)")
            items = []
        }
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("⚠️ Failed to save history: \(error.localizedDescription)")
        }
    }
}

// Date Formatting Extension
extension HistoryItem {
    var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(timestamp) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInYesterday(timestamp) {
            formatter.dateFormat = "昨天 HH:mm"
        } else if calendar.isDate(timestamp, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM/dd HH:mm"
        } else {
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
        }
        
        return formatter.string(from: timestamp)
    }
    
    // Get a short display name for the downloader type
    var shortDownloaderName: String {
        switch downloaderType {
        case "小红书图片下载器":
            return "小红书图片"
        case "小红书实况图片下载器":
            return "小红书实况"
        case "小红书视频下载器":
            return "小红书视频"
        case "米游社图片下载器":
            return "米游社"
        case "微博图片下载器":
            return "微博"
        case "Pixiv 图片下载器":
            return "Pixiv"
        default:
            return downloaderType
        }
    }
}
