//
//  ContentView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2023/12/26.
//  Copyright (c) 2023 iBenzene. All rights reserved.
//

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

struct ContentView: View {
    @State private var linkInput: String = ""
    @State private var feedbackMessage: String?
    
    @State private var isError: Bool = false
    @State private var isWarning: Bool = false
    @State private var isDownloading: Bool = false
    @State private var showingLivePhotoConverter = false
    @State private var showingSettings = false
    @State private var selectedDownloader: ImageDownloaderType = .xhsImg
    
    @AppStorage("backendUrl") private var backendUrl: String = ""
    @AppStorage("backendToken") private var backendToken: String = ""
    
    private let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    
    var body: some View {
        NavigationView {
            VStack {
                // 顶部栏
                HStack {
                    // 占位的空按钮
                    Button(action: {}) {
                        Image(systemName: "photo")
                            .resizable()
                            .frame(width: 25, height: 25)
                            .opacity(0) // 完全透明, 即隐藏
                    }
                    .padding()
                    
                    Spacer()
                    
                    HStack {
                        Image("logo")
                            .resizable()
                            .frame(width: 50, height: 50)
                        
                        Text("苯苯存图")
                            .font(.largeTitle)
                            .foregroundColor(Color("AccentColor"))
                            .bold()
                    }
                    
                    Spacer()
                    
                    // 下拉菜单
                    Menu {
                        Picker("下载器类型", selection: $selectedDownloader) {
                            ForEach(ImageDownloaderType.allCases, id: \.self) { downloaderType in
                                Text(downloaderType.rawValue)
                            }
                        }
                        
                        Divider()
                        
                        Button {
                            showingLivePhotoConverter = true
                        } label: {
                            Label("实况图片转换器", systemImage: "livephoto")
                        }
                        
                        Button {
                            showingSettings = true
                        } label: {
                            Label("设置", systemImage: "gear")
                        }
                        
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .resizable()
                            .frame(width: 25, height: 25)
                            .foregroundColor(Color("AccentColor"))
                    }
                    .padding()
                }
                .padding([.top, .bottom])
                .navigationTitle("首页").navigationBarTitleDisplayMode(.inline)
                
                // 用于跳转到「实况图片转换器」页面
                NavigationLink(
                    destination: LivePhotoConverterView(),
                    isActive: $showingLivePhotoConverter,
                    label: { EmptyView() }
                )
                .hidden()
                
                // 用于跳转到「设置」界面
                NavigationLink(
                    destination: SettingsView(),
                    isActive: $showingSettings,
                    label: { EmptyView() }
                )
                .hidden()
                
                // 文本输入框
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $linkInput)
                        .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.size.height * 0.55)
                        .padding(10)                        // 设置内边距
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.gray, lineWidth: 1.5)
                        )                                   // 圆角矩形边框
                        .multilineTextAlignment(.leading)   // 初始时光标最左
                    
                    Text("请粘贴链接，每行一个")
                        .foregroundColor(Color.gray)
                        .opacity(linkInput.isEmpty ? 1 : 0) // 显示提示词的条件
                        .padding(.horizontal, 14)           // 调整左边距
                        .padding(.top, 18)                  // 调整上边距
                }
                .padding()
                
                // 底部栏
                HStack {
                    Button(action: {
                        // 执行粘贴操作的函数
                        pasteButtonTapped()
                    }) {
                        Image("clipboard")
                            .resizable()
                            .frame(width: 22, height: 30)
                            .foregroundColor(Color("AccentColor"))
                    }
                    .padding()
                    
                    Button(action: {
                        Task {
                            // 执行下载操作的函数
                            await downloadButtonTapped()
                        }
                    }) {
                        Text("下载")
                            .foregroundColor(.white)
                            .bold()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color("AccentColor"))
                            .cornerRadius(10)
                    }
                    .padding()
                    
                    Button(action: {
                        // 清空文本框的内容
                        linkInput = ""
                        feedbackMessage = nil
                    }) {
                        Image(systemName: "trash")
                            .resizable()
                            .frame(width: 27, height: 30)
                            .foregroundColor(Color("AccentColor"))
                    }
                    .padding()
                }
                
                if let message = feedbackMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(isError ? .red : (isWarning ? .yellow : (isDownloading ? .yellow : .green)))
                        .padding()
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
    }
    
    private func pauseBriefly() async {
        // 短暂暂停 1 秒
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }
    
    // 执行下载操作
    func downloadButtonTapped() async {
        var urls: [URL] = []
        
        if linkInput.isEmpty {
            // 文本输入框为空
            feedbackMessage = "请输入链接"
            isError = true
            return
        }
        let links = linkInput.components(separatedBy: "\n")
        var line = 0
        
        for link in links {
            line += 1
            
            if link.isEmpty {
                // 处理空链接
                continue
            }
            
            let pattern = #"http[s]?://[^\s，]+"#
            
            if let match = link.range(of: pattern, options: .regularExpression) {
                let validLink = String(link[match])
                
                guard let url = URL(string: validLink) else {
                    // 处理无效的链接
                    feedbackMessage = "请检查第 \(line) 行包含的链接是否有效"
                    isError = true
                    return
                }
                
                urls.append(url)
            } else {
                // 不存在链接, 直接忽略该行
                feedbackMessage = "第 \(line) 行不包含链接, 跳过"
                isWarning = true
                continue
            }
        }
        
        if urls.isEmpty {
            // 文本输入框内全为空行
            feedbackMessage = "请输入链接"
            isError = true
            return
        }
        
        if backendUrl.isEmpty {
            // 后端地址未配置
            feedbackMessage = "请在设置中配置后端地址"
            isError = true
            return
        }
        
        line = 0
        for url in urls {
            line += 1

            isDownloading = true
            feedbackMessage = "【\(line) / \(urls.count)】处理中..."
            isError = false
            isWarning = false
            
            // 发起网络请求
            do {
                // 向后端发起提取图片或视频 URLs 的请求
                let mediaUrls = try await fetchMediaUrls(url: url)
                
                if mediaUrls.isEmpty {
                    feedbackMessage = "【\(line) / \(urls.count)】未提取到图片或视频的链接"
                    isError = true
                    
                    // Record failure to history
                    HistoryManager.shared.addRecord(
                        url: url.absoluteString,
                        downloaderType: selectedDownloader.rawValue,
                        isSuccess: false,
                        mediaCount: 0
                    )
                    
                    // Debug: 检查提取的媒体链接
                    print("⚠️ [\(line) / \(urls.count)] 未提取到图片或视频的链接, 原始 URL: \(url)")
                    return
                }
                
                // 根据提取的链接, 下载图片或视频, 并保存至相册
                for (index, mediaUrl) in mediaUrls.enumerated() {
                    if selectedDownloader == .xhsLiveImg {
                        guard let mediaUrlTuple = mediaUrl as? (String, String) else {
                            feedbackMessage = "【\(line) / \(urls.count)】提取的实况图片链接不是元组类型（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            return
                        }
                        
                        // 提取实况封面的 URL
                        guard let coverUrl = URL(string: mediaUrlTuple.0) else {
                            feedbackMessage = "【\(line) / \(urls.count)】提取的实况封面链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            return
                        }
                        
                        // 提取实况视频的 URL
                        let videoUrl: URL?
                        if mediaUrlTuple.1.isEmpty {
                            videoUrl = nil
                        } else {
                            guard let validVideoUrl = URL(string: mediaUrlTuple.1) else {
                                feedbackMessage = "【\(line) / \(urls.count)】提取的实况视频链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                                return
                            }
                            videoUrl = validVideoUrl
                        }
                        
                        do {
                            // 请求下载资源
                            isDownloading = true
                            feedbackMessage = "【\(line) / \(urls.count)】下载中...（\(index + 1) / \(mediaUrls.count)）"
                            isError = false
                            isWarning = false
                            
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
                            await saveLiveImageToPhotoLibrary(coverData: coverData, videoData: videoData, currentLine: line, totalLines: urls.count, currentIndex: index + 1, totalCount: mediaUrls.count)
                        } catch {
                            feedbackMessage = "【\(line) / \(urls.count)】实况图片下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            
                            // Record failure to history
                            HistoryManager.shared.addRecord(
                                url: url.absoluteString,
                                downloaderType: selectedDownloader.rawValue,
                                isSuccess: false,
                                mediaCount: index
                            )
                            return
                        }
                    } else {
                        // 将 Unicode 编码 \u002F 替换为 /
                        guard let mediaUrlString = mediaUrl as? String else {
                            feedbackMessage = "【\(line) / \(urls.count)】提取的资源链接不是字符串类型（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            return
                        }
                        let decodedMediaUrlString = mediaUrlString.replacingOccurrences(of: "\\u002F", with: "/")
                        
                        guard let decodedMediaUrl = URL(string: decodedMediaUrlString) else {
                            feedbackMessage = "【\(line) / \(urls.count)】提取的资源链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            
                            // Debug: 检查提取的链接
                            print("⚠️ [\(line) / \(urls.count)] 提取的链接: \(mediaUrl)（\(index + 1) / \(mediaUrls.count)）")
                            return
                        }
                        
                        do {
                            // 请求下载资源
                            isDownloading = true
                            feedbackMessage = "【\(line) / \(urls.count)】下载中...（\(index + 1) / \(mediaUrls.count)）"
                            isError = false
                            isWarning = false
                            let (data, response) = try await URLSession.shared.data(from: decodedMediaUrl)
                            
                            // 检查有没有发生错误
                            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                throw URLError(.badServerResponse)
                            }
                            
                            switch selectedDownloader {
                            case .xhsVid: // 小红书视频下载器
                                // 将视频保存至相册
                                await saveVideoToPhotoLibrary(videoData: data, currentLine: line, totalLines: urls.count, currentIndex: index + 1, totalCount: mediaUrls.count)
                            default: // 图片下载器
                                // 将图片保存至相册
                                await saveImageToPhotoLibrary(imageData: data, currentLine: line, totalLines: urls.count, currentIndex: index + 1, totalCount: mediaUrls.count)
                            }
                        } catch {
                            feedbackMessage = "【\(line) / \(urls.count)】图片或视频下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                            isError = true
                            
                            // Record failure to history
                            HistoryManager.shared.addRecord(
                                url: url.absoluteString,
                                downloaderType: selectedDownloader.rawValue,
                                isSuccess: false,
                                mediaCount: index
                            )
                            return
                        }
                    }
                }
                
                // Record success to history after all media items are downloaded
                HistoryManager.shared.addRecord(
                    url: url.absoluteString,
                    downloaderType: selectedDownloader.rawValue,
                    isSuccess: true,
                    mediaCount: mediaUrls.count
                )
                
            } catch {
                feedbackMessage = "【\(line) / \(urls.count)】" + (error.localizedDescription.isEmpty ? "未知错误" : error.localizedDescription)
                isError = true
                
                // Record failure to history
                HistoryManager.shared.addRecord(
                    url: url.absoluteString,
                    downloaderType: selectedDownloader.rawValue,
                    isSuccess: false,
                    mediaCount: 0
                )
                return
            }
        }
    }
    
    // 将图片保存至相册
    func saveImageToPhotoLibrary(imageData: Data, currentLine: Int, totalLines: Int, currentIndex: Int, totalCount: Int) async {
        guard let image = UIImage(data: imageData) else {
            feedbackMessage = "【\(currentLine) / \(totalLines)】图片数据无效（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            isDownloading = false
            feedbackMessage = "【\(currentLine) / \(totalLines)】图片保存成功（\(currentIndex) / \(totalCount)）"
            isError = false
            isWarning = false
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
        }
    }
    
    // 将视频保存至相册
    func saveVideoToPhotoLibrary(videoData: Data, currentLine: Int, totalLines: Int, currentIndex: Int, totalCount: Int) async {
        // 将视频数据写入临时文件
        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】写入临时视频文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
            return
        }
        
        do {
            defer {
                // 清理临时文件
                do {
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    print("♻️ [\(currentLine) / \(totalLines)] 已删除临时视频文件: \(tempVideoUrl)（\(currentIndex) / \(totalCount)）") }
                catch {
                    // Debug
                    print("⚠️ [\(currentLine) / \(totalLines)] 删除临时视频文件失败: \(error)（\(currentIndex) / \(totalCount)）")
                }
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempVideoUrl)
            }
            isDownloading = false
            feedbackMessage = "【\(currentLine) / \(totalLines)】视频保存成功（\(currentIndex) / \(totalCount)）"
            isError = false
            isWarning = false
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】视频保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
        }
    }
    
    // 将实况图片保存至相册
    func saveLiveImageToPhotoLibrary(coverData: Data, videoData: Data?, currentLine: Int, totalLines: Int, currentIndex: Int, totalCount: Int) async {
        guard let videoData = videoData else {
            // 如果没有视频数据, 则当作普通图片保存
            await saveImageToPhotoLibrary(imageData: coverData, currentLine: currentLine, totalLines: totalLines, currentIndex: currentIndex, totalCount: totalCount)
            return
        }
        
        let tempCoverUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempCover.jpg")
        do {
            try coverData.write(to: tempCoverUrl)
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】写入临时封面文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
            return
        }
        
        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】写入临时视频文件失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
            return
        }
        
        do {
            defer {
                do {
                    try FileManager.default.removeItem(at: tempCoverUrl)
                    try FileManager.default.removeItem(at: tempVideoUrl)
                    print("♻️ [\(currentLine) / \(totalLines)] 已删除临时文件: \(tempCoverUrl), \(tempVideoUrl)（\(currentIndex) / \(totalCount)）")
                } catch {
                    // Debug
                    print("⚠️ [\(currentLine) / \(totalLines)] 删除临时文件失败: \(error)（\(currentIndex) / \(totalCount)）")
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
            
            isDownloading = false
            feedbackMessage = "【\(currentLine) / \(totalLines)】实况图片保存成功（\(currentIndex) / \(totalCount)）"
            isError = false
            isWarning = false
        } catch {
            feedbackMessage = "【\(currentLine) / \(totalLines)】实况图片保存失败: \(error.localizedDescription)（\(currentIndex) / \(totalCount)）"
            isError = true
            await pauseBriefly()
        }
    }
    
    // 执行粘贴操作
    func pasteButtonTapped() {
        if let clipboardContent = UIPasteboard.general.string {
            if linkInput.isEmpty {
                linkInput += clipboardContent
            }
            else {
                linkInput += "\n" + clipboardContent
            }
        } else {
            feedbackMessage = "剪贴板为空"
            isError = true
        }
    }
    
    // 向后端发起提取图片或视频 URLs 的请求
    func fetchMediaUrls(url: URL) async throws -> [Any] {
        guard !backendUrl.isEmpty else {
            throw URLError(.badURL)
        }
        
        // 构建请求 URL
        let baseUrl = backendUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpoint = "\(baseUrl)/v1/extract"
        let token = backendToken.isEmpty ? "default_token" : backendToken
        
        var components = URLComponents(string: endpoint)
        components?.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "downloader", value: selectedDownloader.rawValue),
            URLQueryItem(name: "token", value: token)
        ]
        
        guard let requestUrl = components?.url else {
            throw URLError(.badURL)
        }
        
        // 创建网络请求
        var request = URLRequest(url: requestUrl)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300

        print("🔗 向 \(requestUrl) 发起解析请求")

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
        if selectedDownloader == .xhsLiveImg { // 当前「实况图片下载器」只有小红书的这一个
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
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .previewDisplayName("Light Mode")
            
            ContentView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
