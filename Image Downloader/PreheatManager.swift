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
    case success(cachedUrls: [String])
    case failure(error: String)
}

class PreheatManager: ObservableObject {
    static let shared = PreheatManager()
    
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
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
        
        var allCachedUrls: [String] = []
        
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
                
                // Collect cached URLs
                for mediaUrl in mediaUrls {
                    if downloaderType == .xhsLiveImg {
                        guard let tuple = mediaUrl as? (String, String) else { continue }
                        allCachedUrls.append(encodeLiveCachedUrl(cover: tuple.0, video: tuple.1))
                    } else if let urlString = mediaUrl as? String {
                        allCachedUrls.append(urlString.replacingOccurrences(of: "\\u002F", with: "/"))
                    }
                }
                
                onProgress(PreheatProgress(
                    currentUrlIndex: currentLine,
                    totalUrlCount: urls.count,
                    message: "【\(currentLine) / \(urls.count)】预热成功",
                    isError: false
                ))
                
            } catch {
                let errorMsg = "【\(currentLine) / \(urls.count) " + (error.localizedDescription.isEmpty ? "未知错误" : error.localizedDescription)
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
        
        logInfo("预热任务全部完成, 共缓存 \(allCachedUrls.count) 个资源链接")
        return .success(cachedUrls: allCachedUrls)
    }
    
    // 向服务端发起提取资源 URLs 的请求 (强制 useProxy = true)
    private func fetchMediaUrls(url: URL, downloaderType: ImageDownloaderType) async throws -> [Any] {
        guard !serverUrl.isEmpty else {
            throw URLError(.badURL)
        }
        
        // 构建请求 URL
        let baseUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/extract"
        let token = serverToken.isEmpty ? "default_token" : serverToken
        
        // 预热时始终使用代理, 使资源被缓存到 S3
        let useProxy = true
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "downloader", value: downloaderType.rawValue),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "useProxy", value: String(useProxy))
        ]
        
        guard let requestUrl = components?.url else {
            throw URLError(.badURL)
        }
        
        // 创建网络请求
        var request = URLRequest(url: requestUrl)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        logInfo("向 \(requestUrl) 发起预热请求")

        // 发起请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查响应状态
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            // 尝试解析错误信息
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                logError("服务端预热请求失败, HTTP 状态码: \(httpResponse.statusCode), 错误信息: \(errorMessage)")
                throw NSError(domain: "BackendError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            } else {
                let responseString = String(data: data, encoding: .utf8) ?? "无法解析响应内容"
                logError("服务端预热请求失败, HTTP 状态码: \(httpResponse.statusCode), 响应内容: \(responseString)")
                throw URLError(.badServerResponse)
            }
        }
        
        // 解析 JSON 响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mediaUrls = json["mediaUrls"] else {
            throw URLError(.cannotParseResponse)
        }
        
        // 根据下载器类型处理不同的数据格式
        if downloaderType == .xhsLiveImg {
            guard let mediaArray = mediaUrls as? [[String: Any?]] else {
                throw URLError(.cannotParseResponse)
            }
            
            return mediaArray.compactMap { item -> (String, String)? in
                guard let cover = item["cover"] as? String else {
                    return nil
                }
                let video = item["video"] as? String ?? ""
                return (cover, video)
            }
        } else {
            guard let mediaArray = mediaUrls as? [String] else {
                throw URLError(.cannotParseResponse)
            }
            
            return mediaArray
        }
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
