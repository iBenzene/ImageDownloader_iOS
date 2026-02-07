//
//  LogManager.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2024/2/8.
//  Copyright (c) 2024 iBenzene. All rights reserved.
//

import SwiftUI

// Log levels for categorizing log messages
enum LogLevel: Int, Comparable, CaseIterable {
    case debug = 0
    case info = 1
    case warn = 2
    case error = 3
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    var emoji: String {
        switch self {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warn: return "⚠️"
        case .error: return "❌"
        }
    }
    
    var displayName: String {
        switch self {
        case .debug: return "调试"
        case .info: return "标准"
        case .warn: return "警告"
        case .error: return "错误"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}

// A single log entry
struct LogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    init(level: LogLevel, message: String) {
        self.id = UUID()
        self.timestamp = Date()
        self.level = level
        self.message = message
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(timestamp) {
            formatter.dateFormat = "今天 HH:mm"
        } else if calendar.isDateInYesterday(timestamp) {
            formatter.dateFormat = "昨天 HH:mm"
        } else if calendar.isDate(timestamp, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM/dd HH:mm"
        } else {
            formatter.dateFormat = "yyyy/MM/dd HH:mm"
        }
        
        return formatter.string(from: timestamp)
    }
}

// Centralized log manager for collecting and displaying logs
class LogManager: ObservableObject {
    static let shared = LogManager()
    
    // Maximum number of logs to keep in memory
    private let maxLogCount = 500
    
    // All collected logs
    @Published private(set) var logs: [LogEntry] = []
    
    // Display level stored in UserDefaults (only affects display, not collection)
    @AppStorage("logDisplayLevel") var displayLevel: Int = 1
    
    private init() {}
    
    // Log a message with the specified level
    func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(level: level, message: message)
        
        // Print to Xcode console
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: entry.timestamp)
        print("[\(timestamp)] \(level.emoji) [\(level.displayName)] \(message)")
        
        // Store in memory (on main thread for UI updates)
        DispatchQueue.main.async {
            self.logs.append(entry)
            
            // Trim old logs if exceeding max count
            if self.logs.count > self.maxLogCount {
                self.logs.removeFirst(self.logs.count - self.maxLogCount)
            }
        }
    }
    
    // Log a debug message
    func debug(_ message: String) {
        log(.debug, message)
    }
    
    // Log an info message
    func info(_ message: String) {
        log(.info, message)
    }
    
    // Log a warning message
    func warn(_ message: String) {
        log(.warn, message)
    }
    
    // Log an error message
    func error(_ message: String) {
        log(.error, message)
    }
    
    // Get logs filtered by the current display level
    var filteredLogs: [LogEntry] {
        guard let minLevel = LogLevel(rawValue: displayLevel) else {
            return logs
        }
        return logs.filter { $0.level >= minLevel }
    }
    
    // Clear all logs
    func clearLogs() {
        logs.removeAll()
    }
}

// Global convenience functions for logging
func logDebug(_ message: String) {
    LogManager.shared.debug(message)
}

func logInfo(_ message: String) {
    LogManager.shared.info(message)
}

func logWarn(_ message: String) {
    LogManager.shared.warn(message)
}

func logError(_ message: String) {
    LogManager.shared.error(message)
}
