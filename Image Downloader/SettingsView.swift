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

    var body: some View {
        List {
            Section(header: Text("后端地址").textCase(nil), footer: Text("必须部署后端才能使用下载功能。")) {
                TextField("请输入后端地址", text: $backendUrl)
            }

            Section(header: Text("后端令牌").textCase(nil), footer: Text("令牌必须与后端中的设置保持一致。")) {
                TextField("请输入后端令牌", text: $backendToken)
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
