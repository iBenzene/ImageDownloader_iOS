//
//  Image_DownloaderTests.swift
//  Image DownloaderTests
//
//  Created by 埃苯泽 on 2023/12/26.
//

import XCTest
import SwiftUI
@testable import Image_Downloader

final class ResolveProtocol: URLProtocol {
    static var requests: [URL] = []
    static var syncRecords: [SavedLinkItemAPI] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "dedupe.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let endpoint = request.url else {
            respond(withError: URLError(.badURL))
            return
        }

        Self.requests.append(endpoint)

        if endpoint.path.hasSuffix("/sync") {
            handleSyncRequest(for: endpoint)
            return
        }

        handleResolveOrExtractRequest(for: endpoint)
    }

    override func stopLoading() {}

    private func handleSyncRequest(for endpoint: URL) {
        do {
            let response = SavedLinksSyncResponse(
                records: Self.syncRecords,
                syncedAt: "2026-10-27T00:00:00.000Z"
            )
            let data = try JSONEncoder().encode(response)
            respond(statusCode: 200, data: data, for: endpoint)
        } catch {
            respond(withError: error)
        }
    }

    private func handleResolveOrExtractRequest(for endpoint: URL) {
        let components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        let source = components?.queryItems?.first(where: { $0.name == "url" })?.value ?? ""

        if source.contains("offline") {
            respond(withError: URLError(.notConnectedToInternet))
            return
        }

        if source.contains("timeout") {
            respond(withError: URLError(.timedOut))
            return
        }

        let statusCode: Int
        if source.contains("oldserver") {
            statusCode = 404
        } else if source.contains("unauthorized") {
            statusCode = 401
        } else {
            statusCode = 200
        }

        let contentKey: String
        if source.contains("bili") {
            let page = source.contains("p=2") ? 2 : 1
            contentKey = "bilibili:BVtest:p=\(page)"
        } else {
            let noteSuffix = source.contains("unique") ? source : "same"
            contentKey = "xhs:note-\(noteSuffix)"
        }

        let payload: [String: Any]
        if endpoint.path.hasSuffix("/extract") {
            payload = ["mediaUrls": ["https://media.test/image.jpg"]]
        } else {
            payload = ["contentKey": contentKey]
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            respond(statusCode: statusCode, data: data, for: endpoint)
        } catch {
            respond(withError: error)
        }
    }

    private func respond(statusCode: Int, data: Data, for url: URL) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        ) else {
            respond(withError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func respond(withError error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }
}

final class Image_DownloaderTests: XCTestCase {

    private func assertReady(
        _ result: HomeSavePreparation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .ready = result {
            return
        }
        XCTFail("Expected ready, got \(result)", file: file, line: line)
    }

    private func assertDuplicate(
        _ result: HomeSavePreparation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .needsDuplicateConfirmation = result {
            return
        }
        XCTFail("Expected duplicate confirmation, got \(result)", file: file, line: line)
    }

    @MainActor
    func testIsolatedDeduplicationWorkflow() async throws {
        // Never mutate a production application's defaults, even if run with the wrong scheme.
        try XCTSkipUnless(Bundle.main.bundleIdentifier?.contains("DedupeVerification") == true)

        UserDefaults.standard.set("https://dedupe.test/api", forKey: "serverUrl")
        UserDefaults.standard.set("verification", forKey: "serverToken")

        URLProtocol.registerClass(ResolveProtocol.self)
        defer { URLProtocol.unregisterClass(ResolveProtocol.self) }

        let runID = UUID().uuidString
        let manager = SavedLinksManager.shared
        let workflow = DownloadManager.shared
        manager.clearAll()

        // 1. Single and duplicate links preparation & saving
        let linkA = "https://example.test/\(runID)/xhs-a"
        let linkB = "https://example.test/\(runID)/xhs-b"

        assertReady(await workflow.prepareSaveLinks(from: linkA, downloaderType: .xhsImg))
        let saved = await workflow.saveLinks(
            [linkA],
            downloaderType: .xhsImg,
            shouldPreheatResources: false,
            onProgress: { _ in }
        )
        XCTAssertFalse(saved.feedback.isWarning)

        assertDuplicate(await workflow.prepareSaveLinks(from: linkB, downloaderType: .xhsImg))
        XCTAssertEqual(manager.visibleItems.count, 1, "Preparation must not save the candidate")

        manager.clearAll()

        // 2. Batch input deduplication with identical content keys
        assertDuplicate(await workflow.prepareSaveLinks(from: "\(linkA)\n\(linkB)", downloaderType: .xhsImg))
        _ = await workflow.saveLinks(
            [linkA, linkB],
            downloaderType: .xhsImg,
            shouldPreheatResources: false,
            onProgress: { _ in }
        )
        XCTAssertEqual(manager.visibleItems.count, 2)
        XCTAssertEqual(Set(manager.visibleItems.compactMap(\.contentKey)).count, 1)

        manager.clearAll()

        // 3. Multi-page link deduplication (e.g. Bilibili pages)
        let page1 = "https://example.test/\(runID)/bili?p=1"
        let page2 = "https://example.test/\(runID)/bili?p=2"

        assertReady(await workflow.prepareSaveLinks(from: "\(page1)\n\(page2)", downloaderType: .bVid))
        _ = await workflow.saveLinks(
            [page1],
            downloaderType: .bVid,
            shouldPreheatResources: false,
            onProgress: { _ in }
        )
        assertDuplicate(await workflow.prepareSaveLinks(from: "https://example.test/\(runID)/bili-other?p=1", downloaderType: .bVid))
        assertReady(await workflow.prepareSaveLinks(from: page2, downloaderType: .bVid))

        manager.clearAll()

        // 4. Legacy link migration and metadata persistence
        let legacyURL = "https://example.test/\(runID)/legacy"
        manager.addLink(url: legacyURL, downloaderType: ImageDownloaderType.xhsImg.rawValue)
        assertDuplicate(await workflow.prepareSaveLinks(from: linkB, downloaderType: .xhsImg))

        let item = try XCTUnwrap(manager.visibleItems.first)
        XCTAssertNotNil(item.contentKey)

        let persisted = try JSONDecoder().decode(
            [SavedLinkItem].self,
            from: XCTUnwrap(UserDefaults.standard.data(forKey: "savedLinks"))
        )
        XCTAssertEqual(persisted.first(where: { $0.id == item.id })?.contentKey, item.contentKey)
        XCTAssertEqual(SavedLinkItemAPI(from: item).toLocalItem().contentKey, item.contentKey)

        // Remote merge without overwriting local contentKey
        var remote = item
        remote.contentKey = nil
        remote.updatedAt = Date().addingTimeInterval(1)
        manager.merge(remoteRecords: [remote])
        XCTAssertEqual(manager.visibleItems.first?.contentKey, item.contentKey)

        // Serialization compatibility check when contentKey is missing
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        json.removeValue(forKey: "contentKey")
        let decodedWithoutKey = try JSONDecoder().decode(
            SavedLinkItem.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        XCTAssertNil(decodedWithoutKey.contentKey)

        manager.clearAll()

        // 5. Network failures and error degradation
        for failure in ["offline", "timeout", "oldserver", "unauthorized"] {
            let failureURL = "https://example.test/\(runID)/\(failure)"
            assertReady(await workflow.prepareSaveLinks(from: failureURL, downloaderType: .xhsImg))

            let result = await workflow.saveLinks(
                [failureURL],
                downloaderType: .xhsImg,
                shouldPreheatResources: false,
                onProgress: { _ in }
            )
            XCTAssertTrue(result.feedback.isWarning)
            XCTAssertTrue(result.feedback.message?.contains("未完成内容去重") == true)
            XCTAssertTrue(manager.hasActiveLink(url: failureURL))
        }
        XCTAssertEqual(manager.visibleItems.count, 4)

        // 6. Downloaders that do not require server resolution
        let initialRequestCount = ResolveProtocol.requests.count
        let weiboURL = "https://example.test/\(runID)/weibo"

        assertReady(await workflow.prepareSaveLinks(from: weiboURL, downloaderType: .wbImg))
        _ = await workflow.saveLinks(
            [weiboURL],
            downloaderType: .wbImg,
            shouldPreheatResources: false,
            onProgress: { _ in }
        )
        assertDuplicate(await workflow.prepareSaveLinks(from: weiboURL, downloaderType: .wbImg))
        XCTAssertEqual(ResolveProtocol.requests.count, initialRequestCount, "Other downloaders must not resolve")

        let nonResolvingDownloaders: [ImageDownloaderType] = [.mysImg, .wbImg, .pImg, .pUgoira, .xImg, .xVid]
        for downloader in nonResolvingDownloaders {
            let candidate = "https://example.test/\(runID)/other-\(downloader.hashValue)"
            let requestsBefore = ResolveProtocol.requests.count

            assertReady(await workflow.prepareSaveLinks(from: "\(candidate)\n\(candidate)", downloaderType: downloader))
            _ = await workflow.saveLinks(
                [candidate],
                downloaderType: downloader,
                shouldPreheatResources: false,
                onProgress: { _ in }
            )
            assertDuplicate(await workflow.prepareSaveLinks(from: candidate, downloaderType: downloader))
            XCTAssertEqual(ResolveProtocol.requests.count, requestsBefore)
        }

        // 7. Resource preheating
        let preheated = await workflow.saveLinks(
            [weiboURL],
            downloaderType: .wbImg,
            shouldPreheatResources: true,
            onProgress: { _ in }
        )
        XCTAssertFalse(preheated.feedback.isError)
        XCTAssertEqual(
            manager.visibleItems.first(where: { $0.url == weiboURL })?.cachedUrls,
            ["https://media.test/image.jpg"]
        )

        let syncURL = "https://example.test/\(runID)/unique-sync"
        _ = await workflow.prepareSaveLinks(from: syncURL, downloaderType: .xhsImg)
        _ = await workflow.saveLinks(
            [syncURL],
            downloaderType: .xhsImg,
            shouldPreheatResources: false,
            onProgress: { _ in }
        )
        XCTAssertNotNil(manager.visibleItems.first(where: { $0.url == syncURL })?.contentKey)

        // 8. Exercise the client sync pipeline with a simulated HTTP response
        ResolveProtocol.syncRecords = manager.visibleItems.map { SavedLinkItemAPI(from: $0) }
        let beforeSync = Dictionary(uniqueKeysWithValues: manager.visibleItems.map { ($0.id, $0.contentKey) })
        await SavedLinksSyncManager.shared.sync()

        XCTAssertNotNil(manager.lastSyncedAt)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: manager.visibleItems.map { ($0.id, $0.contentKey) }), beforeSync)
        XCTAssertTrue(manager.fetchDirtyRecords().isEmpty)

        // 9. Failed preheat must not hide the incomplete identity check warning
        let failedPreheatURL = "https://example.test/\(runID)/offline-preheat"
        _ = await workflow.prepareSaveLinks(from: failedPreheatURL, downloaderType: .xhsImg)
        let failedPreheat = await workflow.saveLinks(
            [failedPreheatURL],
            downloaderType: .xhsImg,
            shouldPreheatResources: true,
            onProgress: { _ in }
        )
        XCTAssertTrue(failedPreheat.feedback.isError)
        XCTAssertTrue(failedPreheat.feedback.message?.contains("未完成内容去重") == true)

        let validPaths: Set<String> = [
            "/api/v1/resolve",
            "/api/v1/extract",
            "/api/v1/saved-links/sync"
        ]
        XCTAssertTrue(ResolveProtocol.requests.allSatisfy { validPaths.contains($0.path) })

        #if targetEnvironment(macCatalyst)
        // 10. The Mac workflow must reject a second submission while checking
        var state = MacHomeState()
        state.linkInput = "https://example.test/\(runID)/unique-workflow"
        let binding = Binding(get: { state }, set: { state = $0 })

        MacHomeWorkflow.submitCurrentInput(state: binding, saveLinksOnly: true, preheatResources: false)
        let firstID = state.activeWorkflowID
        XCTAssertTrue(state.isDownloading)

        MacHomeWorkflow.submitCurrentInput(state: binding, saveLinksOnly: true, preheatResources: false)
        XCTAssertEqual(state.activeWorkflowID, firstID)

        for _ in 0..<100 where state.isDownloading {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertFalse(state.isDownloading)
        XCTAssertNil(state.activeWorkflowID)
        XCTAssertEqual(
            manager.visibleItems.filter { $0.url == "https://example.test/\(runID)/unique-workflow" }.count,
            1
        )
        #endif

        // 11. Enough old records to exceed the 20-second budget; the next pass must resume
        manager.clearAll()
        let oldURLs = (0..<145).map { "https://example.test/\(runID)/unique-backfill-\($0)" }
        manager.addLinks(urls: oldURLs, downloaderType: ImageDownloaderType.xhsImg.rawValue)

        _ = await workflow.prepareSaveLinks(
            from: "https://example.test/\(runID)/unique-new-pass",
            downloaderType: .xhsImg
        )
        let remaining = manager.visibleItems.filter { $0.contentKey == nil }.count
        XCTAssertGreaterThan(remaining, 0)
        XCTAssertLessThan(remaining, oldURLs.count)

        _ = await workflow.prepareSaveLinks(
            from: "https://example.test/\(runID)/unique-new-pass",
            downloaderType: .xhsImg
        )
        XCTAssertEqual(manager.visibleItems.filter { $0.contentKey == nil }.count, 0)
    }
}
