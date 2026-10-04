// Пинг через ядро sing-box: поднимаем внутри приложения экземпляр ядра
// без TUN (только outbound'ы + Clash API) и меряем реальную задержку
// каждого сервера через его протокол — включая Hysteria2 (QUIC/UDP),
// который обычным TCP-пингом не измерить.
//
// Файл активен только при собранном Frameworks/Libbox.xcframework
// (scripts/build-libbox.sh). После сборки сверить сигнатуры с Libbox.objc.h.
#if canImport(Libbox)
import Foundation
import Libbox
import ClevVPNKit

enum LibboxPingEngine {
    private static let clashPort = 19_090
    private static let testURL = "https://www.gstatic.com/generate_204"

    /// Подключает движок ядра к PingService. Вызывается при старте приложения.
    static func install() {
        PingService.shared.coreEngine = { servers in
            await ping(servers: servers)
        }
    }

    private static func ping(servers: [Server]) async -> [PingResult] {
        guard !servers.isEmpty else { return [] }

        let config = SingBoxConfigBuilder.buildPingConfig(servers: servers, clashPort: clashPort)
        guard let data = try? JSONSerialization.data(withJSONObject: config) else { return [] }
        let json = String(decoding: data, as: UTF8.self)

        var error: NSError?
        let options = LibboxSetupOptions()
        options.basePath = SharedStore.containerURL.path
        options.workingPath = SharedStore.workingDirectory.path
        options.tempPath = FileManager.default.temporaryDirectory.path
        LibboxSetup(options, &error)

        guard let service = LibboxNewService(json, EmptyPlatformInterface(), &error), error == nil else {
            return []
        }
        do {
            try service.start()
        } catch {
            return []
        }
        defer { try? service.close() }

        // Даём Clash API подняться
        try? await Task.sleep(nanoseconds: 300_000_000)

        return await withTaskGroup(of: PingResult.self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask {
                    let latency = await delay(proxyTag: "ping-\(index)")
                    return PingResult(serverID: server.id, latencyMs: latency)
                }
            }
            var results: [PingResult] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    /// GET /proxies/{tag}/delay у Clash API запущенного ядра.
    private static func delay(proxyTag: String) async -> Int? {
        var components = URLComponents(string: "http://127.0.0.1:\(clashPort)/proxies/\(proxyTag)/delay")!
        components.queryItems = [
            URLQueryItem(name: "timeout", value: "5000"),
            URLQueryItem(name: "url", value: testURL)
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delay = object["delay"] as? Int else {
            return nil
        }
        return delay
    }
}

/// Пустая платформа для ядра без TUN — все системные функции не нужны.
private final class EmptyPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "ClevVPN", code: 20, userInfo: [NSLocalizedDescriptionKey: "no tun in ping mode"])
    }

    func usePlatformAutoDetectInterfaceControl() -> Bool { true }
    func autoDetectInterfaceControl(_ fd: Int32) throws {}
    func usePlatformDefaultInterfaceMonitor() -> Bool { false }
    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}
    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {}
    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "ClevVPN", code: 21, userInfo: [NSLocalizedDescriptionKey: "not implemented"])
    }
    func underNetworkExtension() -> Bool { false }
    func includeAllNetworks() -> Bool { false }
    func useProcFS() -> Bool { false }
    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32,
                             ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "ClevVPN", code: 22)
    }
    func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }
    func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "ClevVPN", code: 23)
    }
    func writeLog(_ message: String?) {}
    func clearDNSCache() {}
    func readWIFIState() -> LibboxWIFIState? { nil }
    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }
    func sendNotification(_ notification: LibboxNotification?) throws {}
}
#endif
