//
//  ContentView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2023/12/26.
//  Copyright (c) 2023 iBenzene. All rights reserved.
//

import SwiftUI
import Photos

struct ContentView: View {
    @State private var linkInput: String = ""
    @State private var feedbackMessage: String?
    
    @State private var isError: Bool = false
    @State private var isWarning: Bool = false
    @State private var isDownloading: Bool = false
    @State private var showingLivePhotoConverter = false
    @State private var showingHistory = false
    
    @State private var showingDuplicateAlert = false
    @State private var pendingSavedLinks: [String] = []
    
    @AppStorage("saveLinksOnly") private var saveLinksOnly: Bool = false
    @AppStorage("preheatResources") private var preheatResources: Bool = false

    @State private var selectedDownloader: ImageDownloaderType = .xhsImg
    
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    
    var body: some View {
        NavigationStack {
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
                            showingHistory = true
                        } label: {
                            Label("下载记录", systemImage: "clock.arrow.circlepath")
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
                
                // 用于跳转到「下载记录」页面
                NavigationLink(
                    destination: HistoryView(),
                    isActive: $showingHistory,
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
                            if saveLinksOnly {
                                // 执行收藏操作的函数
                                await saveLinksButtonTapped()
                            } else {
                                // 执行下载操作的函数
                                await downloadButtonTapped()
                            }
                        }
                    }) {
                        Text(saveLinksOnly ? "收藏" : "下载")
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
            .toolbar(.hidden, for: .navigationBar)
            .alert("重复链接提醒", isPresented: $showingDuplicateAlert) {
                Button("取消", role: .cancel) {
                    pendingSavedLinks = []
                    feedbackMessage = "已取消收藏"
                    isWarning = true
                }
                Button("继续") {
                    Task {
                        await saveLinks(pendingSavedLinks)
                    }
                }
            } message: {
                Text("检测到收藏列表中已存在部分链接，是否继续收藏？")
            }
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
                feedbackMessage = "第 \(line) 行不包含链接，跳过"
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
        
        if serverUrl.isEmpty {
            // 服务端地址未配置
            feedbackMessage = "请在设置中配置服务端地址"
            isError = true
            return
        }
        
        isDownloading = true
        isError = false
        isWarning = false
        
        // 调用 DownloadManager 执行下载
        let result = await DownloadManager.shared.downloadMedia(
            urls: urls,
            downloaderType: selectedDownloader,
            onProgress: { progress in
                // 更新 UI 状态
                Task { @MainActor in
                    feedbackMessage = progress.message
                    isError = progress.isError
                    isWarning = progress.isWarning
                    isDownloading = !progress.isError
                }
            }
        )
        
        // 处理最终结果
        Task { @MainActor in
            // Must delay to ensure this runs after the last onProgress task
            try? await Task.sleep(nanoseconds: 100_000_000)
            switch result {
            case .success(let mediaCount):
                feedbackMessage = "下载完成，共保存 \(mediaCount) 个图片或视频"
                isError = false
                isWarning = false
                isDownloading = false
            case .failure(let error):
                feedbackMessage = error
                isError = true
                isDownloading = false
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
    
    // 执行收藏操作
    func saveLinksButtonTapped() async {
        var savedUrls: [String] = []
        
        if linkInput.isEmpty {
            feedbackMessage = "请输入链接"
            isError = true
            return
        }
        
        let lines = linkInput.components(separatedBy: "\n")
        var line = 0
        
        // Extract valid URLs from each line
        let pattern = #"http[s]?://[^\s，]+"#
        
        for text in lines {
            line += 1
            
            if text.isEmpty {
                continue
            }
            
            if let match = text.range(of: pattern, options: .regularExpression) {
                let validLink = String(text[match])
                savedUrls.append(validLink)
            }
        }
        
        if savedUrls.isEmpty {
            feedbackMessage = "未找到有效链接"
            isError = true
            return
        }
        
        // Check for duplicates (only active links)
        let duplicates = savedUrls.filter { url in
            SavedLinksManager.shared.hasActiveLink(url: url)
        }
        
        if !duplicates.isEmpty {
            // Found duplicates, ask user what to do
            pendingSavedLinks = savedUrls
            showingDuplicateAlert = true
            return
        }
        
        // No duplicates, save directly
        await saveLinks(savedUrls)
    }
    
    // Helper to actually save links and optionally preheat resources
    func saveLinks(_ urls: [String]) async {
        // Save all extracted URLs
        SavedLinksManager.shared.addLinks(urls: urls, downloaderType: selectedDownloader.rawValue)
        
        // Clear input and show initial success message
        linkInput = ""
        feedbackMessage = "已保存 \(urls.count) 个链接"
        isError = false
        isWarning = false
        isDownloading = false
        
        // Clear pending links
        pendingSavedLinks = []
        
        // Preheat resources if enabled
        guard preheatResources else { return }
        
        let validUrls = urls.compactMap { URL(string: $0) }
        guard !validUrls.isEmpty else { return }
        
        isDownloading = true
        feedbackMessage = "正在预热资源..."
        
        let result = await PreheatManager.shared.preheatResources(
            urls: validUrls,
            downloaderType: selectedDownloader,
            onProgress: { progress in
                Task { @MainActor in
                    feedbackMessage = progress.message
                    isError = progress.isError
                    isDownloading = !progress.isError
                }
            }
        )
        
        // Handle preheat result
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            switch result {
            case .success(let cachedUrls):
                // Store cached URLs to saved link items
                for url in urls {
                    if let item = SavedLinksManager.shared.visibleItems.first(where: { $0.url == url }) {
                        SavedLinksManager.shared.updateCachedUrls(for: item, cachedUrls: cachedUrls)
                    }
                }
                feedbackMessage = "已保存 \(urls.count) 个链接，预热成功（缓存 \(cachedUrls.count) 个资源）"
                isError = false
                isWarning = false
                isDownloading = false
            case .failure(let error):
                feedbackMessage = error
                isError = true
                isDownloading = false
            }
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
