import Foundation
import Security

/// Tiny wrapper over the Keychain for the few secrets the app holds: the keys the user
/// typed into Settings and the Spotify tokens. Nothing leaves the device.
enum Keychain {
    private static let service = "io.anes.lyngotunes"
    /// Result of the last write, shown in the Debug counters so a failing Keychain is visible.
    private(set) static var lastWriteStatus: OSStatus = errSecSuccess

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func data(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    static func set(_ data: Data?, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard let data, !data.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        lastWriteStatus = SecItemAdd(q as CFDictionary, nil)
    }

    static func string(_ account: String) -> String {
        data(account).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func set(_ string: String, for account: String) {
        set(Data(string.utf8), for: account)
    }
}
