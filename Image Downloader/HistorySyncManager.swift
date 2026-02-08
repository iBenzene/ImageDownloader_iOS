//
//  HistorySyncManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/7.
//

import Foundation
import SwiftUI

// API Request/Response Models
struct SyncRequest: Codable {
    let records: [HistoryItemAPI]
}

struct SyncResponse: Codable {
    let records: [HistoryItemAPI]
    let syncedAt: String
}

// API representation of HistoryItem
struct HistoryItemAPI: Codable {
    let id: UUID
    let url: String
    let downloader: String
    let media_count: Int
    let is_success: Bool
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
    let metadata: [String: String]?
    
    // Convert from local Item to API Item
    init(from item: HistoryItem) {
        self.id = item.id
        self.url = item.url
        self.downloader = item.downloaderType
        self.media_count = item.mediaCount
        self.is_success = item.isSuccess
        self.created_at = ISO8601DateFormatter.string(from: item.timestamp, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        self.updated_at = ISO8601DateFormatter.string(from: item.updatedAt, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        self.is_deleted = item.isDeleted
        self.metadata = nil
    }
    
    // Convert from API Item to local Item
    func toLocalItem() -> HistoryItem {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let timestampDate = formatter.date(from: created_at) ?? Date()
        let updatedAtDate = formatter.date(from: updated_at) ?? Date()
        
        if is_deleted {
            logDebug("Parsing Remote History Item: \(id) - URL: \(url.prefix(20))... - is_deleted: \(is_deleted), updated_at: \(updated_at)")
        }
        
        return HistoryItem(
            id: id,
            url: url,
            downloaderType: downloader,
            timestamp: timestampDate,
            isSuccess: is_success,
            mediaCount: media_count,
            updatedAt: updatedAtDate,
            isDeleted: is_deleted,
            isDirty: false
        )
    }
}


class HistorySyncManager: ObservableObject {
    static let shared = HistorySyncManager()
    
    @AppStorage("backendUrl") private var backendUrl: String = ""
    @AppStorage("backendToken") private var backendToken: String = ""
    
    private var isSyncing = false
    
    private init() {}
    
    func sync() async {
        guard !isSyncing else { return }
        guard !backendUrl.isEmpty, !backendToken.isEmpty else {
            logWarn("Sync skipped: Missing backend URL or Token")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        logDebug("Starting History Sync...")
        
        // 1. Prepare Request
        let dirtyItems = HistoryManager.shared.fetchDirtyRecords()
        let apiItems = dirtyItems.map { HistoryItemAPI(from: $0) }
        
        let requestBody = SyncRequest(records: apiItems)
        
        // 2. Build URL
        let baseUrl = backendUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/history/sync"
        
        guard var components = URLComponents(string: endpoint) else {
            logWarn("Sync failed: Invalid URL")
            return
        }
        
        var queryItems = [URLQueryItem(name: "token", value: backendToken)]
        
        let incrementalSync = UserDefaults.standard.bool(forKey: "incrementalSync")
        if incrementalSync, let lastSynced = HistoryManager.shared.lastSyncedAt {
            let encodedDate = ISO8601DateFormatter.string(from: lastSynced, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
            queryItems.append(URLQueryItem(name: "since", value: encodedDate))
        } else if !incrementalSync {
            logDebug("Performing full history sync (Incremental sync disabled)")
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            logWarn("Sync failed: Failed to encode body - \(error.localizedDescription)")
            return
        }
        
        // 3. Execute Request
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                logWarn("Sync failed: Invalid response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String {
                    logWarn("Sync failed: Backend error - \(errorMessage)")
                } else {
                    logWarn("Sync failed: HTTP \(httpResponse.statusCode)")
                }
                return
            }
            
            // 4. Handle Response
            let syncResponse = try JSONDecoder().decode(SyncResponse.self, from: data)
            
            logDebug("Pulled \(syncResponse.records.count) history records from remote. SyncedAt: \(syncResponse.syncedAt)")
            
            // Process Remote Records
            let remoteRecords = syncResponse.records.map { $0.toLocalItem() }
            
            await MainActor.run {
                // Determine which IDs were successfully pushed
                let pushedIds = Set(apiItems.map { $0.id })
                HistoryManager.shared.markAsSynced(ids: pushedIds)
                
                // Merge remote changes
                HistoryManager.shared.merge(remoteRecords: remoteRecords)
                
                // Update Last Synced Time
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let newSyncedAt = formatter.date(from: syncResponse.syncedAt) {
                    HistoryManager.shared.lastSyncedAt = newSyncedAt
                }
            }
            
            if apiItems.count > 0 || remoteRecords.count > 0 {
                logInfo("History Sync Completed. Pushed: \(apiItems.count), Pulled: \(remoteRecords.count)")
            } else {
                logDebug("History Sync Completed. No changes detected.")
            }
            
        } catch {
            logError("Sync failed: \(error.localizedDescription)")
        }
    }
}
