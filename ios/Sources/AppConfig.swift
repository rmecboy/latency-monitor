import Foundation

enum ProbeMode: String, CaseIterable, Identifiable {
    case https = "HTTPS"
    case tcp = "TCP"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .https: return "HTTPS (走代理/VPN)"
        case .tcp: return "TCP (443)"
        }
    }
}

enum PiPStyle: String, CaseIterable, Identifiable {
    case regionOnly = "region"
    case miniBar = "mini"
    case detailCard = "card"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .regionOnly: return "极简纯地域"
        case .miniBar: return "迷你一行条"
        case .detailCard: return "详细卡片"
        }
    }
}

struct TargetItem: Identifiable, Hashable {
    let id: String
    let name: String
    let shortName: String
    let urlString: String
    let method: String

    var host: String {
        guard let url = URL(string: normalizedUrl), let h = url.host, !h.isEmpty else {
            return urlString
        }
        return h
    }

    var port: Int {
        guard let url = URL(string: normalizedUrl) else { return 443 }
        if let p = url.port, p > 0 { return p }
        return url.scheme?.lowercased() == "http" ? 80 : 443
    }

    var normalizedUrl: String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}

final class AppConfig: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var mode: ProbeMode {
        didSet { defaults.set(mode.rawValue, forKey: "lm_mode") }
    }
    @Published var pipStyle: PiPStyle {
        didSet { defaults.set(pipStyle.rawValue, forKey: "lm_pip_style") }
    }
    @Published var intervalSeconds: Int {
        didSet { defaults.set(intervalSeconds, forKey: "lm_interval_sec") }
    }
    @Published var googleUrl: String {
        didSet { defaults.set(googleUrl, forKey: "lm_google_url") }
    }
    @Published var cloudflareUrl: String {
        didSet { defaults.set(cloudflareUrl, forKey: "lm_cloudflare_url") }
    }
    @Published var oracleUrl: String {
        didSet { defaults.set(oracleUrl, forKey: "lm_oracle_url") }
    }

    init() {
        let savedMode = defaults.string(forKey: "lm_mode") ?? ProbeMode.https.rawValue
        self.mode = ProbeMode(rawValue: savedMode) ?? .https

        let savedStyle = defaults.string(forKey: "lm_pip_style") ?? PiPStyle.regionOnly.rawValue
        self.pipStyle = PiPStyle(rawValue: savedStyle) ?? .regionOnly

        let savedInterval = defaults.integer(forKey: "lm_interval_sec")
        self.intervalSeconds = savedInterval >= 2 ? savedInterval : 3

        self.googleUrl = defaults.string(forKey: "lm_google_url") ?? "https://www.google.com/generate_204"
        self.cloudflareUrl = defaults.string(forKey: "lm_cloudflare_url") ?? "https://cp.cloudflare.com/generate_204"
        self.oracleUrl = defaults.string(forKey: "lm_oracle_url") ?? "https://www.oracle.com/favicon.ico"
    }

    var targets: [TargetItem] {
        [
            TargetItem(
                id: "google",
                name: "Google",
                shortName: "G",
                urlString: googleUrl.isEmpty ? "https://www.google.com/generate_204" : googleUrl,
                method: "GET"
            ),
            TargetItem(
                id: "cloudflare",
                name: "Cloudflare",
                shortName: "CF",
                urlString: cloudflareUrl.isEmpty ? "https://cp.cloudflare.com/generate_204" : cloudflareUrl,
                method: "GET"
            ),
            TargetItem(
                id: "oracle",
                name: "Oracle",
                shortName: "OCI",
                urlString: oracleUrl.isEmpty ? "https://www.oracle.com/favicon.ico" : oracleUrl,
                method: "HEAD"
            )
        ]
    }
}
