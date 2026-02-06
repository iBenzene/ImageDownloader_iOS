//
//  SavedLinksManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/7.
//

import Foundation
import SwiftUI

// Saved Link Status
enum SavedLinkStatus: String, Codable, Equatable {
    case none
    case success
    case failure
}

// Saved Link Item Model
struct SavedLinkItem: Identifiable, Codable, Equatable {
    let id: UUID
    let url: String              // The saved URL
    let timestamp: Date          // When the link was saved
    let downloaderType: String   // The downloader type used (e.g. "小红书图片下载器")
    var status: SavedLinkStatus  // Download status
    
    init(url: String, downloaderType: String, status: SavedLinkStatus = .none) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.downloaderType = downloaderType
        self.status = status
    }
    
    // Custom decoding to handle legacy data
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(String.self, forKey: .url)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.downloaderType = try container.decodeIfPresent(String.self, forKey: .downloaderType) ?? "小红书图片下载器"
        self.status = try container.decodeIfPresent(SavedLinkStatus.self, forKey: .status) ?? .none
    }
}

// Saved Links Manager
class SavedLinksManager: ObservableObject {
    static let shared = SavedLinksManager()
    
    @Published private(set) var items: [SavedLinkItem] = []
    
    private let storageKey = "savedLinks"
    private let maxItems = 500  // Maximum number of saved links to keep
    
    private init() {
        loadItems()
    }
    
    // Public Methods
    
    // Add a new saved link
    func addLink(url: String, downloaderType: String) {
        let item = SavedLinkItem(url: url, downloaderType: downloaderType)
        
        // Insert at the beginning (newest first)
        items.insert(item, at: 0)
        
        // Trim if exceeds max items
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveItems()
    }
    
    // Add multiple links at once
    func addLinks(urls: [String], downloaderType: String) {
        for url in urls {
            let item = SavedLinkItem(url: url, downloaderType: downloaderType)
            items.insert(item, at: 0)
        }
        
        // Trim if exceeds max items
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
        
        saveItems()
    }
    
    // Update status for a specific item
    func updateStatus(for item: SavedLinkItem, newStatus: SavedLinkStatus) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.status = newStatus
            items[index] = updatedItem
            saveItems()
        }
    }
    
    // Delete a single saved link
    func deleteItem(_ item: SavedLinkItem) {
        items.removeAll { $0.id == item.id }
        saveItems()
    }
    
    // Delete items at specific indices
    func deleteItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        saveItems()
    }
    
    // Clear all saved links
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
            items = try JSONDecoder().decode([SavedLinkItem].self, from: data)
        } catch {
            print("⚠️ Failed to load saved links: \(error.localizedDescription)")
            items = []
        }
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("⚠️ Failed to save links: \(error.localizedDescription)")
        }
    }
}

// Date Formatting Extension & Helpers
extension SavedLinkItem {
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
