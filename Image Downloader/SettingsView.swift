//
//  SettingsView.swift
//  Image Downloader
//
//  Created by 邱想想 on 2024/6/14.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage("xhsCookie") private var xhsCookie: String = ""
    @AppStorage("weiboCookie") private var weiboCookie: String = ""
    @AppStorage("weiboCookiesPoolUrl") private var weiboCookiesPoolUrl: String = ""
    
    var body: some View {
        List {
            Section(header: Text("小红书 Cookie").textCase(nil), footer: Text("小红书 Cookie 仅用于下载视频。")) {
                TextField("请输入 Cookie", text: $xhsCookie)
            }
            
            Section(header: Text("微博 Cookie").textCase(nil)) {
                TextField("请输入 Cookie", text: $weiboCookie)
            }
            
            Section(header: Text("微博 Cookies 池").textCase(nil), footer: Text("微博 Cookies 池仅接受符合特定格式的 JSON 数据，并且会覆盖「微博 Cookie」中填写的内容。")) {
                TextField("请输入 Cookies 池的 URL", text: $weiboCookiesPoolUrl)
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
