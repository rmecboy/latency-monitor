# 网络延迟悬浮窗（Android 安卓版）

原生轻量级 Android 悬浮窗（零第三方依赖，APK 体积仅约 100 KB），支持 Android 8.0 ~ Android 15/16。

## 功能特性
- 实时显示 **Google / Cloudflare / Oracle** 延迟（`< 800 ms` 绿色，`800 ~ 1500 ms` 黄色，`> 1500 ms` 或超时红色）
- 显示当前网络**地域地址**（不显示 IP），5 源自动容错并支持中文地名，自动适配手机 VPN/代理节点切换
- **单击任意一行查看详细信息**（v1.2.0 新增）：
  - 目标行 → 目标地址、当前延迟与 HTTP 状态、更新时间、**最近 20 次平均 / 最低 / 最高**
  - 地域行 → 国家/地区、省份/州、城市、**运营商 / ASN**、数据来源与刷新时间
- **手指拖动**自由定位（自动记忆位置），单击空白处切换「纵向卡片 / 横向迷你条」
- 通知栏提供快捷按钮：切换布局 / 立即刷新 / 关闭悬浮窗
- App 主界面可自定义测速模式（HTTPS / TCP）、刷新频率、透明度及 3 个目标地址

## 云端自动打包 APK（无需在本地装 Android Studio / JDK）

项目根目录已配置好 GitHub Actions 打包脚本 `.github/workflows/build-android.yml`：

1. 在 GitHub 新建一个仓库（公开或私有均可），将本项目推送上去：
   ```bash
   git init
   git add .
   git commit -m "Add Windows & Android latency monitor"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<你的仓库名>.git
   git push -u origin main
   ```
2. 打开仓库页面的 **Actions** 标签页，等待 **Build Android APK** 自动运行完成（约 1 分钟；也可以手动点击右侧 **Run workflow** 触发）。
3. 点击最新的构建记录，在底部 **Artifacts** 中下载 **`LatencyMonitor-Android-APK`**，解压得到 `LatencyMonitor.apk` 发送到安卓手机安装即可。

## 手机端首次使用
1. 打开「网络延迟悬浮窗」App，点击「前往开启悬浮窗权限」，允许“显示在其他应用上层”。
2. 返回 App 点击「开启悬浮窗」即可（Android 13+ 建议允许通知权限，便于通知栏快捷控制与防止后台被杀）。
3. 若手机后台容易清理进程，可在手机系统设置中将该 App 的电池策略设为“无限制”。
