//
//  MacDownloadPreference.swift
//  Image Downloader
//
//  Created by Codex on 2026/7/1.
//

import Foundation

enum MacDownloadPreference {
    static let storageKey = "macDownloadDirectoryPath"

    static var defaultDirectoryUrl: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var defaultDirectoryPath: String {
        defaultDirectoryUrl.path
    }

    static func resolvedDirectoryUrl(preferredPath: String) -> URL {
        let trimmedPath = preferredPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            return defaultDirectoryUrl
        }

        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return defaultDirectoryUrl
        }

        return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
    }
}
