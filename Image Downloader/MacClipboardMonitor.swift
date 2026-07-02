//
//  MacClipboardMonitor.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2026/7/2.
//

import Combine
import UIKit

#if targetEnvironment(macCatalyst)
struct MacClipboardTextRequest: Identifiable, Equatable {
    let id = UUID()
    let text: String
}

final class MacClipboardMonitor: ObservableObject {
    @Published var isListening = false
    @Published var recognizedTextRequest: MacClipboardTextRequest?

    private var timer: Timer?
    private var lastChangeCount = UIPasteboard.general.changeCount
    private let pasteboard: UIPasteboard

    init(pasteboard: UIPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func setListening(_ shouldListen: Bool) {
        guard shouldListen != isListening else { return }

        if shouldListen {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        lastChangeCount = pasteboard.changeCount
        isListening = true

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isListening = false
    }

    private func pollPasteboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }

        lastChangeCount = currentChangeCount

        guard let text = pasteboard.string,
              DownloadManager.shared.hasRecognizedLinks(in: text) else {
            return
        }

        recognizedTextRequest = MacClipboardTextRequest(text: text)
    }

    deinit {
        timer?.invalidate()
    }
}
#endif
