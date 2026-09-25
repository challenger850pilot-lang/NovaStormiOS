import Foundation

/// Tolerant accessors for the loosely typed JSON Xtream servers return (numbers as strings, etc.).
struct JObj {
    let d: [String: Any]
    init(_ d: [String: Any]) { self.d = d }

    func s(_ k: String, _ def: String = "") -> String {
        guard let v = d[k] else { return def }
        if let x = v as? String { return x }
        if let x = v as? NSNumber { return x.stringValue }
        return def
    }

    func i(_ k: String, _ def: Int = 0) -> Int {
        guard let v = d[k] else { return def }
        if let x = v as? NSNumber { return x.intValue }
        if let x = v as? String, let n = Int(x.trimmingCharacters(in: .whitespaces)) { return n }
        return def
    }

    func l(_ k: String, _ def: Int64 = 0) -> Int64 {
        guard let v = d[k] else { return def }
        if let x = v as? NSNumber { return x.int64Value }
        if let x = v as? String, let n = Int64(x.trimmingCharacters(in: .whitespaces)) { return n }
        return def
    }

    func obj(_ k: String) -> JObj? { (d[k] as? [String: Any]).map(JObj.init) }
    func arr(_ k: String) -> [JObj] { JObj.objects(d[k] ?? []) }
    func strArr(_ k: String) -> [String] { (d[k] as? [Any])?.compactMap { $0 as? String } ?? [] }
    func dict(_ k: String) -> [String: Any] { (d[k] as? [String: Any]) ?? [:] }

    static func parse(_ data: Data) throws -> Any { try JSONSerialization.jsonObject(with: data) }
    static func objects(_ any: Any) -> [JObj] {
        (any as? [Any])?.compactMap { ($0 as? [String: Any]).map(JObj.init) } ?? []
    }
    static func object(_ any: Any) -> JObj { JObj((any as? [String: Any]) ?? [:]) }
}
