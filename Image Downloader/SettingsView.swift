//
//  SettingsView.swift
//  Image Downloader
//
//  Created by 埃苯泽 on 2024/6/14.
//  Copyright (c) 2024 iBenzene. All rights reserved.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("xhsCookie") private var xhsCookie: String = ""
    @AppStorage("weiboCookie") private var weiboCookie: String = ""
    @AppStorage("weiboCookiesPoolUrl") private var weiboCookiesPoolUrl: String = ""
    
    // 是否要保存原始质量的视频, 目前仅仅给『小红书图片下载器』使用
    @AppStorage("saveOriginalVideo") private var saveOriginalVideo: Bool = false
    
    var body: some View {
        List {
            
            Section(header: Text("小红书").textCase(nil)) {
                Toggle("保存原始质量的视频", isOn: $saveOriginalVideo)
                    .tint(.accentColor)
            }
            
            if saveOriginalVideo {
                 Section(header: Text("小红书 Cookie").textCase(nil), footer: Text("小红书 Cookie 仅用于下载视频。")) {
                     TextField("请输入 Cookie", text: $xhsCookie)
                 }
            }
            
            // [2025-02-01] 由于发现可以使用游客 Cookie 来访问微博的 API, 所以暂时不需要用户自己设置微博的 Cookie 了
            // Section(header: Text("微博 Cookie").textCase(nil)) {
            //     TextField("请输入 Cookie", text: $weiboCookie)
            // }
            
            // Section(header: Text("微博 Cookies 池").textCase(nil), footer: Text("微博 Cookies 池仅接受符合特定格式的 JSON 数据，并且会覆盖「微博 Cookie」中填写的内容。")) {
            //     TextField("请输入 Cookies 池的 URL", text: $weiboCookiesPoolUrl)
            // }
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
