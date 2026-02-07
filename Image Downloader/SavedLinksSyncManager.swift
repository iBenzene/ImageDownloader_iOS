//
//  SavedLinksSyncManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/7.
//

import Foundation
import SwiftUI

// API Request/Response Models
struct SavedLinksSyncRequest: Codable {
    let records: [SavedLinkItemAPI]
}

struct SavedLinksSyncResponse: Codable {
    let records: [SavedLinkItemAPI]
    let syncedAt: String
}

// API representation of SavedLinkItem
struct SavedLinkItemAPI: Codable {
    let id: UUID
    let url: String
    let downloader: String
    let status: String
    let created_at: String
    let updated_at: String
    let is_deleted: Bool
    let metadata: [String: String]?
    
    init(from item: SavedLinkItem) {
        self.id = item.id
        self.url = item.url
        self.downloader = item.downloaderType
        self.status = item.status.rawValue
        self.created_at = ISO8601DateFormatter.string(from: item.timestamp, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        self.updated_at = ISO8601DateFormatter.string(from: item.updatedAt, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
        self.is_deleted = item.isDeleted
        self.metadata = nil
    }
    
    func toLocalItem() -> SavedLinkItem {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let timestampDate = formatter.date(from: created_at) ?? Date()
        let updatedAtDate = formatter.date(from: updated_at) ?? Date()
        let parsedStatus = SavedLinkStatus(rawValue: status) ?? .none
        
        return SavedLinkItem(
            id: id,
            url: url,
            timestamp: timestampDate,
            downloaderType: downloader,
            status: parsedStatus,
            updatedAt: updatedAtDate,
            isDeleted: is_deleted,
            isDirty: false
        )
    }
}

class SavedLinksSyncManager: ObservableObject {
    static let shared = SavedLinksSyncManager()
    
    @AppStorage("backendUrl") private var backendUrl: String = ""
    @AppStorage("backendToken") private var backendToken: String = ""
    
    private var isSyncing = false
    
    private init() {}
    
    func sync() async {
        guard !isSyncing else { return }
        guard !backendUrl.isEmpty, !backendToken.isEmpty else {
            print("⚠️ SavedLinks Sync skipped: Missing backend URL or Token")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        print("🔄 Starting SavedLinks Sync...")
        
        let dirtyItems = SavedLinksManager.shared.fetchDirtyRecords()
        let apiItems = dirtyItems.map { SavedLinkItemAPI(from: $0) }
        
        let requestBody = SavedLinksSyncRequest(records: apiItems)
        
        let baseUrl = backendUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/saved-links/sync"
        
        guard var components = URLComponents(string: endpoint) else {
            print("⚠️ SavedLinks Sync failed: Invalid URL")
            return
        }
        
        var queryItems = [URLQueryItem(name: "token", value: backendToken)]
        
        if let lastSynced = SavedLinksManager.shared.lastSyncedAt {
            let encodedDate = ISO8601DateFormatter.string(from: lastSynced, timeZone: TimeZone(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])
            queryItems.append(URLQueryItem(name: "since", value: encodedDate))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("⚠️ SavedLinks Sync failed: Failed to encode body - \(error.localizedDescription)")
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ SavedLinks Sync failed: Invalid response")
                return
            }
            
            if httpResponse.statusCode != 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorMessage = json["error"] as? String {
                    print("⚠️ SavedLinks Sync failed: Backend error - \(errorMessage)")
                } else {
                    print("⚠️ SavedLinks Sync failed: HTTP \(httpResponse.statusCode)")
                }
                return
            }
            
            let syncResponse = try JSONDecoder().decode(SavedLinksSyncResponse.self, from: data)
            
            let remoteRecords = syncResponse.records.map { $0.toLocalItem() }
            
            await MainActor.run {
                let pushedIds = Set(apiItems.map { $0.id })
                SavedLinksManager.shared.markAsSynced(ids: pushedIds)
                
                SavedLinksManager.shared.merge(remoteRecords: remoteRecords)
                
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let newSyncedAt = formatter.date(from: syncResponse.syncedAt) {
                    SavedLinksManager.shared.lastSyncedAt = newSyncedAt
                }
            }
            
            print("✅ SavedLinks Sync Completed. Pushed: \(apiItems.count), Pulled: \(remoteRecords.count)")
            
        } catch {
            print("⚠️ SavedLinks Sync failed: \(error.localizedDescription)")
        }
    }
}
