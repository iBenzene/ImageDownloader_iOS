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
    @State private var pendingSavedLinksDownloader: ImageDownloaderType?
    
    @AppStorage("saveLinksOnly") private var saveLinksOnly: Bool = false
    @AppStorage("preheatResources") private var preheatResources: Bool = false

    @State private var selectedDownloader: ImageDownloaderType = .xhsImg
    
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
                        startPrimaryAction()
                    }) {
                        Text(saveLinksOnly ? "收藏" : "下载")
                            .foregroundColor(.white)
                            .bold()
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color("AccentColor"))
                            .cornerRadius(10)
                    }
                    .disabled(isDownloading)
                    .opacity(isDownloading ? 0.6 : 1)
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
                    pendingSavedLinksDownloader = nil
                    feedbackMessage = "已取消收藏"
                    isError = false
                    isWarning = true
                    isDownloading = false
                }
                Button("继续") {
                    continueSavingPendingLinks()
                }
            } message: {
                Text("检测到收藏列表中已存在部分链接，是否继续收藏？")
            }
        }
    }
    
    @MainActor
    private func startPrimaryAction() {
        guard !isDownloading else { return }
        
        let input = linkInput
        let downloaderType = selectedDownloader
        let shouldSaveLinksOnly = saveLinksOnly
        
        feedbackMessage = shouldSaveLinksOnly ? "正在收藏..." : "准备下载..."
        isError = false
        isWarning = false
        isDownloading = true
        
        Task {
            if shouldSaveLinksOnly {
                await saveLinksButtonTapped(input: input, downloaderType: downloaderType)
            } else {
                await downloadButtonTapped(input: input, downloaderType: downloaderType)
            }
        }
    }
    
    @MainActor
    private func continueSavingPendingLinks() {
        guard !isDownloading else { return }
        
        let urls = pendingSavedLinks
        let downloaderType = pendingSavedLinksDownloader ?? selectedDownloader
        
        feedbackMessage = "正在收藏..."
        isError = false
        isWarning = false
        isDownloading = true
        
        Task {
            await saveLinks(urls, downloaderType: downloaderType)
        }
    }
    
    // 执行下载操作
    func downloadButtonTapped(input: String, downloaderType: ImageDownloaderType) async {
        let result = await DownloadManager.shared.performDownload(
            from: input,
            downloaderType: downloaderType,
            invalidLineHandling: .skipWithWarning,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )
        
        Task { @MainActor in
            applyWorkflowResult(result)
        }
    }

    private func applyFeedback(_ feedback: HomeWorkflowFeedback) {
        feedbackMessage = feedback.message
        isError = feedback.isError
        isWarning = feedback.isWarning
        isDownloading = feedback.isDownloading
    }

    private func applyWorkflowResult(_ result: HomeWorkflowResult) {
        if result.shouldClearInput {
            linkInput = ""
        }

        applyFeedback(result.feedback)
    }

    private func handleSavePreparation(
        _ preparation: HomeSavePreparation,
        downloaderType: ImageDownloaderType
    ) async {
        switch preparation {
        case .ready(let urls):
            await saveLinks(urls, downloaderType: downloaderType)
        case .needsDuplicateConfirmation(let urls):
            pendingSavedLinks = urls
            pendingSavedLinksDownloader = downloaderType
            showingDuplicateAlert = true
            feedbackMessage = "请确认是否继续收藏"
            isError = false
            isWarning = true
            isDownloading = false
        case .feedback(let feedback):
            applyFeedback(feedback)
        }
    }

    private func saveLinks(_ urls: [String], downloaderType: ImageDownloaderType) async {
        let result = await DownloadManager.shared.saveLinks(
            urls,
            downloaderType: downloaderType,
            shouldPreheatResources: preheatResources,
            onProgress: { feedback in
                applyFeedback(feedback)
            }
        )

        Task { @MainActor in
            pendingSavedLinks = []
            pendingSavedLinksDownloader = nil
            applyWorkflowResult(result)
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
    func saveLinksButtonTapped(input: String, downloaderType: ImageDownloaderType) async {
        await handleSavePreparation(
            DownloadManager.shared.prepareSaveLinks(from: input),
            downloaderType: downloaderType
        )
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
