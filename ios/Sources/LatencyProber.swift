import Foundation
import Network

struct TargetItem: Identifiable, Equatable {
    let id: String
    let name: String
    let url: String
    let host: String
    let port: UInt16
    let method: String
}

struct ProbeResult: Equatable {
    let success: Bool
    let latencyMs: Int
    let detail: String
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum LatencyProber {
    private static let noRedirectDelegate = NoRedirectDelegate()

    static func probe(target: TargetItem, mode: String, timeoutSec: TimeInterval) async -> ProbeResult {
        if mode.uppercased() == "TCP" {
            return await probeTcp(host: target.host, port: target.port, timeoutSec: timeoutSec)
        }
        return await probeHttps(target: target, timeoutSec: timeoutSec)
    }

    private static func probeHttps(target: TargetItem, timeoutSec: TimeInterval) async -> ProbeResult {
        guard let url = URL(string: target.url) else {
            return ProbeResult(success: false, latencyMs: -1, detail: "Invalid URL")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutSec
        config.timeoutIntervalForResource = timeoutSec
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldUsePipelining = false

        let session = URLSession(configuration: config, delegate: noRedirectDelegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeoutSec)
        req.httpMethod = target.method
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(for: req)
            let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            return ProbeResult(success: true, latencyMs: elapsed, detail: "HTTP \(code)")
        } catch {
            return ProbeResult(success: false, latencyMs: -1, detail: "超时")
        }
    }

    private static func probeTcp(host: String, port: UInt16, timeoutSec: TimeInterval) async -> ProbeResult {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            return ProbeResult(success: false, latencyMs: -1, detail: "Invalid Port")
        }

        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.latencymonitor.tcp.\(UUID().uuidString)")
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
            let start = CFAbsoluteTimeGetCurrent()
            var finished = false

            let finish: (ProbeResult) -> Void = { result in
                if finished { return }
                finished = true
                conn.stateUpdateHandler = nil
                conn.cancel()
                continuation.resume(returning: result)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000.0))
                    finish(ProbeResult(success: true, latencyMs: elapsed, detail: "TCP :\(port)"))
                case .failed:
                    finish(ProbeResult(success: false, latencyMs: -1, detail: "连接失败"))
                case .cancelled:
                    finish(ProbeResult(success: false, latencyMs: -1, detail: "已取消"))
                default:
                    break
                }
            }

            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeoutSec) {
                finish(ProbeResult(success: false, latencyMs: -1, detail: "超时"))
            }
        }
    }
}
