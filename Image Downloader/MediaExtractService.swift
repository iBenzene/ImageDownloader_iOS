//
//  MediaExtractService.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/7/1.
//

import Foundation

enum MediaExtractService {
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    static func fetchMediaUrls(
        url: URL,
        downloaderType: ImageDownloaderType,
        serverUrl: String,
        serverToken: String,
        useProxy: Bool,
        requestLogName: String,
        failureLogName: String
    ) async throws -> [Any] {
        guard !serverUrl.isEmpty else {
            throw URLError(.badURL)
        }

        let baseUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/extract"
        let token = serverToken.isEmpty ? "default_token" : serverToken

        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "downloader", value: downloaderType.rawValue),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "useProxy", value: String(useProxy))
        ]

        guard let requestUrl = components?.url else {
            logError("\(requestLogName)请求参数错误: 无法构建 URL")
            throw URLError(.badURL)
        }

        var request = URLRequest(url: requestUrl)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        logInfo("向 \(requestUrl) 发起\(requestLogName)请求")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logError("\(requestLogName)请求响应错误: 响应不是 HTTPURLResponse")
            throw URLError(.badServerResponse)
        }

        if httpResponse.statusCode != 200 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                logError("服务端\(failureLogName)失败, HTTP 状态码: \(httpResponse.statusCode), 错误信息: \(errorMessage)")
                throw NSError(domain: "BackendError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            }

            let responseString = String(data: data, encoding: .utf8) ?? "无法解析响应内容"
            logError("服务端\(failureLogName)失败, HTTP 状态码: \(httpResponse.statusCode), 响应内容: \(responseString)")
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mediaUrls = json["mediaUrls"] else {
            logError("服务端\(requestLogName)响应解析失败: mediaUrls 字段缺失或格式错误")
            throw URLError(.cannotParseResponse)
        }

        if downloaderType == .xhsLiveImg {
            guard let mediaArray = mediaUrls as? [[String: Any?]] else {
                logError("「实况图片下载器」响应解析失败: 预期媒体项应为字典数组")
                throw URLError(.cannotParseResponse)
            }

            return mediaArray.compactMap { item -> (String, String)? in
                guard let cover = item["cover"] as? String else {
                    return nil
                }

                let video = item["video"] as? String ?? ""
                return (cover, video)
            }
        }

        guard let mediaArray = mediaUrls as? [String] else {
            logError("下载器响应解析失败: 预期媒体项应为字符串数组")
            throw URLError(.cannotParseResponse)
        }

        return mediaArray
    }
}
