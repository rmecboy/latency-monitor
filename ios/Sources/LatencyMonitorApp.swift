import Combine
import SwiftUI

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published var mode: String {
        didSet { UserDefaults.standard.set(mode, forKey: "mode"); pushFrame() }
    }
    @Published var intervalSec: Int {
        didSet { UserDefaults.standard.set(intervalSec, forKey: "interval_sec"); restartProbeLoop() }
    }
    @Published var compactHorizontal: Bool {
        didSet { UserDefaults.standard.set(compactHorizontal, forKey: "compact_horizontal"); pushFrame() }
    }
    @Published var showGeoLocation: Bool {
        didSet {
            UserDefaults.standard.set(showGeoLocation, forKey: "show_geo_location")
            pushFrame()
            if showGeoLocation { refreshGeo() }
        }
    }
    @Published var googleUrl: String
    @Published var cloudflareUrl: String
    @Published var oracleUrl: String

    @Published var results: [String: ProbeResult] = [:]
    @Published var geoInfo: GeoInfo = GeoInfo.empty
    @Published var isPiPActive: Bool = false
    @Published var pipStatus: String = ""

    let pipManager = PiPManager()
    private var probeTask: Task<Void, Never>?
    private var geoTask: Task<Void, Never>?
    private var history: [String: [Int]] = [:]

    init() {
        let ud = UserDefaults.standard
        self.mode = ud.string(forKey: "mode") ?? "HTTPS"
        let savedInterval = ud.integer(forKey: "interval_sec")
        self.intervalSec = savedInterval >= 2 ? savedInterval : 3
        if ud.object(forKey: "compact_horizontal") != nil {
            self.compactHorizontal = ud.bool(forKey: "compact_horizontal")
        } else {
            self.compactHorizontal = true
        }
        if ud.object(forKey: "show_geo_location") != nil {
            self.showGeoLocation = ud.bool(forKey: "show_geo_location")
        } else {
            self.showGeoLocation = true
        }
        self.googleUrl = ud.string(forKey: "google_url") ?? "https://www.google.com/generate_204"
        self.cloudflareUrl = ud.string(forKey: "cloudflare_url") ?? "https://cp.cloudflare.com/generate_204"
        self.oracleUrl = ud.string(forKey: "oracle_url") ?? "https://www.oracle.com/favicon.ico"

        pipManager.$isPiPActive.assign(to: &$isPiPActive)
        pipManager.$statusMessage.assign(to: &$pipStatus)
        pipManager.onToggleCompact = { [weak self] in
            Task { @MainActor in
                self?.compactHorizontal.toggle()
            }
        }
    }

    var targets: [TargetItem] {
        return [
            makeTarget(id: "google", name: "Google", rawUrl: googleUrl, fallbackUrl: "https://www.google.com/generate_204", fallbackHost: "www.google.com", method: "GET"),
            makeTarget(id: "cloudflare", name: "Cloudflare", rawUrl: cloudflareUrl, fallbackUrl: "https://cp.cloudflare.com/generate_204", fallbackHost: "1.1.1.1", method: "GET"),
            makeTarget(id: "oracle", name: "Oracle", rawUrl: oracleUrl, fallbackUrl: "https://www.oracle.com/favicon.ico", fallbackHost: "www.oracle.com", method: "HEAD")
        ]
    }

    func start() {
        pipManager.configureIfNeeded()
        pushFrame()
        restartProbeLoop()
        restartGeoLoop()
    }

    func saveUrls() {
        let ud = UserDefaults.standard
        ud.set(googleUrl.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "google_url")
        ud.set(cloudflareUrl.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "cloudflare_url")
        ud.set(oracleUrl.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "oracle_url")
        refreshAll()
    }

    func togglePiP() {
        pipManager.togglePiP(
            targets: targets,
            results: results,
            details: detailLines(),
            geoText: geoInfo.displayText,
            geoDetail: geoInfo.detailLine,
            geoSuccess: geoInfo.success,
            showGeo: showGeoLocation,
            mode: mode,
            compactHorizontal: compactHorizontal
        )
    }

    /// 每个目标的一行详细信息：延迟 · 状态 · 近 20 次统计 · 目标主机
    func detailLines() -> [String: String] {
        var map: [String: String] = [:]
        for t in targets {
            var parts: [String] = []
            if let r = results[t.id] {
                parts.append(r.success ? "\(r.latencyMs)ms" : "失败")
                if !r.detail.isEmpty { parts.append(r.detail) }
            } else {
                parts.append("--")
            }
            if let s = statsLine(for: t.id) { parts.append(s) }
            parts.append(t.host)
            map[t.id] = parts.joined(separator: " · ")
        }
        return map
    }

    private func statsLine(for id: String) -> String? {
        guard let arr = history[id], !arr.isEmpty else { return nil }
        let avg = arr.reduce(0, +) / arr.count
        let mn = arr.min() ?? 0
        let mx = arr.max() ?? 0
        return "均\(avg) 低\(mn) 高\(mx)"
    }

    func refreshAll() {
        Task { await runProbeOnce() }
        if showGeoLocation {
            refreshGeo()
        }
    }

    func refreshGeo() {
        Task {
            let info = await GeoLocationFetcher.fetch(timeoutSec: 3.5)
            self.geoInfo = info
            self.pushFrame()
        }
    }

    private func restartProbeLoop() {
        probeTask?.cancel()
        probeTask = Task {
            while !Task.isCancelled {
                await runProbeOnce()
                let sleepNs = UInt64(max(2, intervalSec)) * 1_000_000_000
                try? await Task.sleep(nanoseconds: sleepNs)
            }
        }
    }

    private func restartGeoLoop() {
        geoTask?.cancel()
        geoTask = Task {
            while !Task.isCancelled {
                if showGeoLocation {
                    let info = await GeoLocationFetcher.fetch(timeoutSec: 3.5)
                    self.geoInfo = info
                    self.pushFrame()
                }
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func runProbeOnce() async {
        let currentTargets = targets
        let currentMode = mode
        var updated: [String: ProbeResult] = [:]

        await withTaskGroup(of: (String, ProbeResult).self) { group in
            for item in currentTargets {
                group.addTask {
                    let res = await LatencyProber.probe(target: item, mode: currentMode, timeoutSec: 3.0)
                    return (item.id, res)
                }
            }
            for await (id, res) in group {
                updated[id] = res
            }
        }

        for (id, res) in updated where res.success {
            var arr = history[id] ?? []
            arr.append(res.latencyMs)
            if arr.count > 20 { arr.removeFirst(arr.count - 20) }
            history[id] = arr
        }

        self.results = updated
        self.pushFrame()
    }

    func pushFrame() {
        pipManager.updateFrame(
            targets: targets,
            results: results,
            details: detailLines(),
            geoText: geoInfo.displayText,
            geoDetail: geoInfo.detailLine,
            geoSuccess: geoInfo.success,
            showGeo: showGeoLocation,
            mode: mode,
            compactHorizontal: compactHorizontal
        )
    }

    private func makeTarget(id: String, name: String, rawUrl: String, fallbackUrl: String, fallbackHost: String, method: String) -> TargetItem {
        var cleaned = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = fallbackUrl }
        if !cleaned.hasPrefix("http://") && !cleaned.hasPrefix("https://") {
            cleaned = "https://" + cleaned
        }
        let parsed = URL(string: cleaned)
        let host = parsed?.host ?? fallbackHost
        let port = UInt16(parsed?.port ?? (parsed?.scheme == "http" ? 80 : 443))
        return TargetItem(id: id, name: name, url: cleaned, host: host, port: port, method: method)
    }
}

struct ContentView: View {
    @StateObject private var vm = MonitorViewModel()
    @State private var savedToast = false

    var body: some View {
        ZStack {
            Color(red: 15.0 / 255.0, green: 18.0 / 255.0, blue: 25.0 / 255.0)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("网络延迟悬浮窗")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        Text("Google / Cloudflare / Oracle 延迟（<800ms 绿色）+ 当前网络地域")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(white: 0.65))
                    }

                    // Live PiP Preview Card
                    VStack(spacing: 12) {
                        PiPPreviewRepresentable(hostView: vm.pipManager.hostView)
                            .frame(maxWidth: .infinity)
                            .frame(height: vm.compactHorizontal ? 44 : 210)
                            .clipShape(RoundedRectangle(cornerRadius: vm.compactHorizontal ? 22 : 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: vm.compactHorizontal ? 22 : 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
                            )

                        HStack(spacing: 10) {
                            Button(action: { vm.togglePiP() }) {
                                Text(vm.isPiPActive ? "关闭画中画悬浮窗" : "开启画中画悬浮窗")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(vm.isPiPActive ? Color.white : Color(red: 5.0 / 255.0, green: 46.0 / 255.0, blue: 22.0 / 255.0))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        vm.isPiPActive
                                            ? Color(red: 239.0 / 255.0, green: 68.0 / 255.0, blue: 68.0 / 255.0)
                                            : Color(red: 52.0 / 255.0, green: 211.0 / 255.0, blue: 153.0 / 255.0)
                                    )
                                    .cornerRadius(10)
                            }

                            Button(action: { vm.refreshAll() }) {
                                Text("刷新")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(10)
                            }
                        }

                        if !vm.pipStatus.isEmpty {
                            Text(vm.pipStatus)
                                .font(.system(size: 12))
                                .foregroundColor(Color(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("开启画中画后，切回桌面或任何 App 都会保持悬浮显示（可拖动/缩放）。")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(white: 0.58))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(14)
                    .background(Color(red: 24.0 / 255.0, green: 28.0 / 255.0, blue: 38.0 / 255.0))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    // Settings Card
                    VStack(alignment: .leading, spacing: 14) {
                        Text("显示与测速设置")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("测速模式")
                                .font(.system(size: 12.5))
                                .foregroundColor(Color(white: 0.65))
                            Picker("测速模式", selection: $vm.mode) {
                                Text("HTTPS (走代理/VPN)").tag("HTTPS")
                                Text("TCP (443)").tag("TCP")
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("刷新频率")
                                .font(.system(size: 12.5))
                                .foregroundColor(Color(white: 0.65))
                            Picker("刷新频率", selection: $vm.intervalSec) {
                                Text("2秒").tag(2)
                                Text("3秒").tag(3)
                                Text("5秒").tag(5)
                                Text("10秒").tag(10)
                            }
                            .pickerStyle(.segmented)
                        }

                        Toggle("超扁单行胶囊模式（关闭则显示详细纵卡）", isOn: $vm.compactHorizontal)
                            .foregroundColor(.white)
                            .tint(Color(red: 52.0 / 255.0, green: 211.0 / 255.0, blue: 153.0 / 255.0))

                        Toggle("显示当前网络地域（不显示 IP）", isOn: $vm.showGeoLocation)
                            .foregroundColor(.white)
                            .tint(Color(red: 56.0 / 255.0, green: 189.0 / 255.0, blue: 248.0 / 255.0))
                    }
                    .padding(14)
                    .background(Color(red: 24.0 / 255.0, green: 28.0 / 255.0, blue: 38.0 / 255.0))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )

                    // Custom URLs Card
                    VStack(alignment: .leading, spacing: 10) {
                        Text("自定义测速地址")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)

                        urlField("Google", text: $vm.googleUrl)
                        urlField("Cloudflare", text: $vm.cloudflareUrl)
                        urlField("Oracle（可改成你自己的 Oracle Cloud 地址）", text: $vm.oracleUrl)

                        Button(action: {
                            vm.saveUrls()
                            savedToast = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                savedToast = false
                            }
                        }) {
                            Text(savedToast ? "已保存并应用 ✓" : "保存并应用地址")
                                .font(.system(size: 14.5, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Color(red: 37.0 / 255.0, green: 99.0 / 255.0, blue: 235.0 / 255.0))
                                .cornerRadius(10)
                        }
                        .padding(.top, 4)
                    }
                    .padding(14)
                    .background(Color(red: 24.0 / 255.0, green: 28.0 / 255.0, blue: 38.0 / 255.0))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .padding(16)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            vm.start()
        }
    }

    private func urlField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color(white: 0.65))
            TextField("", text: text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .padding(10)
                .background(Color(red: 17.0 / 255.0, green: 21.0 / 255.0, blue: 30.0 / 255.0))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}

@main
struct LatencyMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
