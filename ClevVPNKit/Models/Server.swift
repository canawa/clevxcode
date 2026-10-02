import Foundation

/// Протокол сервера. Все типы, которые отдаёт Remnawave в share-ссылках.
public enum VPNProtocol: String, Codable, CaseIterable, Sendable {
    case vless
    case trojan
    case hysteria2
    case shadowsocks

    public var displayName: String {
        switch self {
        case .vless: return "VLESS"
        case .trojan: return "Trojan"
        case .hysteria2: return "Hysteria2"
        case .shadowsocks: return "Shadowsocks"
        }
    }
}

public enum TransportType: String, Codable, Sendable {
    case tcp
    case ws
    case grpc
    case httpupgrade
}

public struct TransportConfig: Codable, Hashable, Sendable {
    public var type: TransportType
    public var path: String?
    public var host: String?
    public var serviceName: String?

    public init(type: TransportType, path: String? = nil, host: String? = nil, serviceName: String? = nil) {
        self.type = type
        self.path = path
        self.host = host
        self.serviceName = serviceName
    }
}

public struct TLSConfig: Codable, Hashable, Sendable {
    public enum Security: String, Codable, Sendable {
        case none
        case tls
        case reality
    }

    public var security: Security
    public var serverName: String?
    public var alpn: [String]
    public var fingerprint: String?
    public var allowInsecure: Bool
    public var realityPublicKey: String?
    public var realityShortID: String?

    public init(security: Security,
                serverName: String? = nil,
                alpn: [String] = [],
                fingerprint: String? = nil,
                allowInsecure: Bool = false,
                realityPublicKey: String? = nil,
                realityShortID: String? = nil) {
        self.security = security
        self.serverName = serverName
        self.alpn = alpn
        self.fingerprint = fingerprint
        self.allowInsecure = allowInsecure
        self.realityPublicKey = realityPublicKey
        self.realityShortID = realityShortID
    }
}

public struct VLESSConfig: Codable, Hashable, Sendable {
    public var uuid: String
    public var flow: String?
    public var tls: TLSConfig
    public var transport: TransportConfig

    public init(uuid: String, flow: String? = nil, tls: TLSConfig, transport: TransportConfig) {
        self.uuid = uuid
        self.flow = flow
        self.tls = tls
        self.transport = transport
    }
}

public struct TrojanConfig: Codable, Hashable, Sendable {
    public var password: String
    public var tls: TLSConfig
    public var transport: TransportConfig

    public init(password: String, tls: TLSConfig, transport: TransportConfig) {
        self.password = password
        self.tls = tls
        self.transport = transport
    }
}

public struct Hysteria2Config: Codable, Hashable, Sendable {
    public var password: String
    public var serverName: String?
    public var allowInsecure: Bool
    public var obfsPassword: String?
    /// Диапазон портов для port hopping, формат "20000:30000" (из mport/ports).
    public var portRange: String?

    public init(password: String,
                serverName: String? = nil,
                allowInsecure: Bool = false,
                obfsPassword: String? = nil,
                portRange: String? = nil) {
        self.password = password
        self.serverName = serverName
        self.allowInsecure = allowInsecure
        self.obfsPassword = obfsPassword
        self.portRange = portRange
    }
}

public struct ShadowsocksConfig: Codable, Hashable, Sendable {
    public var method: String
    public var password: String

    public init(method: String, password: String) {
        self.method = method
        self.password = password
    }
}

public enum ServerKind: Codable, Hashable, Sendable {
    case vless(VLESSConfig)
    case trojan(TrojanConfig)
    case hysteria2(Hysteria2Config)
    case shadowsocks(ShadowsocksConfig)

    public var protocolType: VPNProtocol {
        switch self {
        case .vless: return .vless
        case .trojan: return .trojan
        case .hysteria2: return .hysteria2
        case .shadowsocks: return .shadowsocks
        }
    }
}

/// Один сервер из подписки.
public struct Server: Codable, Identifiable, Hashable, Sendable {
    /// Стабильный id: протокол + хост + порт + полное имя.
    /// Не меняется между обновлениями подписки, пока сервер тот же —
    /// на него ссылаются избранное и пользовательские папки.
    public var id: String
    /// Имя для отображения (без префикса группы).
    public var name: String
    /// Полное имя из подписки (remark).
    public var rawName: String
    /// Описание сервера из панели (Remnawave meta.serverDescription) —
    /// показывается под названием сервера.
    public var descriptionText: String?
    /// Вкладка из админки: префикс "Группа | Имя" в названии хоста Remnawave.
    public var group: String?
    /// ISO-код страны (из флага-эмодзи или текста в имени).
    public var countryCode: String?
    public var host: String
    public var port: Int
    public var kind: ServerKind

    public var protocolType: VPNProtocol { kind.protocolType }

    public init(name: String,
                rawName: String,
                descriptionText: String? = nil,
                group: String? = nil,
                countryCode: String? = nil,
                host: String,
                port: Int,
                kind: ServerKind) {
        self.name = name
        self.rawName = rawName
        self.descriptionText = descriptionText
        self.group = group
        self.countryCode = countryCode
        self.host = host
        self.port = port
        self.kind = kind
        self.id = "\(kind.protocolType.rawValue)://\(host):\(port)#\(rawName)"
    }

    /// Локализованное название страны (по ISO-коду), для баннера подключения.
    public func countryName(locale: Locale = .current) -> String? {
        guard let code = countryCode, code.count == 2 else { return nil }
        return locale.localizedString(forRegionCode: code)
    }

    /// Флаг страны для UI.
    public var flagEmoji: String? {
        guard let code = countryCode, code.count == 2 else { return nil }
        let base: UInt32 = 127397
        var flag = ""
        for scalar in code.uppercased().unicodeScalars {
            guard let flagScalar = UnicodeScalar(base + scalar.value) else { return nil }
            flag.unicodeScalars.append(flagScalar)
        }
        return flag
    }
}
