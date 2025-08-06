//
//  LivePhotoConverterView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2025/8/6.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// 兼容 iOS 15 的 PHPicker 封装
struct ImagePicker: UIViewControllerRepresentable {
    let configuration: PHPickerConfiguration
    @Binding var isPresented: Bool
    var onCompletion: ([PHPickerResult]) -> Void
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: ImagePicker
        init(_ parent: ImagePicker) { self.parent = parent }
        
        func picker(_ picker: PHPickerViewController,
                    didFinishPicking results: [PHPickerResult]) {
            parent.isPresented = false
            parent.onCompletion(results)
        }
    }
}

struct LivePhotoConverterView: View {
    
    // Picker states
    @State private var showCoverPicker = false
    @State private var showVideoPicker = false
    
    @State private var coverUrl: URL?
    @State private var videoUrl: URL?
    @State private var coverThumbnail: Image?
    
    // Progress & Alerts
    @State private var isSaving = false
    @State private var showResultAlert = false
    @State private var saveSucceeded = false
    @State private var errorMessage: String?
    
    // Helper instance
    private let helper = LivePhotoHelper()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                
                // 1️⃣ 实况封面选择按钮、实况封面预览
                Button(action: { showCoverPicker = true }) {
                    HStack {
                        Image(systemName: "photo")
                        Text(coverUrl == nil ? "选择实况封面" : "重新选择封面")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showCoverPicker) {
                    ImagePicker(configuration: photoConfig,
                                isPresented: $showCoverPicker,
                                onCompletion: handleCoverPicked)
                }
                
                if let thumbnail = coverThumbnail {
                    thumbnail
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                }
                
                // 2️⃣ 实况视频选择按钮
                Button(action: { showVideoPicker = true }) {
                    HStack {
                        Image(systemName: "video")
                        Text(videoUrl == nil ? "选择实况视频" : "重新选择视频")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showVideoPicker) {
                    ImagePicker(configuration: videoConfig,
                                isPresented: $showVideoPicker,
                                onCompletion: handleVideoPicked)
                }
                
                // 3️⃣ 保存 Live Photo
                Button(action: saveLivePhoto) {
                    Label("保存为「实况图片」", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!readyToSave)
                
                if isSaving {
                    ProgressView("保存中...")
                        .padding(.top, 8)
                }
                
                Spacer()
            }
            .padding()
            .alert(isPresented: $showResultAlert) {
                if saveSucceeded {
                    return Alert(
                        title: Text("✅ 已保存"),
                        message: Text("实况图片已保存至系统相册。"),
                        dismissButton: .default(Text("好的"))
                    )
                } else {
                    return Alert(
                        title: Text("❌ 保存失败"),
                        message: Text(errorMessage ?? "未知错误"),
                        dismissButton: .default(Text("知道了"))
                    )
                }
            }
        } // NavigationView
        .navigationBarTitle("实况图片转换器", displayMode: .inline)
    }
}

// Picker configurations
private extension LivePhotoConverterView {
    // 只允许选 1 张图片
    var photoConfig: PHPickerConfiguration {
        var cfg = PHPickerConfiguration()
        cfg.selectionLimit = 1
        cfg.filter = .images
        return cfg
    }
    
    // 只允许选 1 段视频
    var videoConfig: PHPickerConfiguration {
        var cfg = PHPickerConfiguration()
        cfg.selectionLimit = 1
        cfg.filter = .videos
        return cfg
    }
}

// Helper actions
private extension LivePhotoConverterView {
    
    var readyToSave: Bool { coverUrl != nil && videoUrl != nil && !isSaving }
    
    // 处理选中的实况封面
    func handleCoverPicked(_ results: [PHPickerResult]) {
        guard let first = results.first else { return }
        copyMediaPicked(from: first, preferredUTI: .image) { url in
            coverUrl = url
            if let data = try? Data(contentsOf: url),
               let uiImg = UIImage(data: data) {
                coverThumbnail = Image(uiImage: uiImg)
            }
        }
    }
    
    // 处理选中的实况视频
    func handleVideoPicked(_ results: [PHPickerResult]) {
        guard let first = results.first else { return }
        copyMediaPicked(from: first, preferredUTI: .movie) { url in
            videoUrl = url
        }
    }
    
    // 复制一份选中的封面或视频, 存放到临时目录, 并返回其 URL
    // @param result:       选择器回调的 PHPickerResult
    // @param preferredUTI: 期望的 UTType，例如 .image 或 .movie
    // @param completion:   返回本地可读写的 URL
    func copyMediaPicked(from result: PHPickerResult,
                   preferredUTI: UTType,
                   completion: @escaping (URL) -> Void) {
        
        let provider = result.itemProvider
        
        // 先找一个 provider 能满足的 UTI
        let typeIdentifier: String
        if provider.hasItemConformingToTypeIdentifier(preferredUTI.identifier) {
            typeIdentifier = preferredUTI.identifier
        } else {
            // 退而求其次, 用它能提供的第一个类型
            typeIdentifier = provider.registeredTypeIdentifiers.first!
        }
        
        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            guard let srcUrl = url else {
                print("⚠️ 实况封面或视频 loadFileRepresentation 失败: ", error ?? "未知错误")
                return
            }
            
            // 复制到临时目录, 并保留其扩展名
            let destUrl = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(srcUrl.pathExtension)
            
            do {
                try FileManager.default.copyItem(at: srcUrl, to: destUrl)
                DispatchQueue.main.async { completion(destUrl) }
            } catch {
                print("⚠️ 实况封面或视频复制到临时目录失败: ", error)
            }
        }
    }
    
    // 调用 Live Photo Helper 接口, 保存 Live Photo
    func saveLivePhoto() {
        guard let cUrl = coverUrl, let vUrl = videoUrl else { return }
        isSaving = true
        helper.saveLivePhoto(cUrl, videoUrl: vUrl) { success, error in
            DispatchQueue.main.async {
                isSaving = false
                saveSucceeded = success
                errorMessage = error?.localizedDescription
                showResultAlert = true
                
                // 删除临时文件
                if success {
                    try? FileManager.default.removeItem(at: cUrl)
                    try? FileManager.default.removeItem(at: vUrl)
                    coverUrl = nil
                    videoUrl = nil
                    coverThumbnail = nil
                }
            }
        }
    }
}

struct LivePhotoConverterView_Previews: PreviewProvider {
    static var previews: some View {
        LivePhotoConverterView()
    }
}
