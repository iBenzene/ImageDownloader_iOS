//
//  LogsView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2024/2/8.
//  Copyright (c) 2024 iBenzene. All rights reserved.
//

import SwiftUI

struct LogsView: View {
    @ObservedObject private var logManager = LogManager.shared
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
            
            if logManager.filteredLogs.isEmpty {
                // Empty state
                emptyStateView
            } else {
                // Logs list
                logsListView
            }
        }
        .navigationBarTitle("日志", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !logManager.logs.isEmpty {
                    Button(action: {
                        showClearConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("清空日志", isPresented: $showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    logManager.clearLogs()
                }
            }
        } message: {
            Text("确定要清空所有日志吗？此操作无法撤销。")
        }
        .toolbar(.hidden, for: .tabBar)
    }
    
    // Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(("AccentColor")), Color(("AccentColor")).opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("暂无日志")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Text("执行操作后日志会显示在这里")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
    
    // Logs List View
    private var logsListView: some View {
        List {
            ForEach(logManager.filteredLogs.reversed()) { entry in
                NavigationLink(destination: LogDetailView(entry: entry)) {
                    LogItemRow(entry: entry)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

// Log Item Row
struct LogItemRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Level indicator
            levelIndicator
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Message (truncated)
                Text(entry.message)
                    .font(.system(.subheadline))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                
                // Metadata row
                HStack(spacing: 8) {
                    // Level badge
                    Text(entry.level.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(entry.level.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(entry.level.color.opacity(0.15))
                        )
                    
                    Spacer()
                    
                    // Timestamp
                    Text(entry.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // Level Indicator
    private var levelIndicator: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [entry.level.color, entry.level.color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 36, height: 36)
            
            Image(systemName: levelIconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
        }
    }
    
    private var levelIconName: String {
        switch entry.level {
        case .debug: return "magnifyingglass"
        case .info: return "info"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark"
        }
    }
}

// Log Detail View
struct LogDetailView: View {
    let entry: LogEntry
    @State private var isCopied = false
    
    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(.systemBackground), Color(.systemGray6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            // Level indicator
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [entry.level.color, entry.level.color.opacity(0.7)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: levelIconName)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.level.displayName)
                                    .font(.headline)
                                    .foregroundColor(entry.level.color)
                                
                                Text(fullDateFormatter.string(from: entry.timestamp))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                    )
                    
                    // Message card
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("日志内容")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button(action: copyToClipboard) {
                                HStack(spacing: 4) {
                                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                                        .font(.caption)
                                    Text(isCopied ? "已复制" : "复制")
                                        .font(.caption)
                                }
                                .foregroundColor(isCopied ? .green : Color("AccentColor"))
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text(entry.message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                            .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 2)
                    )
                    
                    Spacer()
                }
                .padding()
            }
        }
        .navigationBarTitle("日志详情", displayMode: .inline)
        .toolbar(.hidden, for: .tabBar)
    }
    
    private var levelIconName: String {
        switch entry.level {
        case .debug: return "magnifyingglass"
        case .info: return "info"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark"
        }
    }
    
    private func copyToClipboard() {
        UIPasteboard.general.string = entry.message
        
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}

// 预览
struct LogsView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                LogsView()
            }
            .previewDisplayName("Light Mode")
            
            NavigationStack {
                LogsView()
            }
            .preferredColorScheme(.dark)
            .previewDisplayName("Dark Mode")
        }
    }
}
