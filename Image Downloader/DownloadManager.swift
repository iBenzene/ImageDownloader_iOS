//
//  DownloadManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/7.
//

import Foundation
import SwiftUI
import Photos

// 客户端行为: 读取分享链接 -> 请求服务端解析并提取资源链接 -> 下载资源 -> 保存至相册
// 如果要上线新的下载器, 只需在这里添加新的 case 即可, 区分不同下载器的逻辑都放在了服务端
enum ImageDownloaderType: String, CaseIterable {
    case xhsImg = "小红书图片下载器"
    case xhsLiveImg = "小红书实况图片下载器"
    case xhsVid = "小红书视频下载器"
    case mysImg = "米游社图片下载器"
    case wbImg = "微博图片下载器"
    case bVid = "哔哩哔哩视频下载器"
    case pImg = "Pixiv 插画下载器"
    case pUgoira = "Pixiv 动图下载器"
    case xImg = "Twitter (X) 图片下载器"
    case xVid = "Twitter (X) 视频下载器"
}

// 下载进度
struct DownloadProgress {
    let currentUrlIndex: Int      // 当前处理的 URL 索引 (1 - indexed)
    let totalUrlCount: Int        // URL 总数
    let currentMediaIndex: Int    // 当前下载的媒体索引 (1 - indexed)
    let totalMediaCount: Int      // 媒体总数
    let message: String           // 状态消息
    let isError: Bool
    let isWarning: Bool
}

// 下载结果
enum DownloadResult {
    case success(mediaCount: Int)
    case failure(error: String)
}

struct HomeWorkflowFeedback {
    let message: String?
    let isError: Bool
    let isWarning: Bool
    let isDownloading: Bool
}

struct HomeWorkflowResult {
    let shouldClearInput: Bool
    let feedback: HomeWorkflowFeedback
}

enum HomeSavePreparation {
    case ready([String])
    case needsDuplicateConfirmation([String])
    case feedback(HomeWorkflowFeedback)
}

enum HomeInvalidLineHandling {
    case ignore
    case skipWithWarning
}

private enum HomeUrlExtractionResult {
    case success(urls: [String], warning: HomeWorkflowFeedback?)
    case failure(HomeWorkflowFeedback)
}

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    @AppStorage("serverSideProxy") private var serverSideProxy: Bool = false
    @AppStorage(MacDownloadPreference.storageKey) private var macDownloadDirectoryPath: String = ""
    @AppStorage("macSaveToPhotoLibrary") private var macSaveToPhotoLibrary: Bool = false
    
    private let linkPattern = #"http[s]?://[^\s，]+"#
    private let liveCachePrefix = "__LIVE_CACHE__"
    
    private init() {}
    
    private func pauseBriefly() async {
        // 短暂暂停 1 秒
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func performDownload(
        from input: String,
        downloaderType: ImageDownloaderType,
        invalidLineHandling: HomeInvalidLineHandling,
        onProgress: @escaping (HomeWorkflowFeedback) -> Void
    ) async -> HomeWorkflowResult {
        let extraction = extractUrlStrings(
            from: input,
            noMatchesMessage: "请输入链接",
            invalidLineHandling: invalidLineHandling
        )

        guard case let .success(urlStrings, warning) = extraction else {
            if case let .failure(feedback) = extraction {
                return HomeWorkflowResult(shouldClearInput: false, feedback: feedback)
            }

            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .error("请输入链接")
            )
        }

        if let warning {
            await MainActor.run {
                onProgress(warning)
            }
        }

        let urls = urlStrings.compactMap(URL.init(string:))
        guard !urls.isEmpty else {
            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .error("请输入链接")
            )
        }

        guard !serverUrl.isEmpty else {
            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .error("请在设置中配置服务端地址")
            )
        }

        await MainActor.run {
            onProgress(.downloading(message: nil))
        }

        let result = await downloadMedia(
            urls: urls,
            downloaderType: downloaderType,
            onProgress: { progress in
                Task { @MainActor in
                    onProgress(.from(progress))
                }
            }
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        switch result {
        case .success(let mediaCount):
            return HomeWorkflowResult(
                shouldClearInput: true,
                feedback: .success("下载完成，共保存 \(mediaCount) 个图片或视频")
            )
        case .failure(let error):
            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .error(error)
            )
        }
    }

    func prepareSaveLinks(from input: String) -> HomeSavePreparation {
        let extraction = extractUrlStrings(
            from: input,
            noMatchesMessage: "未找到有效链接",
            invalidLineHandling: .ignore
        )

        switch extraction {
        case .success(let urls, _):
            let duplicates = urls.filter { url in
                SavedLinksManager.shared.hasActiveLink(url: url)
            }

            if duplicates.isEmpty {
                return .ready(urls)
            }

            return .needsDuplicateConfirmation(urls)

        case .failure(let feedback):
            return .feedback(feedback)
        }
    }

    func saveLinks(
        _ urls: [String],
        downloaderType: ImageDownloaderType,
        shouldPreheatResources: Bool,
        onProgress: @escaping (HomeWorkflowFeedback) -> Void
    ) async -> HomeWorkflowResult {
        SavedLinksManager.shared.addLinks(urls: urls, downloaderType: downloaderType.rawValue)

        guard shouldPreheatResources else {
            return HomeWorkflowResult(
                shouldClearInput: true,
                feedback: .success("已保存 \(urls.count) 个链接")
            )
        }

        let validUrls = urls.compactMap(URL.init(string:))
        guard !validUrls.isEmpty else {
            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .warning("已保存 \(urls.count) 个链接，但没有可预热的有效链接")
            )
        }

        await MainActor.run {
            onProgress(.downloading(message: "正在预热资源..."))
        }

        let result = await PreheatManager.shared.preheatResources(
            urls: validUrls,
            downloaderType: downloaderType,
            onProgress: { progress in
                Task { @MainActor in
                    onProgress(.from(progress))
                }
            }
        )

        try? await Task.sleep(nanoseconds: 100_000_000)

        switch result {
        case .success(let cachedUrls):
            for url in urls {
                if let item = SavedLinksManager.shared.visibleItems.first(where: { $0.url == url }) {
                    SavedLinksManager.shared.updateCachedUrls(for: item, cachedUrls: cachedUrls)
                }
            }

            return HomeWorkflowResult(
                shouldClearInput: true,
                feedback: .success("已保存 \(urls.count) 个链接，预热成功（缓存 \(cachedUrls.count) 个资源）")
            )

        case .failure(let error):
            return HomeWorkflowResult(
                shouldClearInput: false,
                feedback: .error(error)
            )
        }
    }

    func hasRecognizedLinks(in input: String) -> Bool {
        if case .success = extractUrlStrings(
            from: input,
            noMatchesMessage: "未找到有效链接",
            invalidLineHandling: .ignore
        ) {
            return true
        }

        return false
    }
    
    // 执行下载操作
    // - Parameters:
    //   - urls: 待下载的 URL 列表
    //   - downloaderType: 下载器类型
    //   - cachedMediaUrls: 已缓存的媒体资源链接, 若存在则优先使用
    //   - onProgress: 进度回调
    // - Returns: 下载结果
    func downloadMedia(
        urls: [URL],
        downloaderType: ImageDownloaderType,
        cachedMediaUrls: [String]? = nil,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> DownloadResult {
        
        if serverUrl.isEmpty {
            // 服务端地址未配置
            logError("下载失败: 服务端地址未配置")
            return .failure(error: "请在设置中配置服务端地址")
        }
        
        logInfo("开始下载 \(urls.count) 个链接 (\(downloaderType.rawValue))")
        
        var totalMediaDownloaded = 0
        
        for (urlIndex, url) in urls.enumerated() {
            let currentLine = urlIndex + 1
            
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: urls.count,
                currentMediaIndex: 0,
                totalMediaCount: 0,
                message: "【\(currentLine) / \(urls.count)】处理中...",
                isError: false,
                isWarning: false
            ))
            
            // 发起网络请求
            do {
                let mediaUrls: [Any]
                
                // 优先使用预热缓存
                if let cachedMediaUrls = cachedMediaUrls, !cachedMediaUrls.isEmpty {
                    if downloaderType == .xhsLiveImg {
                        if let liveCachedUrls = decodeLiveCachedUrls(cachedMediaUrls), !liveCachedUrls.isEmpty {
                            logInfo("[\(currentLine) / \(urls.count)] 使用预热缓存的 \(liveCachedUrls.count) 个实况资源链接")
                            mediaUrls = liveCachedUrls.map { $0 }
                        } else {
                            logWarn("[\(currentLine) / \(urls.count)] 实况预热缓存格式无法解析, 回退实时解析")
                            mediaUrls = try await fetchMediaUrls(url: url, downloaderType: downloaderType)
                        }
                    } else {
                        logInfo("[\(currentLine) / \(urls.count)] 使用预热缓存的 \(cachedMediaUrls.count) 个资源链接")
                        mediaUrls = cachedMediaUrls
                    }
                } else {
                    // 向服务端发起提取图片或视频 URLs 的请求
                    mediaUrls = try await fetchMediaUrls(url: url, downloaderType: downloaderType)
                }
                
                if mediaUrls.isEmpty {
                    onProgress(DownloadProgress(
                        currentUrlIndex: currentLine,
                        totalUrlCount: urls.count,
                        currentMediaIndex: 0,
                        totalMediaCount: 0,
                        message: "【\(currentLine) / \(urls.count)】未提取到图片或视频的链接",
                        isError: true,
                        isWarning: false
                    ))
                    
                    // Record failure to history
                    HistoryManager.shared.addRecord(
                        url: url.absoluteString,
                        downloaderType: downloaderType.rawValue,
                        isSuccess: false,
                        mediaCount: 0
                    )
                    
                    // Debug: 检查提取的媒体链接
                    logError("[\(currentLine) / \(urls.count)] 未提取到图片或视频的链接, 原始 URL: \(url)")
                    return .failure(error: "【\(currentLine) / \(urls.count)】未提取到图片或视频的链接")
                }
                
                // 根据提取的链接, 下载图片或视频, 并保存至相册
                for (index, mediaUrl) in mediaUrls.enumerated() {
                    if downloaderType == .xhsLiveImg { // 实况图片下载器, 图片和视频都得下载
                        guard let mediaUrlTuple = mediaUrl as? (String, String) else {
                            let errorMsg = "【\(currentLine) / \(urls.count)】提取的实况图片链接不是元组类型（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            logError("[\(currentLine) / \(urls.count)] 提取的实况图片链接不是元组类型 (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                        
                        // 提取实况封面的 URL
                        guard let coverUrl = URL(string: mediaUrlTuple.0) else {
                            let errorMsg = "【\(currentLine) / \(urls.count)】提取的实况封面链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            logError("[\(currentLine) / \(urls.count)] 提取的实况封面链接不是合法的 URL (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                        
                        // 提取实况视频的 URL
                        let videoUrl: URL?
                        if mediaUrlTuple.1.isEmpty {
                            videoUrl = nil
                        } else {
                            guard let validVideoUrl = URL(string: mediaUrlTuple.1) else {
                                let errorMsg = "【\(currentLine) / \(urls.count)】提取的实况视频链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                                onProgress(DownloadProgress(
                                    currentUrlIndex: currentLine,
                                    totalUrlCount: urls.count,
                                    currentMediaIndex: index + 1,
                                    totalMediaCount: mediaUrls.count,
                                    message: errorMsg,
                                    isError: true,
                                    isWarning: false
                                ))
                                logError("[\(currentLine) / \(urls.count)] 提取实况视频链接失败: 提取的实况视频链接不是合法的 URL (\(index + 1) / \(mediaUrls.count))")
                                return .failure(error: errorMsg)
                            }
                            videoUrl = validVideoUrl
                        }
                        
                        do {
                            // 请求下载资源
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: "【\(currentLine) / \(urls.count)】下载中...（\(index + 1) / \(mediaUrls.count)）",
                                isError: false,
                                isWarning: false
                            ))
                            
                            // 下载实况封面
                            let (coverData, coverResponse) = try await URLSession.shared.data(from: coverUrl)
                            guard let coverHttpResponse = coverResponse as? HTTPURLResponse, coverHttpResponse.statusCode == 200 else {
                                throw URLError(.badServerResponse)
                            }
                            
                            // 下载实况视频
                            var videoData: Data? = nil
                            if let videoUrl = videoUrl {
                                let (data, videoResponse) = try await URLSession.shared.data(from: videoUrl)
                                guard let videoHttpResponse = videoResponse as? HTTPURLResponse, videoHttpResponse.statusCode == 200 else {
                                    throw URLError(.badServerResponse)
                                }
                                videoData = data
                            }
                            
                            // 将实况图片保存至相册
                            let saveResult = await saveLiveImageToPhotoLibrary(
                                coverData: coverData,
                                videoData: videoData,
                                coverFileExtension: coverUrl.pathExtension,
                                videoFileExtension: videoUrl?.pathExtension,
                                currentLine: currentLine,
                                totalLines: urls.count,
                                currentIndex: index + 1,
                                totalCount: mediaUrls.count,
                                onProgress: onProgress
                            )
                            
                            if !saveResult {
                                // Record failure to history
                                HistoryManager.shared.addRecord(
                                    url: url.absoluteString,
                                    downloaderType: downloaderType.rawValue,
                                    isSuccess: false,
                                    mediaCount: index
                                )
                                logError("[\(currentLine) / \(urls.count)] 实况图片保存失败 (\(index + 1) / \(mediaUrls.count))")
                                return .failure(error: "实况图片保存失败")
                            }
                        } catch {
                            let errorMsg = "【\(currentLine) / \(urls.count)】实况图片下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            
                            // Record failure to history
                            HistoryManager.shared.addRecord(
                                url: url.absoluteString,
                                downloaderType: downloaderType.rawValue,
                                isSuccess: false,
                                mediaCount: index
                            )
                            logError("[\(currentLine) / \(urls.count)] 实况图片下载失败: \(error) (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                    } else { // 只需下载单一资源
                        // 将 Unicode 编码 \u002F 替换为 /
                        guard let mediaUrlString = mediaUrl as? String else {
                            let errorMsg = "【\(currentLine) / \(urls.count)】提取的资源链接不是字符串类型（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            logError("[\(currentLine) / \(urls.count)] 提取的资源链接不是字符串类型 (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                        let decodedMediaUrlString = mediaUrlString.replacingOccurrences(of: "\\u002F", with: "/")
                        
                        guard let decodedMediaUrl = URL(string: decodedMediaUrlString) else {
                            let errorMsg = "【\(currentLine) / \(urls.count)】提取的资源链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            
                            // Debug: 检查提取的链接
                            logError("[\(currentLine) / \(urls.count)] 提取的链接无效: \(mediaUrl) (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                        
                        do {
                            // 请求下载资源
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: "【\(currentLine) / \(urls.count)】下载中...（\(index + 1) / \(mediaUrls.count)）",
                                isError: false,
                                isWarning: false
                            ))
                            
                            let (data, response) = try await URLSession.shared.data(from: decodedMediaUrl)
                            
                            // 检查有没有发生错误
                            guard let httpResponse = response as? HTTPURLResponse else {
                                logError("[\(currentLine) / \(urls.count)] 下载响应错误: 响应不是 HTTPURLResponse (URL: \(decodedMediaUrl))")
                                throw URLError(.badServerResponse)
                            }
                            
                            if httpResponse.statusCode != 200 {
                                logError("[\(currentLine) / \(urls.count)] 资源下载失败, HTTP 状态码: \(httpResponse.statusCode), URL: \(decodedMediaUrl)")
                                throw URLError(.badServerResponse)
                            }
                            
                            
                            if downloaderType == .xhsVid || downloaderType == .bVid || downloaderType == .xVid || downloaderType == .pUgoira { // 视频下载器
                                // 将视频保存至相册
                                // 将视频保存至相册
                                let saveResult = await saveVideoToPhotoLibrary(
                                    videoData: data,
                                    preferredFileExtension: decodedMediaUrl.pathExtension,
                                    currentLine: currentLine,
                                    totalLines: urls.count,
                                    currentIndex: index + 1,
                                    totalCount: mediaUrls.count,
                                    onProgress: onProgress
                                )
                                if !saveResult {
                                    HistoryManager.shared.addRecord(
                                        url: url.absoluteString,
                                        downloaderType: downloaderType.rawValue,
                                        isSuccess: false,
                                        mediaCount: index
                                    )
                                    logError("[\(currentLine) / \(urls.count)] 视频保存失败 (\(index + 1) / \(mediaUrls.count))")
                                    return .failure(error: "视频保存失败")
                                }
                            } else { // 图片下载器
                                // 将图片保存至相册
                                let saveResult = await saveImageToPhotoLibrary(
                                    imageData: data,
                                    preferredFileExtension: decodedMediaUrl.pathExtension,
                                    currentLine: currentLine,
                                    totalLines: urls.count,
                                    currentIndex: index + 1,
                                    totalCount: mediaUrls.count,
                                    onProgress: onProgress
                                )
                                if !saveResult {
                                    HistoryManager.shared.addRecord(
                                        url: url.absoluteString,
                                        downloaderType: downloaderType.rawValue,
                                        isSuccess: false,
                                        mediaCount: index
                                    )
                                    logError("[\(currentLine) / \(urls.count)] 图片保存失败 (\(index + 1) / \(mediaUrls.count))")
                                    return .failure(error: "图片保存失败")
                                }
                            }
                        } catch {
                            let errorMsg = "【\(currentLine) / \(urls.count)】图片或视频下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                            onProgress(DownloadProgress(
                                currentUrlIndex: currentLine,
                                totalUrlCount: urls.count,
                                currentMediaIndex: index + 1,
                                totalMediaCount: mediaUrls.count,
                                message: errorMsg,
                                isError: true,
                                isWarning: false
                            ))
                            
                            // Record failure to history
                            HistoryManager.shared.addRecord(
                                url: url.absoluteString,
                                downloaderType: downloaderType.rawValue,
                                isSuccess: false,
                                mediaCount: index
                            )
                            logError("[\(currentLine) / \(urls.count)] 图片或视频下载失败: \(error) (\(index + 1) / \(mediaUrls.count))")
                            return .failure(error: errorMsg)
                        }
                    }
                }
                
                totalMediaDownloaded += mediaUrls.count
                
                // Record success to history after all media items are downloaded
                HistoryManager.shared.addRecord(
                    url: url.absoluteString,
                    downloaderType: downloaderType.rawValue,
                    isSuccess: true,
                    mediaCount: mediaUrls.count
                )
                
            } catch {
                let errorMsg = "【\(currentLine) / \(urls.count)】" + (error.localizedDescription.isEmpty ? "未知错误" : error.localizedDescription)
                onProgress(DownloadProgress(
                    currentUrlIndex: currentLine,
                    totalUrlCount: urls.count,
                    currentMediaIndex: 0,
                    totalMediaCount: 0,
                    message: errorMsg,
                    isError: true,
                    isWarning: false
                ))
                
                // Record failure to history
                HistoryManager.shared.addRecord(
                    url: url.absoluteString,
                    downloaderType: downloaderType.rawValue,
                    isSuccess: false,
                    mediaCount: 0
                )
                logError("[\(currentLine) / \(urls.count)] 下载过程发生错误: \(error)")
                return .failure(error: errorMsg)
            }
        }
        
        logInfo("下载任务全部完成, 共下载 \(totalMediaDownloaded) 个媒体文件")
        return .success(mediaCount: totalMediaDownloaded)
    }

    private func extractUrlStrings(
        from input: String,
        noMatchesMessage: String,
        invalidLineHandling: HomeInvalidLineHandling
    ) -> HomeUrlExtractionResult {
        guard !input.isEmpty else {
            return .failure(.error("请输入链接"))
        }

        var urls: [String] = []
        var warning: HomeWorkflowFeedback?

        for (index, text) in input.components(separatedBy: "\n").enumerated() {
            guard !text.isEmpty else { continue }

            if let match = text.range(of: linkPattern, options: .regularExpression) {
                urls.append(String(text[match]))
            } else {
                switch invalidLineHandling {
                case .ignore:
                    continue
                case .skipWithWarning:
                    warning = .warning("第 \(index + 1) 行不包含链接，跳过")
                }
            }
        }

        guard !urls.isEmpty else {
            return .failure(.error(noMatchesMessage))
        }

        return .success(urls: urls, warning: warning)
    }
    
    // 向服务端发起提取图片或视频 URLs 的请求
    private func fetchMediaUrls(url: URL, downloaderType: ImageDownloaderType) async throws -> [Any] {
        // Always use proxy for Pixiv and bilibili, otherwise use user setting
        let useProxy = (downloaderType == .pImg || downloaderType == .pUgoira || downloaderType == .bVid) ? true : serverSideProxy

        return try await MediaExtractService.fetchMediaUrls(
            url: url,
            downloaderType: downloaderType,
            serverUrl: serverUrl,
            serverToken: serverToken,
            useProxy: useProxy,
            requestLogName: "解析",
            failureLogName: "提取媒体链接"
        )
    }
    
    // 将图片保存至相册
    private func saveImageToPhotoLibrary(
        imageData: Data,
        preferredFileExtension: String? = nil,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        guard let image = UIImage(data: imageData) else {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】图片数据无效（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 图片数据无效 (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }

        #if targetEnvironment(macCatalyst)
        if macSaveToPhotoLibrary {
            return await saveImageToSystemPhotoLibrary(
                image: image,
                currentLine: currentLine,
                totalLines: totalLines,
                currentIndex: currentIndex,
                totalCount: totalCount,
                onProgress: onProgress
            )
        }

        do {
            let savedUrl = try saveDownloadedFileToDownloads(
                data: imageData,
                preferredFileExtension: preferredFileExtension,
                fallbackFileExtension: "jpg",
                prefix: "image"
            )
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】图片已保存到下载文件夹：\(savedUrl.lastPathComponent)（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 图片保存到下载文件夹失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
        #else
        return await saveImageToSystemPhotoLibrary(
            image: image,
            currentLine: currentLine,
            totalLines: totalLines,
            currentIndex: currentIndex,
            totalCount: totalCount,
            onProgress: onProgress
        )
        #endif
    }
    
    // 将视频保存至相册
    private func saveVideoToPhotoLibrary(
        videoData: Data,
        preferredFileExtension: String? = nil,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        #if targetEnvironment(macCatalyst)
        if macSaveToPhotoLibrary {
            return await saveVideoToSystemPhotoLibrary(
                videoData: videoData,
                currentLine: currentLine,
                totalLines: totalLines,
                currentIndex: currentIndex,
                totalCount: totalCount,
                onProgress: onProgress
            )
        }

        do {
            let savedUrl = try saveDownloadedFileToDownloads(
                data: videoData,
                preferredFileExtension: preferredFileExtension,
                fallbackFileExtension: "mp4",
                prefix: "video"
            )
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】视频已保存到下载文件夹：\(savedUrl.lastPathComponent)（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】视频保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 视频保存到下载文件夹失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
        #else
        return await saveVideoToSystemPhotoLibrary(
            videoData: videoData,
            currentLine: currentLine,
            totalLines: totalLines,
            currentIndex: currentIndex,
            totalCount: totalCount,
            onProgress: onProgress
        )
        #endif
    }
    
    // 将实况图片保存至相册
    private func saveLiveImageToPhotoLibrary(
        coverData: Data,
        videoData: Data?,
        coverFileExtension: String? = nil,
        videoFileExtension: String? = nil,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        guard let videoData = videoData else {
            // 如果没有视频数据, 则当作普通图片保存
            return await saveImageToPhotoLibrary(
                imageData: coverData,
                preferredFileExtension: coverFileExtension,
                currentLine: currentLine,
                totalLines: totalLines,
                currentIndex: currentIndex,
                totalCount: totalCount,
                onProgress: onProgress
            )
        }

        #if targetEnvironment(macCatalyst)
        if macSaveToPhotoLibrary {
            return await saveLiveImageToSystemPhotoLibrary(
                coverData: coverData,
                videoData: videoData,
                currentLine: currentLine,
                totalLines: totalLines,
                currentIndex: currentIndex,
                totalCount: totalCount,
                onProgress: onProgress
            )
        }

        do {
            let coverUrl = try saveDownloadedFileToDownloads(
                data: coverData,
                preferredFileExtension: coverFileExtension,
                fallbackFileExtension: "jpg",
                prefix: "live-cover"
            )
            let videoUrl = try saveDownloadedFileToDownloads(
                data: videoData,
                preferredFileExtension: videoFileExtension,
                fallbackFileExtension: "mp4",
                prefix: "live-video"
            )
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】实况图片已保存到下载文件夹：\(coverUrl.lastPathComponent)、\(videoUrl.lastPathComponent)（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】实况图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 实况图片保存到下载文件夹失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
        #else
        return await saveLiveImageToSystemPhotoLibrary(
            coverData: coverData,
            videoData: videoData,
            currentLine: currentLine,
            totalLines: totalLines,
            currentIndex: currentIndex,
            totalCount: totalCount,
            onProgress: onProgress
        )
        #endif
    }

    private func saveImageToSystemPhotoLibrary(
        image: UIImage,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】图片保存成功（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 图片保存失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
    }

    private func saveVideoToSystemPhotoLibrary(
        videoData: Data,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】写入临时视频文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 写入临时视频文件失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }

        do {
            defer {
                do {
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    logDebug("[\(currentLine) / \(totalLines)] 已删除临时视频文件: \(tempVideoUrl) (\(currentIndex) / \(totalCount))")
                } catch {
                    logWarn("[\(currentLine) / \(totalLines)] 删除临时视频文件失败: \(error) (\(currentIndex) / \(totalCount))")
                }
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempVideoUrl)
            }
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】视频保存成功（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】视频保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 视频保存失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
    }

    private func saveLiveImageToSystemPhotoLibrary(
        coverData: Data,
        videoData: Data,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        let tempCoverUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempCover.jpg")
        do {
            try coverData.write(to: tempCoverUrl)
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】写入临时封面文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 写入临时封面文件失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }

        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】写入临时视频文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 写入临时视频文件失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }

        do {
            defer {
                do {
                    try FileManager.default.removeItem(at: tempCoverUrl)
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    logDebug("[\(currentLine) / \(totalLines)] 已删除临时文件: \(tempCoverUrl), \(tempVideoUrl) (\(currentIndex) / \(totalCount))")
                } catch {
                    logWarn("[\(currentLine) / \(totalLines)] 删除临时文件失败: \(error) (\(currentIndex) / \(totalCount))")
                }
            }

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let livePhotoHelper = LivePhotoHelper()
                livePhotoHelper.saveLivePhoto(tempCoverUrl, videoUrl: tempVideoUrl) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? NSError(
                            domain: "LivePhoto",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "未知错误"]
                        ))
                    }
                }
            }

            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】实况图片保存成功（\(currentIndex) / \(totalCount)）",
                isError: false,
                isWarning: false
            ))
            return true
        } catch {
            onProgress(DownloadProgress(
                currentUrlIndex: currentLine,
                totalUrlCount: totalLines,
                currentMediaIndex: currentIndex,
                totalMediaCount: totalCount,
                message: "【\(currentLine) / \(totalLines)】实况图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）",
                isError: true,
                isWarning: false
            ))
            logError("[\(currentLine) / \(totalLines)] 实况图片保存失败: \(error) (\(currentIndex) / \(totalCount))")
            await pauseBriefly()
            return false
        }
    }

    #if targetEnvironment(macCatalyst)
    private func saveDownloadedFileToDownloads(
        data: Data,
        preferredFileExtension: String?,
        fallbackFileExtension: String,
        prefix: String
    ) throws -> URL {
        let fileExtension = normalizedFileExtension(
            preferredFileExtension,
            fallback: fallbackFileExtension
        )
        let downloadsUrl = MacDownloadPreference.resolvedDirectoryUrl(
            preferredPath: macDownloadDirectoryPath
        )
        let fileName = "ImageDownloader-\(prefix)-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).\(fileExtension)"
        let destinationUrl = downloadsUrl.appendingPathComponent(fileName)

        try data.write(to: destinationUrl, options: .atomic)
        logInfo("已保存文件到下载文件夹: \(destinationUrl.path)")
        return destinationUrl
    }

    private func normalizedFileExtension(_ preferredFileExtension: String?, fallback: String) -> String {
        let candidate = (preferredFileExtension ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let allowedCharacters = CharacterSet.alphanumerics
        let sanitized = String(candidate.unicodeScalars.filter { allowedCharacters.contains($0) })

        return sanitized.isEmpty ? fallback : sanitized
    }
    #endif
    
    private func decodeLiveCachedUrls(_ cachedUrls: [String]) -> [(String, String)]? {
        var decodedUrls: [(String, String)] = []
        
        for cachedUrl in cachedUrls {
            guard cachedUrl.hasPrefix(liveCachePrefix) else {
                return nil
            }
            
            let jsonString = String(cachedUrl.dropFirst(liveCachePrefix.count))
            guard let data = jsonString.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cover = payload["cover"] as? String else {
                return nil
            }
            
            let video = payload["video"] as? String ?? ""
            decodedUrls.append((
                cover.replacingOccurrences(of: "\\u002F", with: "/"),
                video.replacingOccurrences(of: "\\u002F", with: "/")
            ))
        }
        
        return decodedUrls
    }
}

private extension HomeWorkflowFeedback {
    static func success(_ message: String) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: message,
            isError: false,
            isWarning: false,
            isDownloading: false
        )
    }

    static func warning(_ message: String) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: message,
            isError: false,
            isWarning: true,
            isDownloading: false
        )
    }

    static func error(_ message: String) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: message,
            isError: true,
            isWarning: false,
            isDownloading: false
        )
    }

    static func downloading(message: String?) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: message,
            isError: false,
            isWarning: false,
            isDownloading: true
        )
    }

    static func from(_ progress: DownloadProgress) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: progress.message,
            isError: progress.isError,
            isWarning: progress.isWarning,
            isDownloading: !progress.isError
        )
    }

    static func from(_ progress: PreheatProgress) -> HomeWorkflowFeedback {
        HomeWorkflowFeedback(
            message: progress.message,
            isError: progress.isError,
            isWarning: false,
            isDownloading: !progress.isError
        )
    }
}
