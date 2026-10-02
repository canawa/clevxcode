import NetworkExtension
import ClevVPNKit
#if canImport(Libbox)
import Libbox
#endif

/// Туннельный провайдер: запускает ядро sing-box с конфигом,
/// который приложение положило в App Group перед стартом.
class PacketTunnelProvider: NEPacketTunnelProvider {

    #if canImport(Libbox)
    private var boxService: LibboxBoxService?
    private var platformInterface: ExtensionPlatformInterface?
    #endif

    override func startTunnel(options: [String: NSObject]? = nil) async throws {
        #if canImport(Libbox)
        let configURL = SharedStore.configURL
        guard let config = try? String(contentsOf: configURL, encoding: .utf8) else {
            throw NSError(domain: "ClevVPN", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Config not found at \(configURL.path)"
            ])
        }

        try setupLibbox()

        let interface = ExtensionPlatformInterface(provider: self)
        platformInterface = interface

        var error: NSError?
        guard let service = LibboxNewService(config, interface, &error) else {
            throw error ?? NSError(domain: "ClevVPN", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Failed to create sing-box service"
            ])
        }
        try service.start()
        boxService = service
        #else
        throw NSError(domain: "ClevVPN", code: 100, userInfo: [
            NSLocalizedDescriptionKey: "Libbox core is not built. Run scripts/build-libbox.sh"
        ])
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        #if canImport(Libbox)
        try? boxService?.close()
        boxService = nil
        platformInterface?.reset()
        platformInterface = nil
        #endif
    }

    #if canImport(Libbox)
    private func setupLibbox() throws {
        let base = SharedStore.containerURL.path
        let working = SharedStore.workingDirectory.path
        let temp = FileManager.default.temporaryDirectory.path

        var error: NSError?
        let options = LibboxSetupOptions()
        options.basePath = base
        options.workingPath = working
        options.tempPath = temp
        LibboxSetup(options, &error)
        if let error { throw error }
    }

    override func handleAppMessage(_ messageData: Data) async -> Data? {
        // Резерв для запросов статистики из приложения
        return nil
    }
    #endif
}
