//
//  PreheatManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/13.
//

import Foundation
import SwiftUI

// 预热进度
struct PreheatProgress {
    let currentUrlIndex: Int    // 当前处理的 URL 索引 (1 - indexed)
    let totalUrlCount: Int      // URL 总数
    let message: String         // 状态消息
    let isError: Bool
}

// 预热结果
enum PreheatResult {
    case success(cachedUrlsBySourceUrl: [String: [String]], cachedUrlCount: Int)
    case failure(error: String)
}

class PreheatManager: ObservableObject {
    static let shared = PreheatManager()
    
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    
    private let liveCachePrefix = "__LIVE_CACHE__"
    
    private init() {}
    
    // 执行资源预热
    // - Parameters:
    //   - urls: 待预热的 URL 列表
    //   - downloaderType: 下载器类型
    //   - onProgress: 进度回调
    // - Returns: 预热结果
    func preheatResources(
        urls: [URL],
        downloaderType: ImageDownloaderType,
        onProgress: @escaping (PreheatProgress) -> Void
    ) async -> PreheatResult {
        
        if serverUrl.isEmpty {
            logError("预热失败: 服务端地址未配置")
            return .failure(error: "请在设置中配置服务端地址")
        }
        
        logInfo("开始预热 \(urls.count) 个链接 (\(downloaderType.rawValue))")
        
        var cachedUrlsBySourceUrl: [String: [String]] = [:]
        var totalCachedUrlCount = 0
        
        for (urlIndex, url) in urls.enumerated() {
            let currentLine = urlIndex + 1
            
            onProgress(PreheatProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: urls.count,
                message: "【\(currentLine) / \(urls.count)】预热中...",
                isError: false
            ))
            
            do {
                let mediaUrls = try await fetchMediaUrls(url: url, downloaderType: downloaderType)
                
                if mediaUrls.isEmpty {
                    onProgress(PreheatProgress(
                        currentUrlIndex: currentLine,
                        totalUrlCount: urls.count,
                        message: "【\(currentLine) / \(urls.count)】未提取到图片或视频的链接",
                        isError: true
                    ))
                    logError("[\(currentLine) / \(urls.count)] 未提取到图片或视频的链接, 原始 URL: \(url)")
                    return .failure(error: "【\(currentLine) / \(urls.count)】未提取到图片或视频的链接")
                }
                
                var cachedUrls: [String] = []

                // Collect cached URLs for this source URL.
                for mediaUrl in mediaUrls {
                    if downloaderType == .xhsLiveImg {
                        guard let tuple = mediaUrl as? (String, String) else { continue }
                        cachedUrls.append(encodeLiveCachedUrl(cover: tuple.0, video: tuple.1))
                    } else if let urlString = mediaUrl as? String {
                        cachedUrls.append(urlString.replacingOccurrences(of: "\\u002F", with: "/"))
                    }
                }

                cachedUrlsBySourceUrl[url.absoluteString] = cachedUrls
                totalCachedUrlCount += cachedUrls.count
                
                onProgress(PreheatProgress(
                    currentUrlIndex: currentLine,
                    totalUrlCount: urls.count,
                    message: "【\(currentLine) / \(urls.count)】预热成功",
                    isError: false
                ))
                
            } catch {
                let errorMsg = "【\(currentLine) / \(urls.count)】" + (error.localizedDescription.isEmpty ? "未知错误" : error.localizedDescription)
                onProgress(PreheatProgress(
                    currentUrlIndex: currentLine,
                    totalUrlCount: urls.count,
                    message: errorMsg,
                    isError: true
                ))
                logError("[\(currentLine) / \(urls.count)] 预热过程发生错误: \(error)")
                return .failure(error: errorMsg)
            }
        }
        
        logInfo("预热任务全部完成, 共缓存 \(totalCachedUrlCount) 个资源链接")
        return .success(cachedUrlsBySourceUrl: cachedUrlsBySourceUrl, cachedUrlCount: totalCachedUrlCount)
    }
    
    // 向服务端发起提取资源 URLs 的请求 (强制 useProxy = true)
    private func fetchMediaUrls(url: URL, downloaderType: ImageDownloaderType) async throws -> [Any] {
        try await MediaExtractService.fetchMediaUrls(
            url: url,
            downloaderType: downloaderType,
            serverUrl: serverUrl,
            serverToken: serverToken,
            useProxy: true,
            requestLogName: "预热",
            failureLogName: "预热请求"
        )
    }

    private func encodeLiveCachedUrl(cover: String, video: String) -> String {
        let payload: [String: String] = [
            "cover": cover.replacingOccurrences(of: "\\u002F", with: "/"),
            "video": video.replacingOccurrences(of: "\\u002F", with: "/")
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            return liveCachePrefix + "{\"cover\":\"\(cover)\",\"video\":\"\(video)\"}"
        }
        
        return liveCachePrefix + jsonString
    }
}
