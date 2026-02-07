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
    let url: String
    var timestamp: Date
    let downloaderType: String
    var status: SavedLinkStatus
    
    // Sync Metadata
    var updatedAt: Date
    var isDeleted: Bool
    var isDirty: Bool
    
    init(url: String, downloaderType: String, status: SavedLinkStatus = .none) {
        self.id = UUID()
        self.url = url
        self.timestamp = Date()
        self.downloaderType = downloaderType
        self.status = status
        
        self.updatedAt = Date()
        self.isDeleted = false
        self.isDirty = true
    }
    
    // Internal init for merging/syncing
    init(id: UUID, url: String, timestamp: Date, downloaderType: String, status: SavedLinkStatus, updatedAt: Date, isDeleted: Bool, isDirty: Bool) {
        self.id = id
        self.url = url
        self.timestamp = timestamp
        self.downloaderType = downloaderType
        self.status = status
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.isDirty = isDirty
    }
    
    // Custom decoding for migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.url = try container.decode(String.self, forKey: .url)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.downloaderType = try container.decodeIfPresent(String.self, forKey: .downloaderType) ?? "小红书图片下载器"
        self.status = try container.decodeIfPresent(SavedLinkStatus.self, forKey: .status) ?? .none
        
        // Migration: New sync fields
        self.updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? timestamp
        self.isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        self.isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? true
    }
}

// Saved Links Manager
class SavedLinksManager: ObservableObject {
    static let shared = SavedLinksManager()
    
    @Published private(set) var items: [SavedLinkItem] = []
    
    var visibleItems: [SavedLinkItem] {
        items.filter { !$0.isDeleted }
    }
    
    // Track active downloads (transient state, not saved)
    @Published var downloadingItems: [UUID: String] = [:]
    
    private let storageKey = "savedLinks"
    private let lastSyncedKey = "savedLinksLastSyncedAt"
    private let maxItems = 500
    
    var lastSyncedAt: Date? {
        get {
            UserDefaults.standard.object(forKey: lastSyncedKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: lastSyncedKey)
        }
    }
    
    private init() {
        loadItems()
    }
    
    // Check if a link exists and is active (not deleted)
    func hasActiveLink(url: String) -> Bool {
        return visibleItems.contains { $0.url == url }
    }

    // Add a new saved link
    func addLink(url: String, downloaderType: String) {
        addLinks(urls: [url], downloaderType: downloaderType)
    }
    
    // Add multiple links at once
    func addLinks(urls: [String], downloaderType: String) {
        var needsSave = false
        
        for url in urls {
            // Find all matching items (active or deleted)
            let matchingIndices = items.indices.filter { items[$0].url == url }
            
            if !matchingIndices.isEmpty {
                // Pick primary (prefer active)
                let winnerIndex = matchingIndices.first(where: { !items[$0].isDeleted }) ?? matchingIndices.first!
                var winner = items[winnerIndex]
                
                // Restore if deleted
                if winner.isDeleted {
                    winner.isDeleted = false
                }
                
                // Update metadata for the winner
                winner.timestamp = Date()
                winner.updatedAt = Date()
                winner.isDirty = true
                
                // Mark all OTHER matches as deleted (soft delete duplicates)
                for index in matchingIndices where index != winnerIndex {
                    if !items[index].isDeleted {
                        items[index].isDeleted = true
                        items[index].updatedAt = Date()
                        items[index].isDirty = true
                        needsSave = true
                    }
                }
                
                // Move to top
                items.remove(at: winnerIndex)
                items.insert(winner, at: 0)
                needsSave = true
                
            } else {
                // New item
                let item = SavedLinkItem(url: url, downloaderType: downloaderType)
                items.insert(item, at: 0)
                needsSave = true
            }
        }
        
        if needsSave {
            items = Array(items.prefix(maxItems))
            saveItems()
        }
    }
    
    // Update status for a specific item
    func updateStatus(for item: SavedLinkItem, newStatus: SavedLinkStatus) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].status = newStatus
            items[index].updatedAt = Date()
            items[index].isDirty = true
            saveItems()
        }
    }
    
    // Soft delete a single saved link
    func deleteItem(_ item: SavedLinkItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index].isDeleted = true
            items[index].updatedAt = Date()
            items[index].isDirty = true
            saveItems()
        }
    }
    
    // Soft delete items at specific indices (from visibleItems)
    func deleteItems(at offsets: IndexSet) {
        let itemsToDelete = offsets.map { visibleItems[$0] }
        for item in itemsToDelete {
            deleteItem(item)
        }
    }
    
    // Soft delete all items
    func clearAll() {
        for index in items.indices {
            if !items[index].isDeleted {
                items[index].isDeleted = true
                items[index].updatedAt = Date()
                items[index].isDirty = true
            }
        }
        saveItems()
    }
    
    // Hard delete items that have been soft-deleted for more than 30 days
    func cleanupStaleDeletedItems() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let countBefore = items.count
        items.removeAll { $0.isDeleted && $0.updatedAt < cutoffDate }
        
        if items.count < countBefore {
            saveItems()
            print("🧹 Cleaned up \(countBefore - items.count) stale saved links")
        }
    }
    
    // Fetch dirty records for sync
    func fetchDirtyRecords() -> [SavedLinkItem] {
        return items.filter { $0.isDirty }
    }
    
    // Mark records as synced
    func markAsSynced(ids: Set<UUID>) {
        for index in items.indices {
            if ids.contains(items[index].id) {
                items[index].isDirty = false
            }
        }
        saveItems()
    }
    
    // Merge remote records
    func merge(remoteRecords: [SavedLinkItem]) {
        var needsSave = false
        
        for remote in remoteRecords {
            if let index = items.firstIndex(where: { $0.id == remote.id }) {
                let local = items[index]
                if remote.updatedAt >= local.updatedAt {
                    var merged = remote
                    merged.isDirty = false
                    items[index] = merged
                    needsSave = true
                }
            } else {
                var newRecord = remote
                newRecord.isDirty = false
                items.append(newRecord)
                needsSave = true
            }
        }
        
        items.sort { $0.timestamp > $1.timestamp }
        
        if needsSave {
            saveItems()
        }
    }
    
    func setDownloading(itemId: UUID, progress: String = "准备中...") {
        downloadingItems[itemId] = progress
    }
    
    func finishDownloading(itemId: UUID) {
        downloadingItems.removeValue(forKey: itemId)
    }
    
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
