//
//  SavedLinksView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/7.
//

import SwiftUI

// Saved Links View
struct SavedLinksView: View {
    @ObservedObject private var savedLinksManager = SavedLinksManager.shared
    @State private var showClearConfirmation = false
    
    // Batch Download State
    @State private var isBatchDownloading = false
    @State private var batchTotal = 0
    @State private var batchCurrent = 0
    
    var body: some View {
        ZStack {
            // Background gradient for a modern look
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if savedLinksManager.items.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Saved links list
                savedLinksListView
            }
        }
        .navigationTitle("已收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Left: Download All Button
            ToolbarItem(placement: .navigationBarLeading) {
                if !savedLinksManager.items.isEmpty {
                    if isBatchDownloading {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("\(batchCurrent) / \(batchTotal)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 20)
                    } else {
                        Button(action: downloadAll) {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(Color("AccentColor"))
                                .padding(.leading, 18)
                        }
                        // Only enable if there are items that need downloading
                        .disabled(savedLinksManager.items.allSatisfy { $0.status == .success })
                        .opacity(savedLinksManager.items.allSatisfy { $0.status == .success } ? 0.5 : 1.0)
                    }
                }
            }
            
            // Right: Clear All Button
            ToolbarItem(placement: .navigationBarTrailing) {
                if !savedLinksManager.items.isEmpty {
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(.trailing, 20)
                    }
                    .disabled(isBatchDownloading)
                    .opacity(isBatchDownloading ? 0.5 : 1.0)
                }
            }
        }
        .alert("清空已收藏链接", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    savedLinksManager.clearAll()
                }
            }
        } message: {
            Text("确定要清空所有已收藏链接吗？此操作无法撤销。")
        }
    }
    
    private func downloadAll() {
        // Filter items that are not successful (none or failure)
        let itemsToDownload = savedLinksManager.items.filter { $0.status != .success }
        
        guard !itemsToDownload.isEmpty else { return }
        
        withAnimation {
            isBatchDownloading = true
            batchTotal = itemsToDownload.count
            batchCurrent = 0
        }
        
        Task {
            for (index, item) in itemsToDownload.enumerated() {
                // Update progress UI
                await MainActor.run {
                    batchCurrent = index + 1
                }
                
                // Double check status in case it changed during the process
                let currentItem = savedLinksManager.items.first(where: { $0.id == item.id })
                if currentItem?.status == .success { continue }
                
                guard let url = URL(string: item.url) else {
                    await MainActor.run {
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .failure)
                    }
                    continue
                }
                
                let type = ImageDownloaderType(rawValue: item.downloaderType) ?? .xhsImg
                
                // Perform download (ignoring progress callback for individual items in batch mode to keep UI clean,
                // or we could show it somewhere else, but global progress is likely enough)
                let result = await DownloadManager.shared.downloadMedia(
                    urls: [url],
                    downloaderType: type
                ) { _ in }
                
                // Update status
                await MainActor.run {
                    switch result {
                    case .success:
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .success)
                    case .failure:
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .failure)
                    }
                }
                
                // Small delay to be nice to system/network
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s pause
            }
            
            // Finish
            await MainActor.run {
                withAnimation {
                    isBatchDownloading = false
                    batchCurrent = 0
                    batchTotal = 0
                }
            }
        }
    }
    
    // Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color("AccentColor"), Color("AccentColor").opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("暂无已收藏链接")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("开启「收藏模式」后\n保存的链接会显示在这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // Saved Links List View
    private var savedLinksListView: some View {
        List {
            ForEach(savedLinksManager.items) { item in
                SavedLinkItemRow(item: item)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                withAnimation(.easeInOut(duration: 0.25)) {
                    savedLinksManager.deleteItems(at: offsets)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// Saved Link Item Row
struct SavedLinkItemRow: View {
    let item: SavedLinkItem
    @State private var isCopied = false
    
    // Active download state (ephemeral)
    @State private var isDownloading = false
    @State private var downloadProgress = ""
    
    var body: some View {
        HStack(spacing: 12) {
            // Left Status Icon
            statusIcon
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // URL (truncated)
                Text(item.url)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                
                // Metadata row
                HStack(spacing: 8) {
                    // Downloader type badge
                    Text(item.shortDownloaderName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color("AccentColor"))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color("AccentColor").opacity(0.15))
                        )
                    
                    if isDownloading {
                        Text(downloadProgress)
                            .font(.caption2)
                            .foregroundColor(.orange)
                    } else {
                        // Timestamp
                        Text(item.formattedDate)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 0)
            
            // Action Buttons
            HStack(spacing: 12) {
                // Reset Button (only shown after download attempt)
                if !isDownloading && (item.status == .success || item.status == .failure) {
                    Button(action: resetStatus) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.body)
                            .foregroundColor(.gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                
                // Download Button
                if !isDownloading && item.status == .none {
                    Button(action: downloadItem) {
                        Image(systemName: "arrow.down.circle")
                            .font(.body)
                            .foregroundColor(Color("AccentColor"))
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                
                // Copy button
                Button(action: copyToClipboard) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.body)
                        .foregroundColor(isCopied ? .green : Color("AccentColor"))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // Status Icon Logic
    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            if isDownloading {
                // Spinning Loading Icon
                Circle()
                    .stroke(Color("AccentColor").opacity(0.3), lineWidth: 3)
                    .frame(width: 36, height: 36)
                
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color("AccentColor")))
                    .scaleEffect(0.8)
            } else {
                switch item.status {
                case .none:
                    // Default Link Icon
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color("AccentColor"), Color("AccentColor").opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        
                case .success:
                    // Success Checkmark
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        
                case .failure:
                    // Failure Xmark
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.red, .red.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    // Actions
    private func downloadItem() {
        Task {
            // Set initial state
            await MainActor.run {
                withAnimation {
                    isDownloading = true
                    downloadProgress = "准备中..."
                }
            }
            
            // Perform download
            guard let url = URL(string: item.url) else {
                await MainActor.run {
                    withAnimation {
                        isDownloading = false
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .failure)
                    }
                }
                return
            }
            
            let type = ImageDownloaderType(rawValue: item.downloaderType) ?? .xhsImg
            
            let result = await DownloadManager.shared.downloadMedia(
                urls: [url],
                downloaderType: type
            ) { progress in
                Task { @MainActor in
                    withAnimation {
                        downloadProgress = progress.message
                    }
                }
            }
            
            // Handle result
            Task { @MainActor in
                // Small delay to ensure it runs after progress updates
                try? await Task.sleep(nanoseconds: 100_000_000)
                withAnimation {
                    isDownloading = false
                    switch result {
                    case .success:
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .success)
                    case .failure:
                        SavedLinksManager.shared.updateStatus(for: item, newStatus: .failure)
                    }
                }
            }
        }
    }
    
    private func resetStatus() {
        withAnimation {
            SavedLinksManager.shared.updateStatus(for: item, newStatus: .none)
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = item.url
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        // Reset after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

// 预览
struct SavedLinksView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                SavedLinksView()
            }
            .previewDisplayName("Light Mode")
            
            NavigationView {
                SavedLinksView()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
        }
    }
}
