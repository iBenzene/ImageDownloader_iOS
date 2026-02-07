//
//  SettingsView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2024/6/14.
//  Copyright (c) 2024 iBenzene. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("backendUrl") private var backendUrl: String = ""
    @AppStorage("backendToken") private var backendToken: String = ""
    @AppStorage("saveLinksOnly") private var saveLinksOnly: Bool = false
    @AppStorage("logDisplayLevel") private var logDisplayLevel: Int = 1

    var body: some View {
        List {
            Section(header: Text("服务端地址").textCase(nil), footer: Text("必须部署服务端才能使用下载功能。")) {
                TextField("请输入服务端地址", text: $backendUrl)
            }

            Section(header: Text("服务端令牌").textCase(nil), footer: Text("令牌必须与服务端中的设置保持一致。")) {
                TextField("请输入服务端令牌", text: $backendToken)
            }
            
            Section(header: Text("收藏模式").textCase(nil), footer: Text("开启后，首页的「下载」按钮将被替换为「收藏」，仅提取并保存有效链接而不下载资源。")) {
                Toggle("仅保存链接", isOn: $saveLinksOnly)
            }
            
            Section(header: Text("日志").textCase(nil), footer: Text("如果遇到问题，可以查看日志以获取更多信息。")) {
                Picker(selection: $logDisplayLevel) {
                    ForEach(LogLevel.allCases, id: \.rawValue) { level in
                        Text(level.displayName).tag(level.rawValue)
                    }
                } label: {
                    Label("日志等级", systemImage: "line.3.horizontal.decrease.circle")
                }
                
                NavigationLink(destination: LogsView()) {
                    Label("查看日志", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .navigationBarTitle("设置", displayMode: .inline)
    }
}

// 预览
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
