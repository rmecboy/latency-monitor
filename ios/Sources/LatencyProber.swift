import Foundation
import Network

struct ProbeResult {
    let targetId: String
    let name: String
    let shortName: String
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

    static func probeAll(targets: [TargetItem], mode: ProbeMode, timeoutSec: TimeInterval = 3.0) async -> [ProbeResult] {
        await withTaskGroup(of: (Int, ProbeResult).self) { group in
            for (idx, target) in targets.enumerated() {
                group.addTask {
                    let result = await probe(target: target, mode: mode, timeoutSec: timeoutSec)
                    return (idx, result)
                }
            }
            var ordered = Array<ProbeResult?>(repeating: nil, count: targets.count)
            for await (idx, res) in group {
                ordered[idx] = res
            }
            return ordered.compactMap { $0 }
        }
    }

    static func probe(target: TargetItem, mode: ProbeMode, timeoutSec: TimeInterval = 3.0) async -> ProbeResult {
        switch mode {
        case .https:
            return await probeHTTPS(target: target, timeoutSec: timeoutSec)
        case .tcp:
            return await probeTCP(target: target, timeoutSec: timeoutSec)
        }
    }

    private static func probeHTTPS(target: TargetItem, timeoutSec: TimeInterval) async -> ProbeResult {
        guard let url = URL(string: target.normalizedUrl) else {
            return ProbeResult(targetId: target.id, name: target.name, shortName: target.shortName, success: false, latencyMs: -1, detail: "Invalid URL")
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSec
        cfg.timeoutIntervalForResource = timeoutSec
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg, delegate: noRedirectDelegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeoutSec)
        req.httpMethod = target.method
        req.setValue("close", forHTTPHeaderField: "Connection")
        req.setValue(
            "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let (_, response) = try await session.data(for: req)
            let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - start) * 1000.0).rounded()))
            let code = (response as? HTTPURLResponse)?.statusCode ?? 200
            return ProbeResult(
                targetId: target.id,
                name: target.name,
                shortName: target.shortName,
                success: true,
                latencyMs: elapsedMs,
                detail: "HTTP \(code)"
            )
        } catch {
            return ProbeResult(
                targetId: target.id,
                name: target.name,
                shortName: target.shortName,
                success: false,
                latencyMs: -1,
                detail: "超时"
            )
        }
    }

    private static func probeTCP(target: TargetItem, timeoutSec: TimeInterval) async -> ProbeResult {
        let host = NWEndpoint.Host(target.host)
        let portNum = UInt16(clamping: target.port > 0 ? target.port : 443)
        guard let port = NWEndpoint.Port(rawValue: portNum) else {
            return ProbeResult(targetId: target.id, name: target.name, shortName: target.shortName, success: false, latencyMs: -1, detail: "Invalid Port")
        }

        let start = CFAbsoluteTimeGetCurrent()
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.latencymonitor.tcp.\(target.id)")
            let connection = NWConnection(host: host, port: port, using: .tcp)
            let lock = NSLock()
            var finished = false

            func finish(success: Bool, detail: String) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                let elapsedMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - start) * 1000.0).rounded()))
                continuation.resume(returning: ProbeResult(
                    targetId: target.id,
                    name: target.name,
                    shortName: target.shortName,
                    success: success,
                    latencyMs: success ? elapsedMs : -1,
                    detail: detail
                ))
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(success: true, detail: "TCP :\(portNum)")
                case .failed:
                    finish(success: false, detail: "连接失败")
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + timeoutSec) {
                finish(success: false, detail: "超时")
            }

            connection.start(queue: queue)
        }
    }
}
