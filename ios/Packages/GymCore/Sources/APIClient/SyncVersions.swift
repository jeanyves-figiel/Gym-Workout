import Foundation

/// A synced record that remembers the server `updatedAt` of the copy it was last pulled or saved as. Uploads send it
/// back as `baseUpdatedAt`, so the server never overwrites a newer copy (another device's edit) with an older edit.
public protocol ServerVersioned: Identifiable where ID == UUID {
    /// The server's `updatedAt`, kept as the exact text it sent (compared as text by the server); nil for a record
    /// the server never had, or one kept from before versions were tracked (uploaded as before, no check).
    var updatedAt: String? { get set }
}

/// One upload item: the record, plus `baseUpdatedAt` when its version is known.
struct VersionedUpload<T: Encodable & ServerVersioned>: Encodable {
    var item: T

    private enum Keys: String, CodingKey { case baseUpdatedAt }

    func encode(to encoder: any Encoder) throws {
        try item.encode(to: encoder)
        guard let base = item.updatedAt else { return }
        // Same keyed container as the record's own fields: one flat JSON object.
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(base, forKey: .baseUpdatedAt)
    }
}

/// Answer of a `POST /v1/me/<kind>` upload: when it was written, and server copies of the items it refused.
struct UploadResponse<T: Decodable>: Decodable {
    var serverTime: String?
    var conflicts: LossyArray<T>?
}

/// Ids of the refused items, read on their own so a server copy this app can't decode still counts as refused.
struct UploadConflictIds: Decodable {
    struct Item: Decodable { var id: UUID }
    var conflicts: LossyArray<Item>?
}

/// What an upload of versioned records came back with.
public struct UploadResult<T: Sendable>: Sendable {
    /// Server copies of records it kept instead of this upload: changed elsewhere since the edit's base.
    public var conflicts: [T]
    /// Ids of all refused records (including any whose server copy didn't decode).
    public var conflictIds: Set<UUID>
    /// New server version of each record written, by id. Empty when the server didn't say (older server).
    public var versions: [UUID: String]

    public init(conflicts: [T] = [], conflictIds: Set<UUID> = [], versions: [UUID: String] = [:]) {
        self.conflicts = conflicts
        self.conflictIds = conflictIds
        self.versions = versions
    }

    /// Nothing to apply locally.
    public var isEmpty: Bool { conflictIds.isEmpty && versions.isEmpty }
}

extension UploadResult where T: ServerVersioned & Decodable {
    /// Adds one request's answer for the `uploaded` chunk; a missing or unreadable answer adds nothing.
    mutating func add(_ response: UploadResponse<T>?, ids: UploadConflictIds?, uploaded: [T]) {
        let copies = response?.conflicts?.elements ?? []
        let refused = Set(copies.map(\.id)).union(ids?.conflicts?.elements.map(\.id) ?? [])
        conflicts += copies
        conflictIds.formUnion(refused)
        guard let time = response?.serverTime else { return }
        for item in uploaded where !refused.contains(item.id) { versions[item.id] = time }
    }
}

extension UploadResult where T: ServerVersioned {
    /// The answer applied to a local list and its upload queue. A refused record takes the server copy and leaves the
    /// queue: the server's copy is newer, so this device's edit gives way instead of silently overwriting it. A written
    /// one keeps its new version as the base of its next edit (also when edited again meanwhile: that edit builds on
    /// the copy just written). Records no longer in `list` (deleted meanwhile) stay out.
    public func applied(to list: [T], pending: Set<UUID>) -> (list: [T], pending: Set<UUID>) {
        let copies = Dictionary(conflicts.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })
        var out = list
        for i in out.indices {
            let id = out[i].id
            if let server = copies[id] {
                out[i] = server
            } else if !conflictIds.contains(id), let v = versions[id] {
                out[i].updatedAt = v
            }
        }
        return (out, pending.subtracting(conflictIds))
    }
}
