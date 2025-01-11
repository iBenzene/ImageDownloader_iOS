//
//  ContentView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2023/12/26.
//  Copyright (c) 2023 iBenzene. All rights reserved.
//

import SwiftUI
import Photos

enum ImageDownloaderType: String, CaseIterable {
    case xhsImg = "小红书图片下载器"
    case xhsLiveImg = "小红书实况图片下载器（Beta 版）"
    case xhsVid = "小红书视频下载器"
    case mysImg = "米游社图片下载器"
    case wbImg = "微博图片下载器"
}

struct ContentView: View {
    @State private var linkInput: String = ""
    @State private var feedbackMessage: String?
    
    @State private var isError: Bool = false
    @State private var isDownloading: Bool = false
    @State private var isShowingSettings = false
    @State private var selectedDownloader: ImageDownloaderType = .xhsImg
    
    @AppStorage("xhsCookie") private var xhsCookie: String = ""
    @AppStorage("weiboCookie") private var weiboCookie: String = ""
    @AppStorage("weiboCookiesPoolUrl") private var weiboCookiesPoolUrl: String = ""
    
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
                            isShowingSettings = true
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
                
                // 用于跳转到「设置」界面
                NavigationLink(
                    destination: SettingsView(),
                    isActive: $isShowingSettings,
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
                        .foregroundColor(isError ? .red : (isDownloading ? .yellow : .green))
                        .padding()
                }
            }
            .padding()
            .navigationBarHidden(true)
        }
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
        var cnt = 1
        
        for link in links {
            if link.isEmpty {
                // 处理空链接
                cnt += 1
                continue
            }
            
            let pattern = #"http[s]?://[^\s，]+"#
            
            if let match = link.range(of: pattern, options: .regularExpression) {
                let validLink = String(link[match])
                
                guard let url = URL(string: validLink) else {
                    // 处理无效的链接
                    feedbackMessage = "请检查第 \(cnt) 行包含的链接是否有效"
                    isError = true
                    return
                }
                
                urls.append(url)
                cnt += 1
                
            } else {
                // 不存在链接
                feedbackMessage = "请检查第 \(cnt) 行是否包含有效链接"
                isError = true
                return
            }
        }
        
        if urls.isEmpty {
            // 文本输入框内全为空行
            feedbackMessage = "请输入链接"
            isError = true
            return
        }
        
        for url in urls {
            // 发起网络请求
            do {
                if let text = try await fetchUrl(url: url) {
                    
                    // 解析响应的文本并从中提取图片或视频的链接
                    let mediaUrls: [Any]
                    if selectedDownloader == .xhsLiveImg {
                        mediaUrls = try await parsingResponse(text: text, url: url)
                    } else {
                        mediaUrls = parsingResponse(text: text)
                    }
                    
                    // 响应的文本中不包含目标图片或视频的链接
                    if mediaUrls.isEmpty {
                        feedbackMessage = "响应的文本中不包含目标图片或视频的链接"
                        isError = true
                        
                        // Debug: 检查响应的文本
                        print("⚠️ 请求 \(url) 的响应: \(text)")
                        return
                    }
                    
                    // 根据提取的链接, 下载图片或视频, 并保存至相册
                    for (index, mediaUrl) in mediaUrls.enumerated() {
                        if selectedDownloader == .xhsLiveImg {
                            guard let mediaUrlTuple = mediaUrl as? (String, String) else {
                                feedbackMessage = "提取的实况图片链接不是元组类型（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                                return
                            }
                            
                            // 提取实况封面的 url
                            guard let coverUrl = URL(string: mediaUrlTuple.0) else {
                                feedbackMessage = "提取的实况封面链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                                return
                            }
                            
                            // 提取实况视频的 url
                            let videoUrl: URL?
                            if mediaUrlTuple.1.isEmpty {
                                videoUrl = nil
                            } else {
                                guard let validVideoUrl = URL(string: mediaUrlTuple.1) else {
                                    feedbackMessage = "提取的实况视频链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                                    isError = true
                                    return
                                }
                                videoUrl = validVideoUrl
                            }
                            
                            do {
                                // 请求下载资源
                                isDownloading = true
                                feedbackMessage = "下载中..."
                                isError = false
                                
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
                                saveLiveImageToPhotoLibrary(coverData: coverData, videoData: videoData, currentIndex: index + 1, totalCount: mediaUrls.count)
                            } catch {
                                feedbackMessage = "实况图片下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                            }
                        } else {
                            // 将 Unicode 编码 \u002F 替换为 /
                            guard let mediaUrlString = mediaUrl as? String else {
                                feedbackMessage = "提取的资源链接不是字符串类型（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                                return
                            }
                            let decodedMediaUrlString = mediaUrlString.replacingOccurrences(of: "\\u002F", with: "/")
                            
                            guard let decodedMediaUrl = URL(string: decodedMediaUrlString) else {
                                feedbackMessage = "提取的资源链接不是合法的 URL（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                                
                                // Debug: 检查提取的链接
                                print("⚠️ 提取的链接: \(mediaUrl)")
                                return
                            }
                            
                            do {
                                // 请求下载资源
                                isDownloading = true
                                feedbackMessage = "下载中..."
                                isError = false
                                let (data, response) = try await URLSession.shared.data(from: decodedMediaUrl)
                                
                                // 检查有没有发生错误
                                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                                    throw URLError(.badServerResponse)
                                }
                                
                                switch selectedDownloader {
                                case .xhsVid: // 小红书视频下载器
                                    // 将视频保存至相册
                                    saveVideoToPhotoLibrary(videoData: data, currentIndex: index + 1, totalCount: mediaUrls.count)
                                default: // 图片下载器
                                    // 将图片保存至相册
                                    saveImageToPhotoLibrary(imageData: data, currentIndex: index + 1, totalCount: mediaUrls.count)
                                }
                            } catch {
                                feedbackMessage = "图片或视频下载失败: \(error.localizedDescription)（\(index + 1) / \(mediaUrls.count)）"
                                isError = true
                            }
                        }
                    }
                }
            } catch {
                feedbackMessage = "网络请求失败: \(error.localizedDescription)"
                isError = true
            }
        }
    }
    
    // 发起网络请求, 获取包含目标资源 url 的文本或对象
    func fetchUrl(url: URL) async throws -> String? {
        // 声明要访问的 url
        let tgtUrl: URL
        
        // 声明伪造的请求头
        let headers: [String: String]
        
        switch selectedDownloader {
        case .xhsVid: // 小红书视频下载器
            // [2024-06-18] 小红书更新了, 只有在提供 Cookie 时, 才会暴露 originVideoKey 参数
            
            // 提取 Cookie
            let cookie: String
            
            if (!xhsCookie.isEmpty) {
                // 配置了 Cookie
                cookie = xhsCookie
            } else {
                // 没有配置 Cookies
                feedbackMessage = "请配置 Cookies"
                isError = true
                return nil
            }
            
            // 伪造浏览器的 http 请求, 通过 307 重定向来获取真实地址
            headers = [
                "Accept": "*/*",
                
                //（必不可少）用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                
                //（必不可少）Cookie
                "Cookie": cookie
            ]
            
            // 获取 url 的 host 属性
            if let host = url.host {
                // 如果域名是 xhslink.com 则需要重定向
                if host == "xhslink.com" {
                    // 创建一个临时请求
                    var tempRequest = URLRequest(url: url)
                    
                    // 设置请求头的信息x
                    tempRequest.allHTTPHeaderFields = headers
                    
                    // 创建一个自定义的 URLSessionDelegate 来处理重定向
                    class RedirectHandler: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
                        
                        // 禁止自动重定向
                        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
                            // 不进行自动重定向, 传递 nil 继续使用当前响应
                            completionHandler(nil)
                        }
                    }
                    
                    // 创建 URLSessionConfiguration
                    let config = URLSessionConfiguration.default
                    
                    // 创建一个自定义的 URLSession, 指定代理
                    let session = URLSession(configuration: config, delegate: RedirectHandler(), delegateQueue: nil)
                    
                    // 发起临时请求
                    let (_, response) = try await session.data(for: tempRequest)
                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 307 else {
                        feedbackMessage = "重定向异常"
                        isError = true
                        return nil
                    }
                    
                    // 获取 Location 属性
                    guard let location = httpResponse.allHeaderFields["Location"] as? String else {
                        feedbackMessage = "重定向失败: Location 属性不存在"
                        isError = true
                        return nil
                    }
                    
                    // 更新要访问的 url
                    tgtUrl = URL(string: location)!
                } else {
                    tgtUrl = url
                }
            } else {
                feedbackMessage = "网络请求异常: host 属性不存在"
                isError = true
                return nil
            }
            
        case .mysImg: // 米游社图片下载器
            let apiUrl: URL
            
            // 提取文章 id
            if let id = url.absoluteString.components(separatedBy: "/").last { // 为什么不直接使用 pathComponents.last 呢？因为会被 url 中的「?」干扰
                apiUrl = URL(string: "https://bbs-api.miyoushe.com/post/wapi/getPostFull?gids=2&post_id=\(id)&read=1")!
            } else {
                feedbackMessage = "提取文章 ID 失败"
                isError = true
                return nil
            }
            
            // 伪造 ajax 请求
            headers = [
                "Accept": "*/*",
                
                //（必不可少）防盗链
                "Referer": "https://www.miyoushe.com/",
                
                //（必不可少）用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
            
            // 更新要访问的 url
            tgtUrl = apiUrl
            
        case .wbImg: // 微博图片下载器
            let apiUrl: URL
            
            // 提取微博 id
            if let id = url.pathComponents.last?.split(separator: "?").first {
                apiUrl = URL(string:                    "https://weibo.com/ajax/statuses/show?id=\(id)&locale=zh-CN")!
            } else {
                feedbackMessage = "提取微博 ID 失败"
                isError = true
                return nil
            }
            
            // 提取 Cookie
            let cookie: String
            
            if (!weiboCookiesPoolUrl.isEmpty) {
                // 配置了 Cookies 池的 URL
                guard let tempUrl = URL(string: weiboCookiesPoolUrl) else {
                    feedbackMessage = "Cookies 池的 URL 无效"
                    isError = true
                    return nil
                }
                
                // 访问 Cookies 池
                let (data, response) = try await URLSession.shared.data(from: tempUrl)
                
                // 检查有没有发生错误
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    feedbackMessage = "访问 Cookies 池失败"
                    isError = true
                    return nil
                }
                
                // 定义数据模型
                struct User: Codable {
                    let cookie: String
                    let lastUpdate: String?
                }
                
                struct Users: Codable {
                    let users: [String: User]
                }
                
                // 随机选择一个 Cookie
                do {
                    let users = try JSONDecoder().decode([String: User].self, from: data)
                    if let randomUser = users.keys.randomElement(), let user = users[randomUser] {
                        cookie = user.cookie
                    } else {
                        feedbackMessage = "访问 Cookies 池异常"
                        isError = true
                        return nil
                    }
                } catch {
                    feedbackMessage = "Cookies 池的格式不正确"
                    isError = true
                    return nil
                }
            } else if (!weiboCookie.isEmpty) {
                // 配置了 Cookie
                cookie = weiboCookie
            } else {
                // 没有配置 Cookies
                feedbackMessage = "请配置 Cookies"
                isError = true
                return nil
            }
            
            // 伪造 ajax 请求
            headers = [
                "Accept": "*/*",
                
                // 用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                
                //（必不可少）Cookie
                "Cookie": cookie,
            ]
            
            // 更新要访问的 url
            tgtUrl = apiUrl
            
        default: // 小红书图片下载器
            // ToDo: 对于像 http://xhslink.com/TMTJmy 这种动态网页, html 文本中不包含目标图片的链接, 仍存在改进空间
            
            // [2024-03-29] 小红书开始检查请求的 User-Agent 字段了, 应该伪造浏览器的 HTTP 请求, 而不是使用 App 自带的 HTTP 请求
            // [2024-04-03] 从今天开始, 我们不再直接使用 App 自带的 HTTP 请求
            // let html = try String(contentsOf: url)
            
            // 伪造浏览器的 http 请求, 以获取网页的 html 文本
            headers = [
                "Accept": "*/*",
                
                //（必不可少）用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
            tgtUrl = url
        }
        
        // 创建一个网络请求
        var request = URLRequest(url: tgtUrl)
        print("🔗 向 \(tgtUrl) 发起网络请求。")
        
        // 设置请求头的信息
        request.allHTTPHeaderFields = headers
        
        // 发起网络请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查有没有发生错误
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // 将获取到的响应转换为字符串
        guard let result = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeRawData)
        }
        
        return result
    }
    
    // 生成指定长度的随机字母数字字符串
    func randomString(length: Int) -> String {
        let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
    
    // 生成指定长度的随机十六进制字符串
    func randomHexString(length: Int) -> String {
        let characters = "abcdef0123456789"
        return String((0..<length).compactMap { _ in characters.randomElement() })
    }
    
    // 解析 html 文本, 提取实况封面的 url, 同时使用「红薯库」提供的 api, 获取实况视频的 url
    func parsingResponse(text: String, url: URL) async throws -> [(String, String)] {
        let pattern = #"<meta\s+name="og:image"\s+content="([^"]+)""#
        let coverUrls = extractUrls(from: text, withPattern: pattern)
        
        // 随机生成 openId
        let openId = "oqVFV4" + randomString(length: 22)
        
        // 随机生成 sign, 作用未知
        let sign = randomHexString(length: 32)
        
        // 构建要访问的 url
        let tgtUrlString = "https://honghui.hongshuku.com/app/index.php?i=22&t=0&v=1.0&from=wxapp&c=entry&a=wxapp&do=dongtu&sign=\(sign)&m=qu_y&url=\(url)&openid=\(openId)"
        guard let tgtUrl = URL(string: tgtUrlString) else {
            // 如果 url 构建失败, 则返回封面 url, 视频 url 为空
            return coverUrls.map { ($0, "") }
        }
        
        // 伪造微信小程序的请求, 怕后端会记录日志
        let headers = [
            "Accept": "*/*",
            "Accept-Encoding": "gzip, compress, br, deflate",
            "Host": "honghui.hongshuku.com",
            "Connection": "keep-alive",
            
            // 微信小程序会自动添加的参数, 作为一种特征
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 MicroMessenger/8.0.54(0x1800363a) NetType/4G Language/zh_CN",
            "Referer": "https://servicewechat.com/wxd856b1e1305490f7/42/page-frame.html"
        ]
        
        // 创建一个网络请求
        var request = URLRequest(url: tgtUrl)
        print("🔗 向 \(tgtUrl) 发起网络请求。")
        
        // 设置请求头的信息
        request.allHTTPHeaderFields = headers
        
        // 发起网络请求
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // 检查有没有发生错误
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        // 定义数据模型
        struct Response: Codable {
            let errno: Int
            let message: String
            let data: [LiveImageData]
        }
        
        struct LiveImageData: Codable {
            let type: String
            let poster: String
            let url: String
        }
        
        do {
            let decoder = JSONDecoder()
            let response = try decoder.decode(Response.self, from: data)
            
            // 检查 errno 是否为 0
            guard response.errno == 0 else {
                return coverUrls.map { ($0, "") }
            }
            
            // 解析「红薯库」提供的 json
            let liveImageData = response.data
            var result: [(String, String)] = coverUrls.map { ($0, "") } // 这里先把所有 coverUrl 对应的 video 设为空
            var cnt = 0 // 统计实况照片的数目
            for (index, coverUrl) in coverUrls.enumerated() {
                let coverId = extractID(from: coverUrl)
                
                if let video = liveImageData.first(where: { extractID(from: $0.poster) == coverId }) {
                    print("🔍 发现实况图片: \(coverId)")
                    result[index].1 = video.url
                    cnt += 1
                }
            }
            print("📊 实况图片占比: \(cnt) / \(result.count)")
            return result
        } catch {
            print("⚠️ 解析「红薯库」提供的 JSON 时发生了一个错误: \(error)")
            return coverUrls.map { ($0, "") }
        }
    }
    
    // 解析 html 或 json 文本, 提取资源的 url
    func parsingResponse(text: String) -> [String] {
        switch selectedDownloader {
        case .xhsVid: // 小红书视频下载器
            let pattern = #""originVideoKey":"([^"]+)""#
            let prefix = "https://sns-video-al.xhscdn.com/"
            return extractUrls(from: text, withPattern: pattern, prefix: prefix)
            
        case .mysImg: // 米游社图片下载器
            let pattern = #""images"\s*:\s*\[([^\]]+)\]"#
            return extractUrls(from: text, withPattern: pattern, isJson: true)
            
        case .wbImg: // 微博图片下载器
            let pattern = #""pic_ids"\s*:\s*\[([^\]]+)\]"#
            let prefix = "https://wx1.sinaimg.cn/large/"
            return extractUrls(from: text, withPattern: pattern, prefix: prefix, isJson: true)
            
        default: // 小红书图片下载器
            let pattern = #"<meta\s+name="og:image"\s+content="([^"]+)""#
            return extractUrls(from: text, withPattern: pattern)
        }
    }
    
    
    
    // 提取资源的 url
    func extractUrls(from text: String, withPattern pattern: String, prefix: String = "", isJson: Bool = false) -> [String] {
        do {
            // 使用正则表达式创建一个模式匹配器
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            
            if isJson {
                // 在 json 文本中搜索匹配的部分
                guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                      let range = Range(match.range(at: 1), in: text) else {
                    // 服务器未返回包含目标资源的 url
                    // 米游社: {"data":null,"message":"Something went wrong...please retry later","retcode":-502}
                    // 微博: {"ok":-100,"url":"https://weibo.com/login.php"}
                    return []
                }
                
                // 获取匹配到的资源 url 或 id 列表, 移除双引号并按逗号进行拆分
                return String(text[range])
                    .replacingOccurrences(of: "\"", with: "")
                    .components(separatedBy: ",")
                    .map { prefix + $0 }
            } else {
                // 在 html 文本中搜索匹配的部分
                let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
                
                // 返回包含所有资源 url 的数组
                return matches.compactMap { match in
                    guard let range = Range(match.range(at: 1), in: text) else {
                        return nil
                    }
                    // 必要时重新构造资源的 url
                    return prefix + String(text[range])
                }
            }
        } catch {
            return []
        }
    }
    
    // 提取资源（主要是动态图片）的 id
    private func extractID(from urlString: String) -> String {
        guard let lastComponent = urlString.split(separator: "/").last else {
            return ""
        }
        // 有些 url 可能没有 !, 所以这里使用 first ?? ""
        let idPart = lastComponent.split(separator: "!").first ?? ""
        return String(idPart)
    }
    
    // 将图片保存至相册
    func saveImageToPhotoLibrary(imageData: Data, currentIndex: Int, totalCount: Int) {
        if let image = UIImage(data: imageData) {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success {
                    isDownloading = false
                    feedbackMessage = "图片保存成功（\(currentIndex) / \(totalCount)）"
                    isError = false
                } else {
                    feedbackMessage = "图片保存失败: \(error?.localizedDescription ?? "未知错误")（\(currentIndex) / \(totalCount)"
                    isError = true
                }
            }
        }
    }
    
    // 将视频保存至相册
    func saveVideoToPhotoLibrary(videoData: Data, currentIndex: Int, totalCount: Int) {
        // 将视频数据写入临时文件
        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            feedbackMessage = "写入临时视频文件失败: \(error.localizedDescription)"
            isError = true
            return
        }
        
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempVideoUrl)
        }) { success, error in
            if success {
                isDownloading = false
                feedbackMessage = "视频保存成功（\(currentIndex) / \(totalCount)）"
                isError = false
            } else {
                feedbackMessage = "视频保存失败: \(error?.localizedDescription ?? "未知错误")（\(currentIndex) / \(totalCount)）"
                isError = true
            }
            
            // 删除临时视频文件
            do {
                try FileManager.default.removeItem(at: tempVideoUrl)
                print("♻️ 已删除临时视频文件: \(tempVideoUrl)")
            } catch {
                // Debug
                print("⚠️ 删除临时视频文件失败: \(error)")
            }
        }
    }
    
    // 将实况图片保存至相册
    func saveLiveImageToPhotoLibrary(coverData: Data, videoData: Data?, currentIndex: Int, totalCount: Int) {
        guard let videoData = videoData else {
            // 如果没有视频数据, 则当作普通图片保存
            saveImageToPhotoLibrary(imageData: coverData, currentIndex: currentIndex, totalCount: totalCount)
            return
        }
        
        let tempCoverUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempCover.jpg")
        do {
            try coverData.write(to: tempCoverUrl)
        } catch {
            feedbackMessage = "写入临时封面文件失败: \(error.localizedDescription)"
            isError = true
            return
        }
        
        let tempVideoUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
        do {
            try videoData.write(to: tempVideoUrl)
        } catch {
            feedbackMessage = "写入临时视频文件失败: \(error.localizedDescription)"
            isError = true
            return
        }
        
        let livePhotoHelper = LivePhotoHelper()
        livePhotoHelper.saveLivePhoto(tempCoverUrl, videoUrl: tempVideoUrl) { success, error in
            if success {
                isDownloading = false
                feedbackMessage = "实况图片保存成功（\(currentIndex) / \(totalCount)）"
                isError = false
            } else {
                feedbackMessage = "实况图片保存失败: \(error?.localizedDescription ?? "未知错误")（\(currentIndex) / \(totalCount)）"
                isError = true
            }
            
            // 删除临时文件
            do {
                try FileManager.default.removeItem(at: tempCoverUrl)
                try FileManager.default.removeItem(at: tempVideoUrl)
                print("♻️ 已删除临时文件: \(tempCoverUrl), \(tempVideoUrl)")
            } catch {
                // Debug
                print("⚠️ 删除临时文件失败: \(error)")
            }
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
}

// 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
