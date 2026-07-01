//
//  SettingsView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2024/6/14.
//  Copyright (c) 2024 iBenzene. All rights reserved.
//

import SwiftUI
#if targetEnvironment(macCatalyst)
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @AppStorage("serverUrl") private var serverUrl: String = ""
    @AppStorage("serverToken") private var serverToken: String = ""
    @AppStorage("saveLinksOnly") private var saveLinksOnly: Bool = false
    @AppStorage("incrementalSync") private var incrementalSync: Bool = true
    @AppStorage("serverSideProxy") private var serverSideProxy: Bool = false
    @AppStorage("preheatResources") private var preheatResources: Bool = false
    @AppStorage("logDisplayLevel") private var logDisplayLevel: Int = 1
    @AppStorage(MacDownloadPreference.storageKey) private var macDownloadDirectoryPath: String = ""
    @AppStorage("macSaveToPhotoLibrary") private var macSaveToPhotoLibrary: Bool = false
    #if targetEnvironment(macCatalyst)
    @State private var isChoosingDownloadDirectory = false
    #endif

    var body: some View {
        List {
            Section(header: Text("服务端地址").textCase(nil), footer: Text("必须部署服务端才能使用下载功能。")) {
                TextField("请输入服务端地址", text: $serverUrl)
            }

            Section(header: Text("服务端令牌").textCase(nil), footer: Text("令牌必须与服务端中的设置保持一致。")) {
                TextField("请输入服务端令牌", text: $serverToken)
            }
            
            Section(header: Text("网络").textCase(nil), footer: Text("开启「服务端代理」后，将由服务端代为下载资源。")) {
                Toggle(isOn: $serverSideProxy) {
                    SettingsRowLabel("服务端代理", systemImage: "network")
                }
                .macSwitchToggleStyle()
            }
            
            Section(header: Text("收藏模式").textCase(nil), footer: Text("在「收藏模式」下，首页的「下载」按钮将被替换为「收藏」，仅提取并保存有效链接，而不下载资源。" + (saveLinksOnly ? "开启「资源预热」后，收藏链接时将自动通过服务端缓存资源。" : ""))) {
                Toggle(isOn: $saveLinksOnly) {
                    SettingsRowLabel("仅保存链接", systemImage: "link")
                }
                .macSwitchToggleStyle()
                if saveLinksOnly {
                    Toggle(isOn: $preheatResources) {
                        SettingsRowLabel("资源预热", systemImage: "flame.fill")
                    }
                    .macSwitchToggleStyle()
                }
            }

            Section(header: Text("同步").textCase(nil), footer: Text("开启「增量同步」后，将仅获取自上次同步以来的更新。为节约您的流量，建议保持开启状态。")) {
                Toggle(isOn: $incrementalSync) {
                    SettingsRowLabel("增量同步", systemImage: "arrow.triangle.2.circlepath")
                }
                .macSwitchToggleStyle()
            }

            #if targetEnvironment(macCatalyst)
            Section(header: Text("下载").textCase(nil)) {
                Toggle(isOn: $macSaveToPhotoLibrary) {
                    SettingsRowLabel("保存至相册", systemImage: "photo.on.rectangle")
                }
                .macSwitchToggleStyle()

                if !macSaveToPhotoLibrary {
                    HStack {
                        SettingsRowLabel("保存位置", systemImage: "square.and.arrow.down.on.square")

                        TextField("默认：\(MacDownloadPreference.defaultDirectoryPath)", text: $macDownloadDirectoryPath)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)

                        Button {
                            isChoosingDownloadDirectory = true
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }
                        .buttonStyle(.borderless)
                        .help("选择文件夹")

                        if hasCustomDownloadDirectory {
                            Button {
                                macDownloadDirectoryPath = ""
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("恢复默认")
                        }
                    }
                }
            }
            #endif
            
            Section(header: Text("日志").textCase(nil), footer: Text("如果遇到问题，可以查看日志以获取更多信息。")) {
                Picker(selection: $logDisplayLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                } label: {
                    SettingsRowLabel("日志等级", systemImage: "line.3.horizontal.decrease.circle")
                }
                
                NavigationLink(destination: LogsView()) {
                    SettingsRowLabel("查看日志", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationTitle("设置")
        #if targetEnvironment(macCatalyst)
        .fileImporter(
            isPresented: $isChoosingDownloadDirectory,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleDownloadDirectorySelection(result)
        }
        #endif
        #if !targetEnvironment(macCatalyst)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var hasCustomDownloadDirectory: Bool {
        !macDownloadDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func handleDownloadDirectorySelection(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first else {
            return
        }

        macDownloadDirectoryPath = url.path
    }
    #endif
}

private struct SettingsRowLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            titleText
        } icon: {
            iconImage
        }
    }

    @ViewBuilder
    private var titleText: some View {
        #if targetEnvironment(macCatalyst)
        Text(title)
            .font(.body)
        #else
        Text(title)
        #endif
    }

    @ViewBuilder
    private var iconImage: some View {
        #if targetEnvironment(macCatalyst)
        Image(systemName: systemImage)
            .font(.body)
        #else
        Image(systemName: systemImage)
        #endif
    }
}

// 预览
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

private extension View {
    @ViewBuilder
    func macSwitchToggleStyle() -> some View {
        #if targetEnvironment(macCatalyst)
        self.toggleStyle(SwitchToggleStyle(tint: Color("AccentColor")))
        #else
        self
        #endif
    }
}
