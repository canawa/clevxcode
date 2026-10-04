import Foundation
import ClevVPNKit

/// Пинг серверов через ядро sing-box (Clash API `delay`) — реальный тест
/// соединения через каждый протокол, включая Hysteria2 (UDP/QUIC), который
/// TCP-пробой не измерить. Запускается без root (без TUN-инбаунда).
enum MacPingEngine {

    /// Тот же путь, что и у туннеля: бандл / Application Support / brew.
    private static var corePath: String? { MacTunnel.resolveCorePath() }

    /// Устанавливает движок в общий PingService, если ядро доступно.
    static func installIfAvailable() {
        guard corePath != nil else { return }
        PingService.shared.coreEngine = { servers in
            await ping(servers: servers)
        }
    }

    static var isAvailable: Bool { corePath != nil }

    @discardableResult
    static func ping(servers: [Server]) async -> [PingResult] {
        var out: [PingResult] = []
        await ping(servers: servers) { out.append($0) }
        return out
    }

    /// Пингует серверы, вызывая `onResult` по мере готовности каждого — чтобы
    /// UI обновлялся постепенно, а не разом в конце.
    static func ping(servers: [Server], onResult: @escaping @Sendable (PingResult) -> Void) async {
        guard !servers.isEmpty,
              let core = corePath
        else {
            for s in servers { onResult(PingResult(serverID: s.id, latencyMs: nil)) }
            return
        }

        let port = Int.random(in: 19_000...19_900)
        let config = SingBoxConfigBuilder.buildPingConfig(servers: servers, clashPort: port)
        guard let data = try? JSONSerialization.data(withJSONObject: config) else { return }
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clevvpn-ping-\(port).json")
        try? data.write(to: configURL)
        defer { try? FileManager.default.removeItem(at: configURL) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: core)
        proc.arguments = ["run", "-c", configURL.path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch { return }
        defer { proc.terminate() }

        let base = "http://127.0.0.1:\(port)"
        guard await waitForClashAPI(base: base) else {
            for s in servers { onResult(PingResult(serverID: s.id, latencyMs: nil)) }
            return
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let tag = SingBoxConfigBuilder.pingTag(index: index)
                    var ms = await delay(base: base, tag: tag)
                    if ms == nil { ms = await delay(base: base, tag: tag) }
                    onResult(PingResult(serverID: server.id, latencyMs: ms))
                }
            }
            for await _ in group {}
        }
    }

    private static func waitForClashAPI(base: String) async -> Bool {
        guard let url = URL(string: "\(base)/version") else { return false }
        for _ in 0..<20 {
            var request = URLRequest(url: url)
            request.timeoutInterval = 1
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    private static func delay(base: String, tag: String) async -> Int? {
        let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
        let target = "http://www.gstatic.com/generate_204"
        let urlString = "\(base)/proxies/\(encoded)/delay?timeout=8000&url=\(target)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = json["delay"] as? Int else {
            return nil
        }
        return delay
    }
}
