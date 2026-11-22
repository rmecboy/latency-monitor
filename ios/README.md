# 网络延迟悬浮窗（iPadOS / iOS 画中画版）

专为 **iPad mini 5**（兼容 iPadOS / iOS 15.0+）打造的原生 Swift 画中画悬浮窗应用。

## 核心特性
- **系统级画中画真悬浮窗（`AVPictureInPictureController`）**：返回桌面或切换任意 App / 游戏后依然悬浮置顶，双指捏合可缩到极小，可拖到任意角落或贴边隐藏。
- **不打断媒体播放**：音频会话配置为 `.mixWithOthers`，悬浮期间不会暂停你的音乐、B站、YouTube 或游戏声音。
- **3 种悬浮样式，随时切换**：
  - **极简纯地域**（默认）：仅显示状态圆点 + 地域（如 `● 日本·东京`），体积最小；
  - **迷你一行条**：单行显示 `● 日本·东京 | G 42 CF 18 OCI 115`；
  - **详细卡片**：完整显示 Google / Cloudflare / Oracle 毫秒延迟（`< 800ms` 绿、`800~1500ms` 黄、`> 1500ms` 或超时红）与地域。
  - **快捷切换**：在画中画浮窗中轻点中间按钮，即可直接在「极简纯地域」与「详细卡片」间切换！
- **多源地域识别（无 IP）**：内置 5 源容错与中文地名映射，自动走 iPad VPN / 代理节点。
- **详细信息（v1.2.0）**：详细卡片中每个目标多一行 `延迟 · HTTP 状态 · 均/低/高`，地域行下方多一行 `运营商 · ASN`（如 `AS45102`），可直接判断当前出口 IP 是「真的落地在境外」还是「IP 注册在国内」。

## 云端编译 `.ipa`（Windows 无需 Mac）

已配置好 GitHub Actions 工作流 `.github/workflows/build-ios.yml`：
1. 将本项目中的 `ios/` 目录与 `.github/workflows/build-ios.yml` 上传到你的 GitHub 仓库（可直接用 Edge 网页拖入 `ios` 文件夹并新建 `.github/workflows/build-ios.yml`）。
2. 在仓库 **Actions** 中运行 **Build iPadOS / iOS IPA**（基于 `macos-latest` + `XcodeGen` 自动编译，约 2 分钟）。
3. 构建完成后在底部 **Artifacts** 下载 **`LatencyMonitor-iPadOS-IPA`**，解压得到未签名的 `LatencyMonitor.ipa`。

## 安装到 iPad mini 5
- **方式 A（巨魔 TrollStore，推荐，永久免签）**：若 iPad mini 5 系统支持 TrollStore，将 `LatencyMonitor.ipa` 发送到 iPad，用 TrollStore 打开安装即可永久使用。
- **方式 B（Windows + Sideloadly / 爱思助手）**：
  1. 在 Windows 安装 [Sideloadly](https://sideloadly.io/)（或爱思助手），用数据线连接 iPad mini 5 并在 iPad 上点「信任此电脑」。
  2. 把 `LatencyMonitor.ipa` 拖入 Sideloadly，登录你的 Apple ID 点击 **Start** 自动签名安装。
  3. 安装后在 iPad **设置 → 通用 → VPN 与设备管理** 中信任开发者证书，并开启 **设置 → 隐私与安全性 → 开发者模式**（iPadOS 16+）即可打开使用。
