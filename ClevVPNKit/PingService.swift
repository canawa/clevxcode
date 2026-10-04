import Foundation
import Network

/// Результат замера задержки.
public struct PingResult: Sendable {
    public let serverID: String
    /// Миллисекунды; nil — сервер недоступен.
    public let latencyMs: Int?

    public init(serverID: String, latencyMs: Int?) {
        self.serverID = serverID
        self.latencyMs = latencyMs
    }
}

/// Замер задержки серверов = время TCP-рукопожатия до сервера (чистый сетевой
/// RTT, малые сопоставимые цифры, как у большинства VPN-клиентов).
/// Hysteria2 работает по UDP/QUIC — его порт не отвечает на TCP, поэтому для
/// него RTT меряется по стандартным TCP-портам того же хоста (443/80).
public final class PingService: @unchecked Sendable {
    public static let shared = PingService()

    /// Подключаемый движок ядра (опционально). По умолчанию не используется —
    /// приложение полагается на быстрый TCP-пинг.
    public var coreEngine: (@Sendable ([Server]) async -> [PingResult])?

    private init() {}

    public func ping(servers: [Server]) async -> [PingResult] {
        let results = await tcpPing(servers: servers)
        save(results)
        return results
    }

    /// Пинг с постепенной отдачей результатов (по мере готовности каждого сервера).
    /// Ограничиваем одновременные соединения — иначе десятки одновременных SYN
    /// теряются под нагрузкой и TCP ретранслирует их через ~1с (ложные ~1000мс).
    public func ping(servers: [Server], onResult: @escaping @Sendable (PingResult) -> Void) async {
        let maxConcurrent = 12
        await withTaskGroup(of: Void.self) { group in
            var index = 0
            func addNext() {
                guard index < servers.count else { return }
                let server = servers[index]; index += 1
                group.addTask {
                    let ms = await Self.probe(server)
                    onResult(PingResult(serverID: server.id, latencyMs: ms))
                }
            }
            for _ in 0..<min(maxConcurrent, servers.count) { addNext() }
            while await group.next() != nil { addNext() }
        }
    }

    private func save(_ results: [PingResult]) {
        var stored = SharedStore.pingResults
        for result in results {
            stored[result.serverID] = result.latencyMs ?? -1
        }
        SharedStore.pingResults = stored
    }

    // MARK: - TCP

    private func tcpPing(servers: [Server]) async -> [PingResult] {
        await withTaskGroup(of: PingResult.self) { group in
            for server in servers {
                group.addTask {
                    let latency = await Self.probe(server)
                    return PingResult(serverID: server.id, latencyMs: latency)
                }
            }
            var results: [PingResult] = []
            for await result in group { results.append(result) }
            return results
        }
    }

    /// RTT одного сервера. Если первое значение аномально большое (вероятный
    /// SYN-ретрансмит ~1с), перепроверяем и берём минимум.
    private static func probe(_ server: Server) async -> Int? {
        let first = await probeOnce(server)
        if let f = first, f > 600 {
            if let second = await probeOnce(server) { return min(f, second) }
        }
        return first
    }

    /// Одна попытка. DNS-резолв вынесен из замера (резолвим в IP заранее) —
    /// в цифре только TCP-рукопожатие. Hysteria2 (UDP) меряем по TCP 443/80.
    private static func probeOnce(_ server: Server) async -> Int? {
        let target = resolveIP(server.host) ?? server.host
        if let ms = await tcpConnectTime(host: target, port: server.port) {
            return ms
        }
        if server.protocolType == .hysteria2 {
            for fallbackPort in [443, 80] where fallbackPort != server.port {
                if let ms = await tcpConnectTime(host: target, port: fallbackPort) {
                    return ms
                }
            }
        }
        return nil
    }

    /// Физический интерфейс (Wi-Fi/Ethernet) для жёсткой привязки пинга —
    /// чтобы соединения шли мимо VPN-туннеля. Кэшируется; сбрасывается редко.
    private static var cachedInterface: NWInterface?
    private static var interfaceResolvedAt: Date?
    private static let interfaceLock = NSLock()

    private static func physicalInterface() -> NWInterface? {
        interfaceLock.lock()
        // Перечитываем раз в 30с — на случай смены сети (Wi-Fi ↔ Ethernet)
        if let at = interfaceResolvedAt, Date().timeIntervalSince(at) < 30 {
            let cached = cachedInterface
            interfaceLock.unlock()
            return cached
        }
        interfaceLock.unlock()

        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var found: NWInterface?
        monitor.pathUpdateHandler = { path in
            found = path.availableInterfaces.first {
                $0.type == .wifi || $0.type == .wiredEthernet
            }
            semaphore.signal()
        }
        monitor.start(queue: DispatchQueue(label: "clevvpn.ping.iface"))
        _ = semaphore.wait(timeout: .now() + 2)
        monitor.cancel()

        interfaceLock.lock()
        cachedInterface = found
        interfaceResolvedAt = Date()
        interfaceLock.unlock()
        return found
    }

    private static var ipCache: [String: String] = [:]
    private static let ipCacheLock = NSLock()

    /// Резолвит host → IP (с кэшем). Если host уже IP — возвращает как есть.
    private static func resolveIP(_ host: String) -> String? {
        if host.allSatisfy({ $0.isNumber || $0 == "." || $0 == ":" }) { return host }
        ipCacheLock.lock()
        if let cached = ipCache[host] { ipCacheLock.unlock(); return cached }
        ipCacheLock.unlock()

        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
                             ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { return nil }
        defer { freeaddrinfo(res) }
        var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(first.pointee.ai_addr, first.pointee.ai_addrlen,
                          &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 else { return nil }
        let ip = String(cString: buf)
        ipCacheLock.lock(); ipCache[host] = ip; ipCacheLock.unlock()
        return ip
    }

    private static func tcpConnectTime(host: String, port: Int, timeout: TimeInterval = 3) async -> Int? {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { return nil }
        // Пинг идёт МИМО VPN-туннелей, чтобы показывать реальный RTT от локации.
        // При активном VPN prohibitedInterfaceTypes недостаточно (auto_route
        // перехватывает), поэтому ЖЁСТКО привязываем к физическому интерфейсу.
        let params = NWParameters.tcp
        if let iface = physicalInterface() {
            params.requiredInterface = iface
        } else {
            params.prohibitedInterfaceTypes = [.other]
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        let start = DispatchTime.now()

        return await withCheckedContinuation { continuation in
            let finished = LockedFlag()
            let finish: (Int?) -> Void = { value in
                guard finished.trySet() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let elapsed = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
                    finish(Int(elapsed / 1_000_000))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }
}

/// Однократный флаг с блокировкой — защита от двойного resume continuation.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    func trySet() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if isSet { return false }
        isSet = true
        return true
    }
}
