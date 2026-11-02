import Foundation

final class LocalStore {
    let root: URL
    private let lock = NSRecursiveLock()
    private var values: [String: String]
    private var revision: Int
    let token = UUID().uuidString + UUID().uuidString
    private let stateURL: URL
    private var files: [String: String]

    init(root: URL) throws {
        self.root = root
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        for directory in ["files", "backups"] { try fm.createDirectory(at: root.appendingPathComponent(directory), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        stateURL = root.appendingPathComponent("state.json")
        if fm.fileExists(atPath: stateURL.path) {
            let data = try Data(contentsOf: stateURL)
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String] else { throw NSError(domain: "Zen", code: 1, userInfo: [NSLocalizedDescriptionKey: "~/.zen/state.json 格式不正确。原文件已保留，请从备份恢复。"] ) }
            values = decoded
        } else { values = [:] }
        let fileURL = root.appendingPathComponent("files.json")
        if fm.fileExists(atPath: fileURL.path) { files = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String:String] ?? [:] } else { files = [:] }
        revision = Int(Date().timeIntervalSince1970 * 1000)
        if !fm.fileExists(atPath: stateURL.path) { try write(values, to: stateURL) }
    }
    private func write(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["kind":"zen-disk-store", "storage":values, "revision":revision, "token":token, "migrationPending":FileManager.default.fileExists(atPath: root.appendingPathComponent("migration-pending").path)]
    }
    func set(key: String, value: String?) throws -> [String:Any] {
        lock.lock(); defer { lock.unlock() }
        guard key.hasPrefix("zen-") else { throw StoreError.invalid }
        var next = values
        next[key] = value
        try write(next, to: stateURL); values = next; revision += 1
        return ["revision":revision]
    }
    func clear() throws -> [String:Any] {
        lock.lock(); defer { lock.unlock() }
        try backup(); try write([String:String](), to: stateURL); values = [:]; revision += 1
        return ["revision":revision]
    }
    func bootstrap(_ incoming: [String:String]) throws -> [String:Any] {
        lock.lock(); defer { lock.unlock() }
        if values.isEmpty {
            let clean = incoming.filter { $0.key.hasPrefix("zen-") }
            try write(clean, to: root.appendingPathComponent("backups/browser-migration-\(Int(Date().timeIntervalSince1970)).json"))
            try Data().write(to: root.appendingPathComponent("migration-pending"))
            try write(clean, to: stateURL); values = clean; revision += 1
        }
        return snapshot()
    }
    func completeMigration() throws { lock.lock(); defer { lock.unlock() }; let url = root.appendingPathComponent("migration-pending"); if FileManager.default.fileExists(atPath:url.path) { try FileManager.default.removeItem(at:url) } }
    func backup() throws { lock.lock(); defer { lock.unlock() }; try write(values, to: root.appendingPathComponent("backups/state-\(Int(Date().timeIntervalSince1970)).json")) }
    private func fileURL(_ id: String) throws -> URL {
        guard !id.isEmpty, id.count <= 180, id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "." }), id != ".", id != ".." else { throw StoreError.invalid }
        return root.appendingPathComponent("files").appendingPathComponent(id)
    }
    func putFile(_ id: String, data: Data, mime: String) throws {
        lock.lock(); defer { lock.unlock() }
        let url = try fileURL(id)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:url.path)
        var next = files; next[id] = mime
        try write(next, to: root.appendingPathComponent("files.json")); files = next
    }
    func file(_ id: String) throws -> (Data,String) { lock.lock(); defer { lock.unlock() }; return (try Data(contentsOf:fileURL(id)), files[id] ?? "application/octet-stream") }
    enum StoreError: Error { case invalid }
}
