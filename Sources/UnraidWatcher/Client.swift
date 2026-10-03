import Foundation
import Security

// MARK: - Flexible number decoding (Unraid returns some numbers as strings)

struct Flex: Decodable, Hashable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d }
        else if let s = try? c.decode(String.self), let d = Double(s) { value = d }
        else { value = 0 }
    }
}

// MARK: - Models

struct Overview: Decodable {
    struct Info: Decodable {
        struct OS: Decodable { let hostname: String?; let distro: String?; let release: String?; let uptime: String? }
        struct CPU: Decodable { let brand: String?; let cores: Int?; let threads: Int? }
        let os: OS?; let cpu: CPU?
    }
    struct Metrics: Decodable {
        struct CPU: Decodable { let percentTotal: Double? }
        struct Mem: Decodable { let total: Flex?; let used: Flex?; let percentTotal: Double? }
        let cpu: CPU?; let memory: Mem?
    }
    let info: Info?; let metrics: Metrics?
}

struct Disk: Decodable, Identifiable {
    var id: String { (device ?? "") + (name ?? "") }
    let name: String?; let device: String?; let size: Flex?; let temp: Double?; let status: String?
    let fsSize: Flex?; let fsUsed: Flex?; let fsFree: Flex?
}

struct ArrayInfo: Decodable {
    struct Capacity: Decodable {
        struct KB: Decodable { let free: Flex?; let used: Flex?; let total: Flex? }
        let kilobytes: KB?
    }
    let state: String?; let capacity: Capacity?
    let parities: [Disk]?; let disks: [Disk]?; let caches: [Disk]?
}

struct Container: Decodable, Identifiable {
    let id: String; let names: [String]?; let state: String?; let status: String?; let image: String?
    var displayName: String { (names?.first ?? id).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    var isRunning: Bool { state?.uppercased() == "RUNNING" }
}

struct VM: Decodable, Identifiable { let id: String; let name: String?; let state: String? }

struct Share: Decodable, Identifiable {
    var id: String { name ?? UUID().uuidString }
    let name: String?; let free: Flex?; let used: Flex?; let size: Flex?; let comment: String?
}

struct NotificationItem: Decodable, Identifiable {
    let id: String; let title: String?; let subject: String?; let description: String?
    let importance: String?; let timestamp: String?
}
struct NotificationCounts: Decodable { let info: Int?; let warning: Int?; let alert: Int?; let total: Int? }

struct SystemDetails: Decodable {
    struct Info: Decodable {
        struct Mfr: Decodable { let manufacturer: String?; let model: String?; let version: String? }
        struct OS: Decodable { let kernel: String?; let arch: String?; let platform: String? }
        struct CPU: Decodable { let manufacturer: String?; let speed: Flex?; let speedmax: Flex?; let socket: String? }
        struct Versions: Decodable { struct Core: Decodable { let unraid: String?; let kernel: String?; let api: String? }; let core: Core? }
        let baseboard: Mfr?; let system: Mfr?; let os: OS?; let cpu: CPU?; let versions: Versions?
    }
    let info: Info?
}

struct DiskExtra: Decodable {
    let name: String?; let fsType: String?; let numErrors: Flex?; let isSpinning: Bool?
    let numReads: Flex?; let numWrites: Flex?; let rotational: Bool?
}

struct ContainerExtra: Decodable {
    struct Port: Decodable { let ip: String?; let privatePort: Int?; let publicPort: Int?; let type: String? }
    let id: String; let autoStart: Bool?; let created: Flex?; let ports: [Port]?
}

struct UPS: Decodable, Identifiable {
    struct Battery: Decodable { let chargeLevel: Double?; let estimatedRuntime: Double? }
    struct Power: Decodable { let loadPercentage: Double?; let inputVoltage: Double?; let outputVoltage: Double? }
    let id: String; let name: String?; let model: String?; let status: String?
    let battery: Battery?; let power: Power?
}

struct ParityCheck: Decodable, Identifiable {
    var id: String { (date ?? "") + String(speed ?? "") }
    let date: String?; let duration: Flex?; let speed: String?; let status: String?; let errors: Flex?
}

struct LStr: Decodable, Hashable {
    let s: String
    init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let v = try? c.decode(String.self) { s = v }
        else if let v = try? c.decode(Double.self) { s = v.rounded() == v ? String(Int(v)) : String(v) }
        else if let v = try? c.decode(Bool.self) { s = v ? "Yes" : "No" }
        else { s = "-" }
    }
}
struct Registration: Decodable { let type: LStr?; let state: LStr?; let expiration: LStr?; let updateExpiration: LStr? }
struct Service: Decodable, Identifiable { var id: String { name ?? "" }; let name: String?; let online: Bool?; let version: LStr? }
struct Flash: Decodable { let guid: LStr?; let vendor: LStr?; let product: LStr? }
struct ServerVars: Decodable {
    let name: LStr?; let version: LStr?; let regTy: LStr?; let regState: LStr?; let timeZone: LStr?
    let mdNumDisks: LStr?; let fsState: LStr?; let safeMode: LStr?; let shareCount: LStr?
}

// MARK: - Client

enum UnraidError: LocalizedError {
    case notConfigured, http(Int), graphql(String)
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add your server URL and API key in Settings."
        case .http(let c): return c == 401 || c == 403 ? "Unauthorized (HTTP \(c)) - check the API key." : "HTTP \(c)"
        case .graphql(let m): return m
        }
    }
}

struct Envelope<T: Decodable>: Decodable {
    struct E: Decodable { let message: String }
    let data: T?; let errors: [E]?
}

final class UnraidClient: NSObject, URLSessionDelegate {
    let baseURL: URL; let apiKey: String; let allowInsecure: Bool
    private lazy var session = URLSession(configuration: {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        return c
    }(), delegate: self, delegateQueue: nil)

    init(baseURL: URL, apiKey: String, allowInsecure: Bool) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.allowInsecure = allowInsecure
    }

    func urlSession(_ s: URLSession, didReceive ch: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInsecure, ch.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = ch.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else { completionHandler(.performDefaultHandling, nil) }
    }

    func query<T: Decodable>(_ q: String, as: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": q])
        let (data, resp) = try await session.data(for: req)
        if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { throw UnraidError.http(h.statusCode) }
        let env = try JSONDecoder().decode(Envelope<T>.self, from: data)
        if let d = env.data { return d }
        throw UnraidError.graphql(env.errors?.map(\.message).joined(separator: "; ") ?? "Empty response")
    }
}

// MARK: - Keychain

enum Keychain {
    static func get(_ key: String) -> String {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
    static func set(_ key: String, _ value: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base; add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
