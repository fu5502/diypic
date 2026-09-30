# diypic - iOS 录屏自动合成长截图工具

一款类似 **Picsew（皮克秀）** 体验的 iOS 自动滚屏长截图工具。无需单张手动拼接，无需受限于浏览器网页，在手机任意 App（微信聊天、小红书、微博、知乎等）中通过控制中心“屏幕广播”实时滑动，录屏结束后自动无缝拼装为超长图。

---

## 🌟 核心特性

1. **控制中心屏幕广播（ReplayKit Broadcast）**：
   - 采用 iOS 官方 `RPBroadcastSampleHandler` 广播扩展机制。
   - 随时随地从控制中心唤起，在任意第三方 App 界面内滑动即录。
2. **极限制约优化（< 50MB 内存）**：
   - iOS 广播扩展具有极严格的 50MB 内存上限（超标即被系统强制终止）。
   - 本项目通过**帧率动态节流 (12~15fps)**、**竖直特征条降采样**、**一维模板匹配（1D Normalized Cross-Correlation）** 快速估算垂直位移 $\Delta y$。
   - 磁盘流式切片暂存，主 App (SwiftUI) 在独立进程中完成高分辨率 Core Graphics 无缝拼装，绝不 OOM。
3. **备用方案（相册录屏导入）**：
   - 即使不使用广播扩展，也可以直接在系统自带录屏录一段滑动视频，导入 App 自动提取位移并生成长截图。
4. **纯在线编译，无需本地 Mac**：
   - 使用 **XcodeGen** 维护工程结构。
   - 配置 **GitHub Actions (macOS Runner)** 在线自动化编译打包，一键输出 `.ipa` 安装包。

---

## 🚀 在线编译与下载方法

你不需要拥有一台 Mac 电脑，也不需要安装 Xcode：

1. **触发编译**：
   - 每次代码提交（Push 到 `main` 分支）会自动触发编译。
   - 或者进入 GitHub 仓库页面顶部导航栏的 **Actions** -> 选择左侧的 **Build iOS IPA** -> 点击右侧 **Run workflow** 手动触发。
2. **下载 IPA**：
   - 编译完成后（约需 2~3 分钟），点击该次构建记录。
   - 在页面最下方的 **Artifacts** 区域，点击下载 `diypic-unsigned-ipa`。
   - 解压下载的 zip 包即可获得 `diypic_unsigned.ipa`。

---

## 📱 安装到 iPhone 教程（以 Sideloadly 为例）

使用 Windows 电脑配合免费自签工具（如 Sideloadly）即可把 App 免费安装到你的 iPhone：

1. **准备工具**：
   - 电脑安装官方 iTunes（从 Apple 官网下载，非微软商店版）以确保驱动正常。
   - 下载并安装 [Sideloadly](https://sideloadly.io/)（支持 Windows）。
2. **签名并安装**：
   - 用数据线将 iPhone 连接到电脑，在手机上点击“信任此电脑”。
   - 打开 Sideloadly，界面会自动识别到你的设备。
   - 将下载好的 `diypic_unsigned.ipa` 拖拽进 Sideloadly 窗口中。
   - 在 `Apple ID` 输入框中填入你平常用的普通 Apple ID（用于免费临时签名）。
   - 点击 **Start**，等待进度条走完显示 `Done`。
3. **在 iPhone 上信任证书**：
   - 安装完成后，手机桌面上会出现 `diypic` 图标。
   - 打开 iPhone 的 **设置** -> **通用** -> **VPN 与设备管理**。
   - 在“开发者 App”下方点击你的 Apple ID，选择 **信任**。
   - 现在即可正常打开 `diypic`！

---

## 💡 使用步骤（如何截长图）

1. **打开 diypic App**：确保已首次打开过 App（赋予相册权限）。
2. **唤出控制中心**：从 iPhone 屏幕右上角向下滑动打开控制中心。
3. **长按录屏图标**：长按带有双圆环的“屏幕录制”快捷图标。
4. **选择广播服务**：在弹出的列表中勾选 **「diypic 滚动截屏」**，并点击 **「开始直播」**。
5. **滑动截取**：倒数 3 秒后，切换至你需要截长图的 App（例如微信聊天界面），**匀速平稳地向下滑动**。
6. **停止并合成**：截取完成后，点击屏幕顶部灵动岛/红色药丸状态栏停止录屏。
7. **查看与保存**：返回 `diypic` App，界面会自动弹出已合成的长图，支持双指自由缩放预览，一键保存至系统相册或分享！

---

## 📂 项目结构

```
diypic/
├── .github/workflows/
│   └── build.yml               # GitHub Actions macOS 在线编译工作流
├── project.yml                 # XcodeGen 描述文件 (App + Extension + App Groups)
├── Shared/
│   ├── Models.swift            # 共享数据模型 (CaptureSession, FrameRecord)
│   └── MotionEstimator.swift   # 轻量级一维垂直滚动位移估算引擎 (CV)
├── diypic/                     # 主 App 源码 (SwiftUI)
│   ├── App/DiyPicApp.swift     # 应用入口
│   ├── Views/ContentView.swift # 主界面与控制中心使用引导
│   ├── Views/StitchResultView.swift # 长图查看器与相册保存
│   ├── Services/StitchEngine.swift  # 图像拼装与视频解析服务
│   ├── Services/SharedDataManager.swift # App Group 数据中继
│   ├── Resources/Info.plist    # 权限配置
│   └── diypic.entitlements      # App Group 共享配置
└── diypicBroadcast/            # ReplayKit 广播扩展源码
    ├── SampleHandler.swift     # 屏幕流捕获处理与内存控制
    ├── Resources/Info.plist    # 扩展点声明 (broadcast-services-upload)
    └── diypicBroadcast.entitlements
```
