# 网络延迟悬浮窗 (LatencyMonitor)

一个轻量级、免安装的 Windows 桌面悬浮窗，实时显示当前访问 **Google**、**Cloudflare**、**Oracle** 的延迟（ms），以及当前网络的**地域地址**（不显示 IP）。

## 快速使用

直接双击运行 `LatencyMonitor.exe` 即可。

- **当前网络地域**：自动通过系统代理检测并显示当前网络出口的地域（如 `日本 · 东京`、`中国香港`、`美国 · 洛杉矶`、`新加坡` 等），默认每 15 秒自动刷新一次（切换代理节点会自动更新）；悬停可查看国家/省/市、运营商与 **ASN**（如 `AS45102`）详情（不暴露 IP）。
- **左键拖动**：自由移动悬浮窗位置（自动记忆）
- **左键双击**：切换「纵向卡片」 / 「横向迷你条」布局
- **鼠标悬停某一行**：查看目标地址、响应状态，以及最近 20 次的平均/最低/最高延迟
- **右键菜单**：
  - 切换测速模式：
    - `HTTPS`（默认，自动跟随 Windows 系统代理，测得真实访问延迟；切换代理节点会实时生效）
    - `TCP`（443 端口直连握手延迟）
    - `ICMP`（传统 Ping 延迟）
  - 调整刷新频率（1s / 2s / 3s / 5s / 10s）
  - 调整窗口透明度
  - 开启/关闭窗口置顶
  - 开启**鼠标穿透**（开启后右键右下角系统托盘图标可取消）
  - 调整**颜色阈值**（预设：严格 / 标准 / 宽松 / 默认；自定义请编辑 `config.json` 的 `GreenMaxMs` / `YellowMaxMs`）
  - 编辑/重新加载 `config.json`
- **颜色指示**（默认值，可在右键菜单或 `config.json` 中修改）：
  - 绿色：`< 800 ms`
  - 黄色：`800 ~ 1500 ms`
  - 红色：`> 1500 ms` 或超时

## 自定义目标（如修改为你自己的 Oracle Cloud 服务器）

右键悬浮窗 → `编辑配置文件 (config.json)`，修改后保存，再点击 `重新加载配置` 即可生效。你也可以在 `Targets` 数组中增删任意站点。

## 全平台与自动发布

同一个仓库还包含 **Android**（`android/`，APK 悬浮窗）与 **iPadOS / iOS**（`ios/`，画中画悬浮窗）两个版本，由 GitHub Actions 自动编译：

- 推送 `v*` 标签 → 运行 `.github/workflows/release.yml`，同时构建 Windows `.exe`、Android `.apk`、iOS `.ipa` 并创建 GitHub Release
- 只想单独打包某一端 → 手动运行 `.github/workflows/build-android.yml` 或 `build-ios.yml`

手机端自 v1.2.0 起也支持查看详细信息：单击悬浮窗中的目标行，可展开目标地址、HTTP 状态、更新时间与最近 20 次的平均/最低/最高延迟；单击地域行可展开国家/省/市、运营商与 ASN。

## 重新编译（如需修改源码）

本程序仅依赖 Windows 自带的 .NET Framework 4.x，无需安装额外 SDK：

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```
