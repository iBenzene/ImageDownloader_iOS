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
    case pImg = "Pixiv 图片下载器"
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

class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    @AppStorage("serverSideProxy") private var serverSideProxy: Bool = false
    
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    private init() {}
    
    private func pauseBriefly() async {
        // 短暂暂停 1 秒
        try? await Task.sleep(nanoseconds: 1_000_000_000)
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
                    logInfo("[\(currentLine) / \(urls.count)] 使用预热缓存的 \(cachedMediaUrls.count) 个资源链接")
                    mediaUrls = cachedMediaUrls
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
                    if downloaderType == .xhsLiveImg {
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
                                logError("[\(currentLine) / \(urls.count)] 实况图片保存失败（\(index + 1) / \(mediaUrls.count)）")
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
                            return .failure(error: errorMsg)
                        }
                    } else {
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
                            logError("[\(currentLine) / \(urls.count)] 提取的链接无效: \(mediaUrl)（\(index + 1) / \(mediaUrls.count)）")
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
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                throw URLError(.badServerResponse)
                            }
                            
                            switch downloaderType {
                            case .xhsVid: // 小红书视频下载器
                                // 将视频保存至相册
                                let saveResult = await saveVideoToPhotoLibrary(
                                    videoData: data,
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
                                    logError("[\(currentLine) / \(urls.count)] 视频保存失败（\(index + 1) / \(mediaUrls.count)）")
                                    return .failure(error: "视频保存失败")
                                }
                            default: // 图片下载器
                                // 将图片保存至相册
                                let saveResult = await saveImageToPhotoLibrary(
                                    imageData: data,
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
                                    logError("[\(currentLine) / \(urls.count)] 图片保存失败（\(index + 1) / \(mediaUrls.count)）")
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
                logError("[\(currentLine) / \(urls.count)] 下载过程发生错误: \(errorMsg)")
                return .failure(error: errorMsg)
            }
        }
        
        logInfo("下载任务全部完成, 共下载 \(totalMediaDownloaded) 个媒体文件")
        return .success(mediaCount: totalMediaDownloaded)
    }
    
    // 向服务端发起提取图片或视频 URLs 的请求
    private func fetchMediaUrls(url: URL, downloaderType: ImageDownloaderType) async throws -> [Any] {
        guard !serverUrl.isEmpty else {
            throw URLError(.badURL)
        }
        
        // 构建请求 URL
        let baseUrl = serverUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/extract"
        let token = serverToken.isEmpty ? "default_token" : serverToken
        
        // Determine useProxy value
        // Always use proxy for Pixiv, otherwise use user setting
        let useProxy = (downloaderType == .pImg) ? true : serverSideProxy
        
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

        logInfo("向 \(requestUrl) 发起解析请求")

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
                throw NSError(domain: "BackendError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage])
            } else {
                throw URLError(.badServerResponse)
            }
        }
        
        // 解析 JSON 响应
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mediaUrls = json["mediaUrls"] else {
            throw URLError(.cannotParseResponse)
        }
        
        // 根据下载器类型处理不同的数据格式
        if downloaderType == .xhsLiveImg { // 当前「实况图片下载器」只有小红书的这一个
            //「实况图片下载器」返回对象数组, 因为每个「实况图片」包含封面和视频两个部分
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
            // 一般的下载器返回字符串数组
            guard let mediaArray = mediaUrls as? [String] else {
                throw URLError(.cannotParseResponse)
            }
            
            return mediaArray
        }
    }
    
    // 将图片保存至相册
    private func saveImageToPhotoLibrary(
        imageData: Data,
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
            await pauseBriefly()
            return false
        }
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
            await pauseBriefly()
            return false
        }
    }
    
    // 将视频保存至相册
    private func saveVideoToPhotoLibrary(
        videoData: Data,
        currentLine: Int,
        totalLines: Int,
        currentIndex: Int,
        totalCount: Int,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async -> Bool {
        // 将视频数据写入临时文件
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
            await pauseBriefly()
            return false
        }
        
        do {
            defer {
                // 清理临时文件
                do {
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    logDebug("[\(currentLine) / \(totalLines)] 已删除临时视频文件: \(tempVideoUrl)（\(currentIndex) / \(totalCount)）") }
                catch {
                    // Debug
                    logWarn("[\(currentLine) / \(totalLines)] 删除临时视频文件失败: \(error)（\(currentIndex) / \(totalCount)）")
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
            await pauseBriefly()
            return false
        }
    }
    
    // 将实况图片保存至相册
    private func saveLiveImageToPhotoLibrary(
        coverData: Data,
        videoData: Data?,
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
                currentLine: currentLine,
                totalLines: totalLines,
                currentIndex: currentIndex,
                totalCount: totalCount,
                onProgress: onProgress
            )
        }
        
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
            await pauseBriefly()
            return false
        }
        
        do {
            defer {
                do {
                    try FileManager.default.removeItem(at: tempCoverUrl)
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    logDebug("[\(currentLine) / \(totalLines)] 已删除临时文件: \(tempCoverUrl), \(tempVideoUrl)（\(currentIndex) / \(totalCount)）")
                } catch {
                    // Debug
                    logWarn("[\(currentLine) / \(totalLines)] 删除临时文件失败: \(error)（\(currentIndex) / \(totalCount)）")
                }
            }
            
            // 将回调式的闭包转换为 async/await, 并调用 LivePhotoHelper 保存实况图片
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let livePhotoHelper = LivePhotoHelper()
                livePhotoHelper.saveLivePhoto(tempCoverUrl, videoUrl: tempVideoUrl) { success, error in
                    if success {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error ?? NSError(domain: "LivePhoto", code: -1,
                                                               userInfo: [NSLocalizedDescriptionKey: "未知错误"]))
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
            await pauseBriefly()
            return false
        }
    }
}
