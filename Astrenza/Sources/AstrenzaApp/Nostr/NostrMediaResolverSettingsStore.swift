import AstrenzaCore
import Foundation
import Security

struct NostrMediaResolverServiceSettings: CustomDebugStringConvertible, CustomStringConvertible, Equatable, Sendable {
    var serviceURLString: String
    var bearerToken: String
    var isEnabled: Bool

    static let empty = NostrMediaResolverServiceSettings(
        serviceURLString: "",
        bearerToken: "",
        isEnabled: false
    )

    var configuration: NostrMediaResolverServiceConfiguration {
        NostrMediaResolverServiceConfiguration(
            serviceURLString: serviceURLString,
            bearerToken: bearerToken,
            isEnabled: isEnabled
        )
    }

    var description: String {
        "NostrMediaResolverServiceSettings(configuration: \(configuration))"
    }

    var debugDescription: String {
        description
    }
}

struct NostrMediaResolverSettingsStore: @unchecked Sendable {
    static let shared = NostrMediaResolverSettingsStore()
    static let legacyBearerTokenDefaultsKey = "astrenza.media-resolver.bearer-token"

    private let defaults: UserDefaults
    private let bearerTokenStore: NostrMediaResolverBearerTokenStore
    private let serviceURLKey = "astrenza.media-resolver.service-url"
    private let isEnabledKey = "astrenza.media-resolver.enabled"

    init(
        defaults: UserDefaults = .standard,
        bearerTokenStore: NostrMediaResolverBearerTokenStore = .keychain
    ) {
        self.defaults = defaults
        self.bearerTokenStore = bearerTokenStore
    }

    func settings() -> NostrMediaResolverServiceSettings {
        NostrMediaResolverServiceSettings(
            serviceURLString: defaults.string(forKey: serviceURLKey) ?? "",
            bearerToken: migratedBearerToken(),
            isEnabled: defaults.bool(forKey: isEnabledKey)
        )
    }

    func save(_ settings: NostrMediaResolverServiceSettings) {
        defaults.set(settings.serviceURLString, forKey: serviceURLKey)
        defaults.set(settings.isEnabled, forKey: isEnabledKey)
        defaults.removeObject(forKey: Self.legacyBearerTokenDefaultsKey)
        bearerTokenStore.save(settings.bearerToken)
    }

    func configuration() -> NostrMediaResolverServiceConfiguration {
        settings().configuration
    }

    private func migratedBearerToken() -> String {
        let storedToken = bearerTokenStore.token()
        if !storedToken.isEmpty {
            defaults.removeObject(forKey: Self.legacyBearerTokenDefaultsKey)
            return storedToken
        }

        let legacyToken = (defaults.string(forKey: Self.legacyBearerTokenDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyToken.isEmpty else {
            defaults.removeObject(forKey: Self.legacyBearerTokenDefaultsKey)
            return ""
        }

        bearerTokenStore.save(legacyToken)
        defaults.removeObject(forKey: Self.legacyBearerTokenDefaultsKey)
        return legacyToken
    }
}

struct NostrMediaResolverBearerTokenStore: Sendable {
    let token: @Sendable () -> String
    let save: @Sendable (String) -> Void

    static let keychain = NostrMediaResolverBearerTokenStore(
        token: {
            NostrMediaResolverKeychainBearerTokenStore.shared.token()
        },
        save: { token in
            NostrMediaResolverKeychainBearerTokenStore.shared.save(token)
        }
    )
}

private final class NostrMediaResolverKeychainBearerTokenStore: @unchecked Sendable {
    static let shared = NostrMediaResolverKeychainBearerTokenStore()

    private let service = "com.ikuradon.Astrenza.media-resolver"
    private let account = "bearer-token"

    func token() -> String {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return "" }
        return token
    }

    func save(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            SecItemDelete(baseQuery() as CFDictionary)
            return
        }

        let data = Data(trimmedToken.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery() as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        guard updateStatus == errSecItemNotFound else { return }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
