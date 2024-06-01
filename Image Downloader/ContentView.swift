//
//  ContentView.swift
//  Image Downloader
//
//  Created by 邱想想 on 2023/12/26.
//

import SwiftUI
import Photos

enum ImageDownloaderType: String, CaseIterable {
    case xhsImg = "小红书图片下载器"
    case xhsVid = "小红书视频下载器"
    case mysImg = "米游社图片下载器"
    case wbImg = "微博图片下载器"
}

struct ContentView: View {
    @State private var linkInput: String = ""
    @State private var feedbackMessage: String?
    @State private var isError: Bool = false
    @State private var selectedDownloader: ImageDownloaderType = .xhsImg
    
    var body: some View {
        VStack {
            HStack {
                // 占位的空按钮
                Button(action: {}){
                    Image("").resizable()
                        .frame(width: 20, height: 20)
                }.padding()
                
                Spacer()
                
                HStack{
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
                    ForEach(ImageDownloaderType.allCases, id: \.self) { downloaderType in
                        Button(action: {
                            selectedDownloader = downloaderType
                        }) {
                            HStack {
                                Text(downloaderType.rawValue)
                                Spacer()
                                if selectedDownloader == downloaderType {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(Color("AccentColor"))
                }
                .padding()
            }
            
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
            
            HStack {
                Button(action: {
                    // 执行粘贴操作的函数
                    pasteButtonTapped()
                }) {
                    Image("clipboard")
                        .resizable()
                        .frame(width: 21, height: 28)
                        .foregroundColor(Color("AccentColor"))
                }.padding()
                
                Button(action: {
                    // 执行下载操作的函数
                    downloadButtonTapped()
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
                        .frame(width: 25, height: 26)
                        .foregroundColor(Color("AccentColor"))
                }.padding()
            }
            
            if let message = feedbackMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(isError ? .red : .green)
                    .padding()
            }
        }
        .padding()
    }
    
    // 执行下载操作
    func downloadButtonTapped() {
        var urls: [URL] = []
        
        if linkInput.isEmpty {
            // 文本输入框为空
            feedbackMessage = "文本框为空"
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
            feedbackMessage = "文本框为空"
            isError = true
            return
        }
        
        for url in urls {
            // 发起网络请求
            if let text = fetchUrl(url: url) {
                // 解析响应的文本并提取图片或视频的链接
                let mediaUrls = parsingURL(text: text)
                
                // 响应的文本中不包含目标图片或视频的链接
                if mediaUrls.isEmpty {
                    feedbackMessage = "响应的文本中不包含目标图片或视频的链接"
                    isError = true
                    
                    // Debug: 检查响应的文本
                    print("⚠️ 服务器返回值: \(text)")
                }
                
                // 下载图片或视频并保存至相册
                // ToDo: 修复保存的资源顺序错乱的问题
                for mediaUrl in mediaUrls {
                    download(url: mediaUrl)
                }
            } else {
                feedbackMessage = "网络请求失败"
                isError = true
            }
        }
    }
    
    // 发起网络请求, 获取包含图片 url 的网络资源
    func fetchUrl(url: URL) -> String? {
        // 声明要访问网络资源的 url
        var tgtUrl: URL
        
        // 声明伪造的请求头
        var headers = [String: String]()
        
        switch selectedDownloader {
        case .mysImg: // 米游社图片下载器
            var apiUrl: URL
            
            // 提取文章 id
            if let id = url.absoluteString.components(separatedBy: "/").last { // 为什么不直接使用 pathComponents.last 呢？因为会被 url 中的「?」干扰
                apiUrl = URL(string: "https://bbs-api.miyoushe.com/post/wapi/getPostFull?gids=2&post_id=\(id)&read=1")!
            } else {
                return nil
            }
            
            // 伪造 ajax 请求
            headers = [
                "Accept": "application/json, text/plain, */*",
                
                //（必不可少）防盗链
                "Referer": "https://www.miyoushe.com/",
                
                //（必不可少）用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
            
            // 更新要访问网络资源的 url
            tgtUrl = apiUrl
            
        case .wbImg: // 微博图片下载器
            var apiUrl: URL
            
            // 提取文章 id
            if let id = url.pathComponents.last?.split(separator: "?").first {
                apiUrl = URL(string:                    "https://weibo.com/ajax/statuses/show?id=\(id)&locale=zh-CN")!
            } else {
                return nil
            }
            
            // 伪造 ajax 请求
            headers = [
                "Accept": "application/json, text/plain, */*",
                
                // 用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                
                //（必不可少）Cookie
                // ToDo: 直接调用微博的 API, 让用户登录, 从而动态地获取 Cookie
                "Cookie": "SUB=_2A25LCeW_DeRhGeFH6lER8y_LzzWIHXVoZ2d3rDV8PUJbkNANLU7EkW1Ne-bxq52WL40B6-0wyRk09FCbgKKmgDBO",
            ]
            
            // 更新要访问网络资源的 url
            tgtUrl = apiUrl
            
        default: // 小红书图片下载器、小红书视频下载器
            // ToDo: 对于像 http://xhslink.com/TMTJmy 这种动态网页, html 文本中不包含目标图片的链接, 仍存在改进空间
            
            // [2024-03-29] 小红书开始检查请求的 User-Agent 字段了, 应该伪造浏览器的 HTTP 请求, 而不是使用 App 自带的 HTTP 请求
            // [2024-04-03] 适应性维护: 不再直接使用 App 自带的 HTTP 请求
            // let html = try String(contentsOf: url)
            
            // 伪造浏览器的 http 请求, 以获取网页的 html 文本
            headers = [
                "Accept": "application/json, text/plain, */*",
                
                //（必不可少）用户代理
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            ]
            tgtUrl = url
        }
        var request = URLRequest(url: tgtUrl)
        print("🔗 向 \(tgtUrl) 发起网络请求")
        
        // 设置请求头信息
        request.allHTTPHeaderFields = headers
        
        // 创建一个信号量, 用于等待异步任务完成
        let semaphore = DispatchSemaphore(value: 0)
        
        // 发起一个异步网络请求
        var result: String?
        URLSession.shared.dataTask(with: request) {data, response, error in
            // 异步任务完成后执行的代码块
            defer {
                // 释放信号量, 表示异步任务已经完成
                semaphore.signal()
            }
            
            // 判断是否存在数据且没有发生错误
            guard let data = data, error == nil else {
                // 如果出现错误或者没有数据, 则直接返回
                return
            }
            
            // 将获取到的响应转换成字符串
            result = String(data: data, encoding: .utf8)
        }.resume()
        
        // 等待异步任务完成
        semaphore.wait()
        
        return result
    }
    
    // 解析 html 或 json 文本, 提取图片的 url
    func parsingURL(text: String) -> [String] {
        switch selectedDownloader {
        case .xhsImg: // 小红书图片下载器
            let html = text
            
            // 定义正则表达式模式
            let pattern = "<meta\\s+name=\"og:image\"\\s+content=\"([^\"]+)\""
            
            // 在 html 文本中搜索匹配的部分
            do {
                // 使用正则表达式创建一个模式匹配器
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
                
                // 用于存储找到的图片 url 的数组
                var imageUrls: [String] = []
                
                // 遍历所有匹配项
                for match in matches {
                    // 获取匹配到的子字符串的范围
                    let range = Range(match.range(at: 1), in: html)!
                    
                    // 从 html 中提取图片 url
                    let imageUrl = String(html[range])
                    
                    // 将提取到的图片 url 添加到数组中
                    imageUrls.append(imageUrl)
                }
                
                // 返回包含所有图片 url 的数组
                return imageUrls
            } catch {
                return []
            }
            
        case .xhsVid: // 小红书视频下载器
            let html = text
            
            // 定义正则表达式模式
            let pattern = "\"originVideoKey\":\"([^\"]+)\""
            
            // 在 html 文本中搜索匹配的部分
            do {
                // 使用正则表达式创建一个模式匹配器
                let regex = try NSRegularExpression(pattern: pattern, options: [])
                let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
                
                // 用于存储找到的视频 url 的数组
                var videoUrls: [String] = []
                
                // 遍历所有匹配项
                for match in matches {
                    // 获取匹配到的子字符串的范围
                    let range = Range(match.range(at: 1), in: html)!
                    
                    // 从 html 中提取视频 url 参数, 并构造视频 url
                    let videoUrl = "https://sns-video-al.xhscdn.com/" + String(html[range])
                    
                    // 将提取到的视频 url 添加到数组中
                    videoUrls.append(videoUrl)
                }
                
                // 返回包含所有视频 url 的数组
                return videoUrls
            } catch {
                return []
            }
            
        case .mysImg: // 米游社图片下载器
            let json = text
            
            // 定义正则表达式模式
            let pattern = #""images"\s*:\s*\[([^\]]+)\]"#
            
            // 在 json 文本中搜索匹配的部分
            guard let match = try? NSRegularExpression(pattern: pattern, options: [])
                .firstMatch(in: json, options: [], range: NSRange(json.startIndex..., in: json)),
                  let range = Range(match.range(at: 1), in: json) else {
                // 服务器未返回包含目标图片链接
                // 可能的错误: {"data":null,"message":"Something went wrong...please retry later","retcode":-502}
                return []
            }
            
            // 获取匹配到的图片链接列表字符串
            let imagesStr = String(json[range])
            
            // 移除双引号并按逗号拆分字符串
            let imagesList = imagesStr
                .replacingOccurrences(of: "\"", with: "")
                .components(separatedBy: ",")
            
            return imagesList
            
        case .wbImg: // 微博图片下载器
            let json = text
            
            // 定义正则表达式模式
            let pattern = #""pic_ids"\s*:\s*\[([^\]]+)\]"#
            
            // 在 json 文本中搜索匹配的部分
            guard let match = try? NSRegularExpression(pattern: pattern, options: [])
                .firstMatch(in: json, options: [], range: NSRange(json.startIndex..., in: json)),
                  let range = Range(match.range(at: 1), in: json) else {
                // 服务器未返回包含目标图片链接
                // 可能的错误: {"ok":-100,"url":"https://weibo.com/login.php"}
                return []
            }
            
            // 获取匹配到的图片 id 列表字符串, 移除双引号并按逗号拆分
            let picIds = String(json[range]).replacingOccurrences(of: "\"", with: "")
                .components(separatedBy: ",")

            // 拼接图片的完整的 url
            let imagesList = picIds.map { picId in
                return "https://wx1.sinaimg.cn/large/\(picId)"
            }
            
            return imagesList
        }
    }
    
    // 获取并下载图片或视频
    func download(url: String) {
        guard let mediaURL = URL(string: url) else {
            feedbackMessage = "无效的图片或视频链接，响应的文本可能存在问题"
            isError = true
            return
        }
        
        URLSession.shared.dataTask(with: mediaURL) { data, _, error in
            if let data = data {
                switch selectedDownloader {
                case .xhsVid: // 小红书视频下载器
                    // 将视频保存至相册
                    saveVideoToPhotoLibrary(videoData: data)
                default: // 图片下载器
                    // 将图片保存至相册
                    saveImageToPhotoLibrary(imageData: data)
                }
            } else {
                feedbackMessage = "图片或视频下载失败: \(error?.localizedDescription ?? "未知错误")"
                isError = true
            }
        }.resume()
    }
    
    // 将图片保存至相册
    func saveImageToPhotoLibrary(imageData: Data) {
        if let image = UIImage(data: imageData) {
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, error in
                if success {
                    feedbackMessage = "图片保存成功"
                    isError = false
                } else {
                    feedbackMessage = "图片保存失败: \(error?.localizedDescription ?? "未知错误")"
                    isError = true
                }
            }
        }
    }
    
    // 将视频保存至相册
    func saveVideoToPhotoLibrary(videoData: Data) {
        do {
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("tempVideo.mp4")
            try videoData.write(to: tempURL)
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: tempURL)
            }) { success, error in
                if success {
                    feedbackMessage = "视频保存成功"
                    isError = false
                } else {
                    feedbackMessage = "视频保存失败: \(error?.localizedDescription ?? "未知错误")"
                    isError = true
                }
                
                // 删除临时视频文件
                do {
                    try FileManager.default.removeItem(at: tempURL)
                } catch {
                    print("⚠️ Failed to delete temporary video file: \(error.localizedDescription)")
                }
            }
        } catch {
            feedbackMessage = "无法保存视频: \(error.localizedDescription)"
            isError = true
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
