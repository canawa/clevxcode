// Мост между ядром sing-box (Libbox) и NetworkExtension.
// ВНИМАНИЕ: сигнатуры протокола LibboxPlatformInterfaceProtocol зависят от версии
// sing-box — после сборки Frameworks/Libbox.xcframework сверить с Libbox.objc.h.
#if canImport(Libbox)
import Foundation
import Network
import NetworkExtension
import Libbox

final class ExtensionPlatformInterface: NSObject, LibboxPlatformInterfaceProtocol {
    private unowned let provider: PacketTunnelProvider
    private var networkSettings: NEPacketTunnelNetworkSettings?

    init(provider: PacketTunnelProvider) {
        self.provider = provider
    }

    func reset() {
        networkSettings = nil
    }

    // MARK: - TUN

    func openTun(_ options: (any LibboxTunOptionsProtocol)?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        guard let options else { throw NSError(domain: "ClevVPN", code: 10) }

        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")
        settings.mtu = NSNumber(value: options.getMTU())

        var ipv4Addresses: [String] = []
        var ipv4Masks: [String] = []
        let inet4Iterator = options.getInet4Address()
        while let iterator = inet4Iterator, iterator.hasNext() {
            guard let prefix = iterator.next() else { break }
            ipv4Addresses.append(prefix.address())
            ipv4Masks.append(prefix.mask())
        }
        if !ipv4Addresses.isEmpty {
            let ipv4 = NEIPv4Settings(addresses: ipv4Addresses, subnetMasks: ipv4Masks)
            if options.getAutoRoute() {
                ipv4.includedRoutes = [NEIPv4Route.default()]
            }
            settings.ipv4Settings = ipv4
        }

        var ipv6Addresses: [String] = []
        var ipv6Prefixes: [NSNumber] = []
        let inet6Iterator = options.getInet6Address()
        while let iterator = inet6Iterator, iterator.hasNext() {
            guard let prefix = iterator.next() else { break }
            ipv6Addresses.append(prefix.address())
            ipv6Prefixes.append(NSNumber(value: prefix.prefix()))
        }
        if !ipv6Addresses.isEmpty {
            let ipv6 = NEIPv6Settings(addresses: ipv6Addresses, networkPrefixLengths: ipv6Prefixes)
            if options.getAutoRoute() {
                ipv6.includedRoutes = [NEIPv6Route.default()]
            }
            settings.ipv6Settings = ipv6
        }

        var dnsServer = "1.1.1.1"
        if let dns = options.getDNSServerAddress(), !dns.isEmpty {
            dnsServer = dns
        }
        let dnsSettings = NEDNSSettings(servers: [dnsServer])
        dnsSettings.matchDomains = [""]
        settings.dnsSettings = dnsSettings

        networkSettings = settings

        let semaphore = DispatchSemaphore(value: 0)
        var applyError: Error?
        provider.setTunnelNetworkSettings(settings) { error in
            applyError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let applyError { throw applyError }

        ret0_?.pointee = tunFileDescriptor()
    }

    /// Дескриптор utun-интерфейса packetFlow.
    private func tunFileDescriptor() -> Int32 {
        if let fd = provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as? Int32 {
            return fd
        }
        // Fallback: ищем utun среди открытых дескрипторов
        var buf = [CChar](repeating: 0, count: Int(IFNAMSIZ))
        for fd: Int32 in 0...1024 {
            var len = socklen_t(buf.count)
            if getsockopt(fd, 2 /* SYSPROTO_CONTROL */, 2 /* UTUN_OPT_IFNAME */, &buf, &len) == 0 {
                return fd
            }
        }
        return -1
    }

    // MARK: - Интерфейсы и мониторинг сети

    func usePlatformAutoDetectInterfaceControl() -> Bool { true }

    func autoDetectInterfaceControl(_ fd: Int32) throws {}

    func usePlatformDefaultInterfaceMonitor() -> Bool { true }

    private var interfaceListener: (any LibboxInterfaceUpdateListenerProtocol)?
    private var pathMonitor: NWPathMonitor?

    func startDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        interfaceListener = listener
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let listener = self?.interfaceListener else { return }
            let expensive = path.isExpensive
            let constrained = path.isConstrained
            listener.updateDefaultInterface(
                path.availableInterfaces.first?.name ?? "",
                interfaceIndex: Int32(path.availableInterfaces.first?.index ?? 0),
                isExpensive: expensive,
                isConstrained: constrained
            )
        }
        monitor.start(queue: DispatchQueue(label: "clevvpn.path-monitor"))
        pathMonitor = monitor
    }

    func closeDefaultInterfaceMonitor(_ listener: (any LibboxInterfaceUpdateListenerProtocol)?) throws {
        pathMonitor?.cancel()
        pathMonitor = nil
        interfaceListener = nil
    }

    func getInterfaces() throws -> any LibboxNetworkInterfaceIteratorProtocol {
        throw NSError(domain: "ClevVPN", code: 11, userInfo: [NSLocalizedDescriptionKey: "not implemented"])
    }

    // MARK: - Платформенные флаги

    func underNetworkExtension() -> Bool { true }
    func includeAllNetworks() -> Bool { false }
    func useProcFS() -> Bool { false }

    func findConnectionOwner(_ ipProtocol: Int32, sourceAddress: String?, sourcePort: Int32,
                             destinationAddress: String?, destinationPort: Int32,
                             ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "ClevVPN", code: 12, userInfo: [NSLocalizedDescriptionKey: "not supported on iOS"])
    }

    func packageName(byUid uid: Int32, error: NSErrorPointer) -> String { "" }

    func uid(byPackageName packageName: String?, ret0_: UnsafeMutablePointer<Int32>?) throws {
        throw NSError(domain: "ClevVPN", code: 13, userInfo: [NSLocalizedDescriptionKey: "not supported on iOS"])
    }

    // MARK: - Прочее

    func writeLog(_ message: String?) {
        if let message { NSLog("[sing-box] %@", message) }
    }

    func clearDNSCache() {
        if let settings = networkSettings {
            provider.reasserting = true
            provider.setTunnelNetworkSettings(nil) { _ in }
            provider.setTunnelNetworkSettings(settings) { _ in }
            provider.reasserting = false
        }
    }

    func readWIFIState() -> LibboxWIFIState? { nil }

    func systemCertificates() -> (any LibboxStringIteratorProtocol)? { nil }

    func sendNotification(_ notification: LibboxNotification?) throws {}
}
#endif
