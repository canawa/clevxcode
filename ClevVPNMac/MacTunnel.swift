import Foundation
import ClevVPNKit

/// Управление ядром sing-box на macOS: обычный root-процесс с TUN,
/// без Network Extension — поэтому работает без платного аккаунта Apple.
@MainActor
final class MacTunnel: ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    @Published private(set) var state: State = .disconnected
    @Published private(set) var lastError: String?
    /// Момент установления соединения — для таймера подключения.
    @Published private(set) var connectedAt: Date?
    /// Ядро найдено (бандл → Application Support, иначе Homebrew).
    @Published private(set) var corePath: String?
    /// Разрешение sudo без пароля настроено.
    @Published private(set) var isAuthorized = false

    private var process: Process?
    /// Остановка инициирована пользователем — не показывать «ядро упало».
    private var isStopping = false

    nonisolated private static let brewCandidates = [
        "/opt/homebrew/bin/sing-box",
        "/usr/local/bin/sing-box"
    ]

    nonisolated static let workDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClevVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Стабильный путь установленного ядра (для sudoers и запуска).
    nonisolated static var installedCoreURL: URL {
        workDirectory.appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("sing-box")
    }

    private var configURL: URL { Self.workDirectory.appendingPathComponent("config.json") }
    private var logURL: URL { Self.workDirectory.appendingPathComponent("core.log") }

    init() {
        refreshEnvironment()
    }

    /// Проверяет наличие ядра и права sudo. Запуск sudo — в фоне, чтобы не
    /// блокировать интерфейс при старте/обновлении.
    func refreshEnvironment() {
        corePath = Self.resolveCorePath()
        let core = corePath
        Task.detached(priority: .utility) {
            let ok = Self.checkSudo(core: core)
            await MainActor.run { self.isAuthorized = ok }
        }
    }

    /// Порядок: бандл → ~/Library/Application Support/ClevVPN/bin/sing-box → brew.
    nonisolated static func resolveCorePath() -> String? {
        if let installed = installBundledCoreIfNeeded() {
            return installed
        }
        if FileManager.default.isExecutableFile(atPath: installedCoreURL.path) {
            return installedCoreURL.path
        }
        if let brew = brewCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return brew
        }
        // На всякий случай — ресурс без копирования
        return Bundle.main.path(forResource: bundledResourceName(), ofType: nil)
            ?? Bundle.main.path(forResource: "sing-box", ofType: nil)
    }

    nonisolated private static func bundledResourceName() -> String {
        #if arch(arm64)
        return "sing-box-arm64"
        #else
        return "sing-box-amd64"
        #endif
    }

    /// Копирует ядро из .app в Application Support (стабильный путь для sudoers).
    @discardableResult
    nonisolated static func installBundledCoreIfNeeded() -> String? {
        let fm = FileManager.default
        guard let src = Bundle.main.url(forResource: bundledResourceName(), withExtension: nil)
                ?? Bundle.main.url(forResource: "sing-box", withExtension: nil)
        else { return nil }

        let dest = installedCoreURL
        let destDir = dest.deletingLastPathComponent()
        try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let bundledVersion = Bundle.main.url(forResource: "VERSION", withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let installedVersionURL = destDir.appendingPathComponent("VERSION")
        let installedVersion = (try? String(contentsOf: installedVersionURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let needsCopy: Bool
        if !fm.isExecutableFile(atPath: dest.path) {
            needsCopy = true
        } else if let bv = bundledVersion, bv != installedVersion {
            needsCopy = true
        } else {
            // Размер как быстрый индикатор обновления без VERSION
            let srcSize = (try? fm.attributesOfItem(atPath: src.path)[.size] as? NSNumber)?.intValue
            let dstSize = (try? fm.attributesOfItem(atPath: dest.path)[.size] as? NSNumber)?.intValue
            needsCopy = srcSize != nil && srcSize != dstSize
        }

        if needsCopy {
            try? fm.removeItem(at: dest)
            do {
                try fm.copyItem(at: src, to: dest)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest.path)
                if let bv = bundledVersion {
                    try? bv.write(to: installedVersionURL, atomically: true, encoding: .utf8)
                }
            } catch {
                return fm.isExecutableFile(atPath: dest.path) ? dest.path : nil
            }
        }

        return fm.isExecutableFile(atPath: dest.path) ? dest.path : nil
    }

    nonisolated private static func checkSudo(core: String?) -> Bool {
        guard let core else { return false }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        check.arguments = ["-n", core, "version"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        try? check.run()
        check.waitUntilExit()
        return check.terminationStatus == 0
    }

    /// Доступен ли pfctl без пароля (нужно для Kill Switch).
    nonisolated static func checkPfctlSudo() -> Bool {
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        check.arguments = ["-n", "/sbin/pfctl", "-s", "info"]
        check.standardOutput = FileHandle.nullDevice
        check.standardError = FileHandle.nullDevice
        try? check.run()
        check.waitUntilExit()
        return check.terminationStatus == 0
    }

    /// Убеждается, что pfctl авторизован (для Kill Switch). Если правило sudoers
    /// ещё старое (только sing-box) — показывает разовый запрос пароля админа,
    /// который перезаписывает правило, добавляя pfctl.
    @discardableResult
    func ensurePfctlAuthorized() async -> Bool {
        if Self.checkPfctlSudo() { return true }
        await authorize()
        return Self.checkPfctlSudo()
    }

    /// Одноразовая настройка: правило sudoers только для бинарника sing-box.
    /// Показывает системный запрос пароля администратора.
    func authorize() async {
        guard let core = corePath else { return }
        let user = NSUserName()
        // Разрешаем без пароля sing-box (туннель) и pfctl (Kill Switch)
        let line = "\(user) ALL=(root) NOPASSWD: \(core), /sbin/pfctl"
        let shell = "mkdir -p /etc/sudoers.d && printf '%s\\n' '\(line)' > /etc/sudoers.d/clevvpn && chmod 440 /etc/sudoers.d/clevvpn"
        let script = "do shell script \"\(shell.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"

        let osascript = Process()
        osascript.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        osascript.arguments = ["-e", script]
        let errPipe = Pipe()
        osascript.standardError = errPipe

        do {
            try osascript.run()
            await waitForExit(osascript)
            if osascript.terminationStatus != 0 {
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(decoding: data, as: UTF8.self)
                if !message.contains("-128") { // -128 = пользователь нажал «Отмена»
                    lastError = message.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
        isAuthorized = Self.checkSudo(core: corePath)
    }

    // MARK: - Запуск/остановка

    func start(servers: [Server], autoSelect: Bool,
               routingMode: RoutingMode, customRules: [RoutingRule],
               appRules: [AppRule], appRoutingMode: AppRoutingMode) async {
        guard let core = corePath else {
            lastError = String(localized: "VPN core not found in the app bundle")
            return
        }
        // Быстрая прямая проверка прав. Медленный запрос прав администратора
        // (osascript) — только если sudo реально не настроен.
        if !Self.checkSudo(core: core) {
            await authorize()
            guard Self.checkSudo(core: core) else { return }
        }

        lastError = nil
        isStopping = false
        state = .connecting

        let builder = SingBoxConfigBuilder(servers: servers, autoSelect: autoSelect,
                                           routingMode: routingMode, customRules: customRules,
                                           appRules: appRules, appRoutingMode: appRoutingMode)
        do {
            let json = try builder.buildTunnelConfigJSON()
            try json.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = error.localizedDescription
            state = .disconnected
            return
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard let logHandle = try? FileHandle(forWritingTo: logURL) else {
            lastError = "Cannot open log file"
            state = .disconnected
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        proc.arguments = ["-n", core, "run", "-c", configURL.path, "-D", Self.workDirectory.path]
        proc.standardOutput = logHandle
        proc.standardError = logHandle
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleTermination()
            }
        }

        do {
            try proc.run()
            process = proc
            connectedAt = Date()
            state = .connected
        } catch {
            lastError = error.localizedDescription
            state = .disconnected
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else {
            state = .disconnected
            return
        }
        // Мгновенно показываем «Отключено», а ядро гасим в фоне — снятие
        // маршрутов ядром может занять секунду, но пользователю ждать незачем.
        isStopping = true
        state = .disconnected
        connectedAt = nil
        process = nil
        Task.detached {
            proc.terminate()
            proc.waitUntilExit()
        }
    }

    private func handleTermination() {
        // Пропускаем, если остановку инициировал пользователь (или уже почищено)
        guard !isStopping, process != nil else {
            isStopping = false
            return
        }
        process = nil
        state = .disconnected
        connectedAt = nil
        // Ядро упало само — показываем хвост лога
        if let log = try? String(contentsOf: logURL, encoding: .utf8) {
            let tail = log.split(separator: "\n").suffix(3).joined(separator: "\n")
            if !tail.isEmpty { lastError = tail }
        }
    }

    private func waitForExit(_ process: Process) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }
}
