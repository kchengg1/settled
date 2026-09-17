import Foundation

/// How one expense's cost is divided among the people it covers.
/// All variants resolve to integer-cents owed shares that sum exactly to the
/// expense amount (via the same largest-remainder apportionment as bills).
public enum SplitMethod: Hashable, Codable, Sendable {
    /// Divided evenly among these participants.
    case equally(participantIDs: [Person.ID])
    /// Divided in proportion to per-person weights (e.g. 2:1).
    case shares([Person.ID: Int])
    /// Divided by per-person basis points (10_000 = 100%).
    case percentages([Person.ID: Int])
    /// Exact per-person cents. The caller guarantees these sum to the amount.
    case exactCents([Person.ID: Int])

    /// Everyone the split names, in a deterministic order.
    public var participantIDs: [Person.ID] {
        switch self {
        case .equally(let ids): return ids
        case .shares(let map), .percentages(let map), .exactCents(let map):
            return map.keys.sorted { $0.uuidString < $1.uuidString }
        }
    }
}

/// A single cost in a group: who paid, how much, and how it's shared.
/// A scanned, itemized receipt becomes one of these with an `.exactCents`
/// split built from the per-person totals the bill engine computed.
///
/// Expenses are never hard-deleted from a group's ledger: `isDeleted` is a
/// tombstone so a delete can be undone, shows in the activity feed, and
/// survives a merge with another device's copy.
public struct Expense: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var title: String
    public var payerID: Person.ID
    public var amountCents: Int
    public var date: Date
    public var split: SplitMethod
    public var isDeleted: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        payerID: Person.ID,
        amountCents: Int,
        date: Date = .now,
        split: SplitMethod,
        isDeleted: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.payerID = payerID
        self.amountCents = amountCents
        self.date = date
        self.split = split
        self.isDeleted = isDeleted
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    /// True when this person paid or owes anything on this expense.
    public func references(_ personID: Person.ID) -> Bool {
        payerID == personID || split.participantIDs.contains(personID)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, payerID, amountCents, date, split, isDeleted, createdAt, updatedAt
    }

    /// Trips saved before the ledger existed have no tombstone or
    /// timestamps; they decode as live entries created on their date.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        payerID = try c.decode(Person.ID.self, forKey: .payerID)
        amountCents = try c.decode(Int.self, forKey: .amountCents)
        date = try c.decode(Date.self, forKey: .date)
        split = try c.decode(SplitMethod.self, forKey: .split)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        let created = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? date
        createdAt = created
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? created
    }
}
