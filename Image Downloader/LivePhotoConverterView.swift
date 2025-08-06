//
//  LivePhotoConverterView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2025/8/6.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LivePhotoConverterView: View {
    @Environment(\.presentationMode) private var presentationMode
    
    @State private var showCoverPicker = false
    @State private var showVideoPicker = false
    
    @State private var coverUrl: URL?
    @State private var videoUrl: URL?
    
    @State private var isProcessing = false
    @State private var alertMsg    = ""
    @State private var showAlert   = false
    
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
        .onAppear { if coverUrl == nil { showCoverPicker = true } } // 进入页面时, 立即选择封面
        .sheet(isPresented: $showCoverPicker) { coverPicker }
        .sheet(isPresented: $showVideoPicker) { videoPicker }
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
    
    // 封面 & 视频 Picker
    private var coverPicker: some View {
        ImagePicker(configuration: {
            var cfg = PHPickerConfiguration(photoLibrary: .shared())
            cfg.filter = .images; cfg.selectionLimit = 1; return cfg
        }(), isPresented: $showCoverPicker) { results in
            handlePickerResults(results, isCover: true)
        }
    }
    private var videoPicker: some View {
        ImagePicker(configuration: {
            var cfg = PHPickerConfiguration(photoLibrary: .shared())
            cfg.filter = .videos; cfg.selectionLimit = 1; return cfg
        }(), isPresented: $showVideoPicker) { results in
            handlePickerResults(results, isCover: false)
        }
    }
    
    // 处理选取结果
    private func handlePickerResults(_ results: [PHPickerResult], isCover: Bool) {
        guard let item = results.first else { return }
        let typeID = isCover ? UTType.image.identifier : UTType.movie.identifier
        item.itemProvider.loadFileRepresentation(forTypeIdentifier: typeID) { tmpUrl, _ in
            guard let tmpUrl = tmpUrl else { return }
            let dstUrl = FileManager.default.temporaryDirectory
                .appendingPathComponent(tmpUrl.lastPathComponent)
            try? FileManager.default.removeItem(at: dstUrl)
            try? FileManager.default.copyItem(at: tmpUrl, to: dstUrl)
            DispatchQueue.main.async {
                if isCover {
                    coverUrl = dstUrl // 选封面 👉 等待「下一步」
                } else {
                    videoUrl = dstUrl // 选视频 👉 立即合成
                    startConvert()
                }
            }
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

// ImagePicker 组件, 用于选择封面或视频
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

struct LivePhotoConverterView_Previews: PreviewProvider {
    static var previews: some View {
        LivePhotoConverterView()
    }
}
