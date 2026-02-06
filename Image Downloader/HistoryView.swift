//
//  HistoryView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/2/6.
//

import SwiftUI

// History View
struct HistoryView: View {
    @ObservedObject private var historyManager = HistoryManager.shared
    @State private var showClearConfirmation = false
    
    var body: some View {
        ZStack {
            // Background gradient for a modern look
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            if historyManager.items.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // History list
                historyListView
            }
        }
        .navigationTitle("下载记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyManager.items.isEmpty {
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .padding(.trailing, 20)
                    }
                }
            }
        }
        .alert("清空下载记录", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    historyManager.clearAll()
                }
            }
        } message: {
            Text("确定要清空所有下载记录吗？此操作无法撤销。")
        }
    }
    
    // Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color("AccentColor"), Color("AccentColor").opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("暂无下载记录")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("下载完成后会自动记录在这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // History List View
    private var historyListView: some View {
        List {
            ForEach(historyManager.items) { item in
                HistoryItemRow(item: item)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .onDelete { offsets in
                withAnimation(.easeInOut(duration: 0.25)) {
                    historyManager.deleteItems(at: offsets)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// History Item Row
struct HistoryItemRow: View {
    let item: HistoryItem
    @State private var isCopied = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            statusIndicator
            
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
                    
                    // Content Type & Count
                    HStack(spacing: 2) {
                        Image(systemName: typeIconName)
                            .font(.caption2)

                        Text("\(item.mediaCount)")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Timestamp
                    Text(item.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
            
            // Copy button
            Button(action: copyToClipboard) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.body)
                    .foregroundColor(isCopied ? .green : Color("AccentColor"))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // Helper to determine icon name
    private var typeIconName: String {
        if item.shortDownloaderName.contains("视频") {
            return "film"
        } else if item.shortDownloaderName.contains("实况") {
            return "livephoto"
        } else {
            return item.mediaCount > 1 ? "photo.stack" : "photo"
        }
    }

    // Status Indicator
    private var statusIndicator: some View {
        ZStack {
            Circle()
                .fill(item.isSuccess ?
                      LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing) :
                        LinearGradient(colors: [.red, .red.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .frame(width: 36, height: 36)
            
            Image(systemName: item.isSuccess ? "checkmark" : "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    // Actions
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
struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            HistoryView()
                .previewDisplayName("Light Mode")
            
            HistoryView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
