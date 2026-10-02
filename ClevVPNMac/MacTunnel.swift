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
    /// Ядро найдено (Homebrew или в бандле).
    @Published private(set) var corePath: String?
    /// Разрешение sudo без пароля настроено.
    @Published private(set) var isAuthorized = false

    private var process: Process?
    /// Остановка инициирована пользователем — не показывать «ядро упало».
    private var isStopping = false

    private static let coreCandidates = [
        "/opt/homebrew/bin/sing-box",
        "/usr/local/bin/sing-box"
    ]

    static let workDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClevVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var configURL: URL { Self.workDirectory.appendingPathComponent("config.json") }
    private var logURL: URL { Self.workDirectory.appendingPathComponent("core.log") }

    init() {
        refreshEnvironment()
    }

    /// Проверяет наличие ядра и права sudo. Запуск sudo — в фоне, чтобы не
    /// блокировать интерфейс при старте/обновлении.
    func refreshEnvironment() {
        corePath = Self.coreCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? Bundle.main.path(forResource: "sing-box", ofType: nil)
        let core = corePath
        Task.detached(priority: .utility) {
            let ok = Self.checkSudo(core: core)
            await MainActor.run { self.isAuthorized = ok }
        }
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
            } else {
                lastError = nil
            }
        } catch {
            lastError = error.localizedDescription
        }
        isAuthorized = Self.checkSudo(core: corePath)
    }

    // MARK: - Запуск/остановка

    func start(servers: [Server],
               routingMode: RoutingMode, customRules: [RoutingRule],
               appRules: [AppRule], appRoutingMode: AppRoutingMode) async {
        guard let core = corePath else {
            lastError = String(localized: "sing-box core not found. Install it: brew install sing-box")
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

        // Mac выбирает один сервер на UI; urltest/autoSelect остаётся для iOS.
        let builder = SingBoxConfigBuilder(servers: servers, autoSelect: false,
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
            // Ядро упало само — короткое понятное сообщение, не сырой хвост лога
            lastError = String(localized: "Tunnel stopped unexpectedly")
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
