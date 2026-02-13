#  苯苯存图

🚫 图片不让保存？

🤯 想要保存的图片太多？受够了一个个点击「加载原图」👉「保存图片」 的繁琐步骤？

💦 保存的图片有水印？

❤️ 或许「**苯苯存图**」可以帮助你～

<div align=center>
  <img src="https://cdn.ibenzene.net/image-downloader/Preview_iOS.png" alt="预览图" width="30%"></img>
</div>


## 快速开始

### 爱思助手侧载

**步骤一**  使用你的电脑，下载 App 的 iPA 安装包。

**步骤二**  打开「爱思助手」，点击顶部栏的「工具箱」，找到「iPA 签名」工具。

**步骤三**  点击「添加 iPA 文件」，选择刚刚下载好的 iPA 安装包进行添加。

**步骤四**  点击「添加 Apple ID」，使用你的 Apple ID 对该 iPA 安装包进行签名。

**步骤五**  勾选刚刚添加的 iPA 安装包以及 Apple ID，点击「开始签名」。

**步骤六**  签名成功后，使用数据线连接你的 iPhone，点击顶部栏的「我的设备」，接着点击侧边栏的「应用游戏」，然后点击「导入安装」，选择刚刚签名完成的 iPA 安装包，导入到你的 iPhone 中进行安装。

**步骤七**  打开你 iPhone 上的设置 App，在「隐私与安全性」界面中拉到底部，找到「开发者模式」，打开其开关。

**步骤八**  在「通用」👉「VPN 与设备管理」👉「开发者 App」中找到你的 Apple ID，对你自己的签名进行信任。

🥰 然后就可以正常使用 App 啦～

⚠️ 不过需要注意的是，这种方式的签名有效期为 **七天**，到期了需要重新签名，也就是得重新过一遍以上的步骤。

### SideStore 侧载（推荐）

**步骤一**  使用你的电脑，在「🔗 [SideStore 官网](https://sidestore.io/#get-started)」下载必要的文件，包括 AltServer（AltStore 是另一个侧载服务商）的安装包、SideStore 的 iPA 安装包以及配对文件生成器。

**步骤二**  按照「🔗 [SideStore 官方文档](https://docs.sidestore.io/docs/intro)」的指导，在 iPhone 上安装好 SideStore。

**步骤三**  打开 SideStore，由底部导航栏的 Sources 进入软件源的编辑页面，添加 https://cdn.ibenzene.net/default/iBzAltSource.json 作为新的下载源。

<div align=center>
  <img src="https://cdn.ibenzene.net/default/SideStore_Guide_1.jpg" alt="SideStore 侧载指导" width="25%"></img>
</div>

**步骤四**  单击进入我们的软件源，下载《苯苯存图》，完成后打开即可使用。

<div align=center>
  <img src="https://cdn.ibenzene.net/default/SideStore_Guide_2.jpg" alt="SideStore 侧载指导" width="25%"></img>
</div>

**步骤五（可选）** 如果对于官方提供的 iPA 自签名服务不放心，可以自行部署 iPA 自签名服务。（🔗 [Anisette Server v3](https://github.com/Dadoum/anisette-v3-server)）

💡 虽然这种方式的签名有效期也为七天，但是到期之前 **仅需在手机上** 自动续签即可，无需电脑！（签名服务由官方或者你自己部署的 Anisette Server 提供）

## 服务端部署

⚠️ 自 v0.2.0 更新以来，为了便于项目的维护，我们将前端中与 UI 无关的代码分离开来，作为独立的服务端，你需要单独部署。

🔗 [服务端项目](https://github.com/iBenzene/ImageDownloader_Server)

## 支持功能

✅ 输入单个或多个链接，批量保存小红书图片、**实况图片** 或视频。

✅ 输入单个或多个链接，批量保存米游社图片。

✅ 输入单个或多个链接，批量保存微博图片。

✅ 输入单个或多个链接，批量保存 Pixiv 图片。（可选择让服务端代理下载）

✅ 自由地使用一张图片和一段视频合成「实况图片」。

## 计划支持

🚧 输入单个或多个链接，批量保存哔哩哔哩视频。（预计下个版本支持）

🚧 允许将图片或视频保存到云盘，节省手机存储空间。（计划支持协议：WebDAV）

🚧 输入单个或多个链接，批量保存抖音视频。
