//
//  LivePhotoConverterView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2025/8/6.
//

import SwiftUI
import PhotosUI

// MARK: - 实况照片转换器视图
struct LivePhotoConverterView: View {
    @Environment(\.presentationMode) private var presentationMode
    
    // 弹窗开关
    @State private var showCoverPicker = false
    @State private var showVideoPicker = false
    
    // 业务数据
    @State private var coverUrl: URL?
    @State private var videoUrl: URL?
    
    // UI 状态
    @State private var isProcessing = false
    @State private var alertMsg    = ""
    @State private var showAlert   = false
    
    // iOS 16 原生 PhotosPicker 的选中项
    @State private var coverItem: PhotosPickerItem?
    @State private var videoItem: PhotosPickerItem?
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .edgesIgnoringSafeArea(.horizontal)
            
            // 显示照片（全屏铺满）
            if let coverUrl = coverUrl,
               let image = UIImage(contentsOfFile: coverUrl.path) {
                
                GeometryReader { proxy in
                    let fullWidth = proxy.size.width           // 可用宽度（含安全区）
                    
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)        // 保持比例, 且不裁切
                        .frame(width: fullWidth)               // 宽度占满
                        .position(x: fullWidth / 2,            // 垂直方向居中显示
                                  y: proxy.size.height / 2)
                }
                .background(Color(.systemBackground))          // 剩余区域与系统背景同色
                .transition(.opacity)
            } else {
                // 尚未选择封面时的占位
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 72))
                        .foregroundColor(.secondary)
                    Text("请先选择实况封面")
                        .foregroundColor(.secondary)
                }.contentShape(Rectangle()) // 使整个占位区域可点击
                    .onTapGesture {
                        withAnimation(.easeIn(duration: 0.2)) {
                            showCoverPicker = true // 再次弹出封面选择器
                        }
                    }
            }
            
            // 「合成中」浮层
            if isProcessing {
                ProgressView("合成中...")
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .navigationBarTitle("实况图片转换器", displayMode: .inline)
        .navigationBarItems(trailing: trailingBarItem)
        .onAppear {
            cleanupWorkDir() // 页面加载时清理一次缓存
            if coverUrl == nil {
                showCoverPicker = true // 进入页面时, 立即选择封面
            }
        }
        .onDisappear {
            // 页面退出时清理一次缓存
            cleanupWorkDir()
        }
        // iOS16 原生 PhotosPicker
        .photosPicker(
            isPresented: $showCoverPicker,
            selection: $coverItem,
            matching: .images
        )
        .photosPicker(
            isPresented: $showVideoPicker,
            selection: $videoItem,
            matching: .videos
        )
        // 监听封面和视频的选取
        .onChange(of: coverItem) { newItem in
            guard newItem != nil else { return }
            Task { await handlePickerResults(newItem, isCover: true) }
        }
        .onChange(of: videoItem) { newItem in
            guard newItem != nil else { return }
            Task { await handlePickerResults(newItem, isCover: false) }
        }
        // 转换完成后的弹窗
        .alert(isPresented: $showAlert) {
            Alert(title: Text(alertMsg),
                  dismissButton: .default(Text("好的")) {
                presentationMode.wrappedValue.dismiss() // 返回主页
            })
        }
    }
    
    // 仅在选完封面后显示「下一步」按钮
    @ViewBuilder
    private var trailingBarItem: some View {
        if coverUrl != nil && videoUrl == nil {
            Button("下一步") { showVideoPicker = true }
        }
    }
    
    // 处理选取结果
    private func handlePickerResults(_ item: PhotosPickerItem?, isCover: Bool) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let dir = try workDir()
                let filename = await item.itemIdentifier()
                let dstUrl = dir.appendingPathComponent(filename)
                
                try? FileManager.default.removeItem(at: dstUrl)
                try data.write(to: dstUrl)
                
                if isCover {
                    coverUrl = dstUrl
                } else {
                    videoUrl = dstUrl
                    startConvert()
                }
            }
        } catch {
            alertMsg = "读取选取的项目失败：\(error.localizedDescription)"
            showAlert = true
        }
    }
    
    // 合成 Live Photo, 并保存到相册
    private func startConvert() {
        guard let cover = coverUrl, let video = videoUrl else { return }
        isProcessing = true
        
        let helper = LivePhotoHelper()
        helper.saveLivePhoto(cover, videoUrl: video) { success, error in
            DispatchQueue.main.async {
                isProcessing = false
                alertMsg = success ? "实况照片已保存 🎉" :
                (error?.localizedDescription ?? "实况照片合成失败 ❌")
                showAlert = true
            }
        }
    }
}

private extension PhotosPickerItem {
    func itemIdentifier() async -> String {
        if let utType = self.supportedContentTypes.first {
            let ext = utType.preferredFilenameExtension ?? "bin"
            return UUID().uuidString + "." + ext
        }
        return UUID().uuidString
    }
}

// MARK: - 临时文件管理工具
private let workDirName = "LivePhotoWork"

private func workDir() throws -> URL {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(workDirName, isDirectory: true)
    if !FileManager.default.fileExists(atPath: base.path) {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    }
    return base
}

private func cleanupWorkDir() {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(workDirName, isDirectory: true)
    try? FileManager.default.removeItem(at: base)
    print("♻️ 清理缓存：\(base.path)")
}

// MARK: - 预览
struct LivePhotoConverterView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            LivePhotoConverterView()
        }
    }
}
