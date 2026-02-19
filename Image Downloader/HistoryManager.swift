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
    
    // Sync Metadata
    var updatedAt: Date          // Last modification timestamp
    var isDeleted: Bool          // Soft delete flag
    var isDirty: Bool            // Local flag: needs sync
    
    init(url: String, downloaderType: String, isSuccess: Bool, mediaCount: Int = 1) {
        self.id = UUID()
        self.url = url
        self.downloaderType = downloaderType
        self.timestamp = Date()
        self.isSuccess = isSuccess
        self.mediaCount = mediaCount
        
        self.updatedAt = Date()
        self.isDeleted = false
        self.isDirty = true
    }
    
    // Internal init for merging/syncing
    init(id: UUID, url: String, downloaderType: String, timestamp: Date, isSuccess: Bool, mediaCount: Int, updatedAt: Date, isDeleted: Bool, isDirty: Bool) {
        self.id = id
        self.url = url
        self.downloaderType = downloaderType
        self.timestamp = timestamp
        self.isSuccess = isSuccess
        self.mediaCount = mediaCount
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.isDirty = isDirty
    }
    
    // Custom decoding for migration
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        downloaderType = try container.decode(String.self, forKey: .downloaderType)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isSuccess = try container.decode(Bool.self, forKey: .isSuccess)
        mediaCount = try container.decode(Int.self, forKey: .mediaCount)
        
        // Migration: New fields
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? timestamp
        isDeleted = try container.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        isDirty = try container.decodeIfPresent(Bool.self, forKey: .isDirty) ?? true
    }
}

// History Manager
class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    
    @Published private(set) var items: [HistoryItem] = []
    
    // Public accesor for UI to see only non-deleted items
    var visibleItems: [HistoryItem] {
        items.filter { !$0.isDeleted }
    }
    
    private let storageKey = "downloadHistory"
    private let lastSyncedKey = "historyLastSyncedAt"
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
        items = Array(items.prefix(maxItems))
        
        saveItems()
    }
    
    // Soft delete a single history item
    func deleteItem(_ item: HistoryItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updatedItem = items[index]
            updatedItem.isDeleted = true
            updatedItem.updatedAt = Date()
            updatedItem.isDirty = true
            items[index] = updatedItem
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
    
    // Clear all history (Soft delete all)
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
            logInfo("Cleaned up \(countBefore - items.count) stale history records")
        }
    }
    
    // Hard delete (for internal cleanup if needed)
    func hardDelete(id: UUID) {
        items.removeAll { $0.id == id }
        saveItems()
    }
    
    // Fetch dirty records for sync
    func fetchDirtyRecords() -> [HistoryItem] {
        return items.filter { $0.isDirty }
    }
    
    // Mark records as synced (not dirty)
    func markAsSynced(ids: Set<UUID>) {
        for index in items.indices {
            if ids.contains(items[index].id) {
                items[index].isDirty = false
            }
        }
        saveItems()
    }
    
    // Merge remote records
    func merge(remoteRecords: [HistoryItem]) {
        var needsSave = false
        
        for remote in remoteRecords {
            if let index = items.firstIndex(where: { $0.id == remote.id }) {
                // Conflict resolution: Remote wins if newer (or backend logic implies remote is truth)
                let local = items[index]
                if remote.updatedAt >= local.updatedAt {
                    logDebug("History Merge [Update]: \(remote.id) - Local isDeleted: \(local.isDeleted) -> Remote isDeleted: \(remote.isDeleted) (Remote updatedAt: \(remote.updatedAt) >= Local: \(local.updatedAt))")
                    var merged = remote
                    merged.isDirty = false
                    items[index] = merged
                    needsSave = true
                } else {
                    logDebug("History Merge [Skip]: \(remote.id) - Remote updatedAt: \(remote.updatedAt) < Local: \(local.updatedAt)")
                }
            } else {
                // Insert new record
                logDebug("History Merge [New]: \(remote.id) - isDeleted: \(remote.isDeleted)")
                var newRecord = remote
                newRecord.isDirty = false
                items.append(newRecord)
                needsSave = true
            }
        }
        
        // Re-sort by timestamp descending
        items.sort { $0.timestamp > $1.timestamp }
        
        if needsSave {
            saveItems()
        }
    }
    
    private func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            items = []
            return
        }
        
        do {
            items = try JSONDecoder().decode([HistoryItem].self, from: data)
        } catch {
            logError("Failed to load history: \(error.localizedDescription)")
            items = []
        }
    }
    
    private func saveItems() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            logError("Failed to save history: \(error.localizedDescription)")
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
        case "哔哩哔哩视频下载器":
            return "哔哩哔哩"
        case "Pixiv 插画下载器":
            return "Pixiv 插画"
        case "Pixiv 动图下载器":
            return "Pixiv 动图"
        case "Twitter (X) 图片下载器":
            return "Twitter (X) 图片"
        case "Twitter (X) 视频下载器":
            return "Twitter (X) 视频"
        default:
            return downloaderType
        }
    }
}
