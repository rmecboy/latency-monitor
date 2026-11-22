import SwiftUI

@main
struct LatencyMonitorApp: App {
    @StateObject private var config: AppConfig
    @StateObject private var pipManager: PiPManager

    init() {
        let cfg = AppConfig()
        _config = StateObject(wrappedValue: cfg)
        _pipManager = StateObject(wrappedValue: PiPManager(config: cfg))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(config: config, pipManager: pipManager)
                .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @ObservedObject var config: AppConfig
    @ObservedObject var pipManager: PiPManager

    private let bgDark = Color(red: 15/255, green: 18/255, blue: 25/255)
    private let cardBg = Color(red: 24/255, green: 28/255, blue: 38/255)
    private let greenAccent = Color(red: 52/255, green: 211/255, blue: 153/255)
    private let amberAccent = Color(red: 251/255, green: 191/255, blue: 36/255)
    private let redAccent = Color(red: 248/255, green: 113/255, blue: 113/255)
    private let skyAccent = Color(red: 56/255, green: 189/255, blue: 248/255)

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    previewCard
                    controlCard
                    settingsCard
                    targetsCard
                }
                .padding(16)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(bgDark.ignoresSafeArea())
            .navigationTitle("网络延迟悬浮窗")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
    }

    private var previewCard: some View {
        let px = PiPRenderer.pixelSize(for: config.pipStyle)
        let ratio = CGFloat(px.width) / CGFloat(px.height)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时悬浮窗预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.gray)
                Spacer()
                Text(pipManager.statusMessage)
                    .font(.caption)
                    .foregroundColor(pipManager.isPiPActive ? greenAccent : .gray)
            }

            PiPPreviewContainer(manager: pipManager)
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxHeight: config.pipStyle == .detailCard ? 160 : 66)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button(action: { pipManager.togglePiP() }) {
                    HStack {
                        Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                        Text(pipManager.isPiPActive ? "关闭画中画悬浮窗" : "开启画中画悬浮窗")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(pipManager.isPiPActive ? redAccent : greenAccent)
                    .foregroundColor(Color.black.opacity(0.88))
                    .cornerRadius(10)
                }

                Button(action: { pipManager.refreshNow() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .padding(12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            Text("提示：开启后返回桌面或切换其他 App 即可悬浮置顶；双指捏合可缩到极小，点画中画中间按钮可在「极简纯地域 / 详细卡片」间切换。")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var controlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("当前网络状态")
                    .font(.headline)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                        .foregroundColor(skyAccent)
                    Text(pipManager.geoInfo?.displayText ?? "定位中...")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }
            }

            Divider().background(Color.white.opacity(0.15))

            ForEach(config.targets) { target in
                let res = pipManager.results.first(where: { $0.targetId == target.id })
                HStack {
                    Circle()
                        .fill(statusColor(for: res))
                        .frame(width: 8, height: 8)
                    Text(target.name)
                        .font(.body)
                        .foregroundColor(.white)
                    Spacer()
                    Text(latencyText(for: res))
                        .font(.system(.body, design: .monospaced).weight(.bold))
                        .foregroundColor(statusColor(for: res))
                }
            }
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("显示与测速设置")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("画中画悬浮样式")
                    .font(.caption)
                    .foregroundColor(.gray)
                Picker("样式", selection: $config.pipStyle) {
                    ForEach(PiPStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.pipStyle) { _ in
                    pipManager.applyStyleChange()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("测速模式")
                    .font(.caption)
                    .foregroundColor(.gray)
                Picker("模式", selection: $config.mode) {
                    ForEach(ProbeMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: config.mode) { _ in
                    pipManager.refreshNow()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("刷新间隔")
                    .font(.caption)
                    .foregroundColor(.gray)
                Picker("间隔", selection: $config.intervalSeconds) {
                    Text("2秒").tag(2)
                    Text("3秒").tag(3)
                    Text("5秒").tag(5)
                    Text("10秒").tag(10)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("自定义测速地址")
                .font(.headline)

            urlField(title: "Google", text: $config.googleUrl)
            urlField(title: "Cloudflare", text: $config.cloudflareUrl)
            urlField(title: "Oracle（可替换成你自己的 Oracle Cloud 地址）", text: $config.oracleUrl)
        }
        .padding(14)
        .background(cardBg)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func urlField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
            TextField("", text: text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .font(.system(.footnote, design: .monospaced))
                .padding(9)
                .background(bgDark)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
    }

    private func latencyText(for res: ProbeResult?) -> String {
        guard let res = res else { return "-- ms" }
        return res.success ? "\(res.latencyMs) ms" : "超时"
    }

    private func statusColor(for res: ProbeResult?) -> Color {
        guard let res = res else { return .gray }
        if !res.success { return redAccent }
        if res.latencyMs < 800 { return greenAccent }
        if res.latencyMs <= 1500 { return amberAccent }
        return redAccent
    }
}
