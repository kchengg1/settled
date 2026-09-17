import Foundation

/// One person's net position in a group, in cents.
/// Positive means the group owes them; negative means they owe the group.
public struct Balance: Identifiable, Hashable, Sendable {
    public var id: Person.ID { personID }
    public let personID: Person.ID
    public var cents: Int
}

/// A single "settle up" payment: `from` pays `to` this many cents.
public struct Transfer: Hashable, Sendable {
    public let fromID: Person.ID
    public let toID: Person.ID
    public let cents: Int

    public init(fromID: Person.ID, toID: Person.ID, cents: Int) {
        self.fromID = fromID
        self.toID = toID
        self.cents = cents
    }
}

public struct Settlement: Sendable {
    /// Net balances in the group's people order. Always sums to zero.
    public var balances: [Balance]
    /// The payments that settle everyone up: minimized when the group
    /// simplifies debts, otherwise pairwise as incurred.
    public var transfers: [Transfer]
    public var isSimplified: Bool
}

/// Derives balances and settle-up payments for a group. Pure functions over
/// value types, so the whole thing is unit-testable with no UI or storage.
public enum SettlementEngine {

    /// The cents each person owes for one expense. Always sums to the
    /// expense amount for the computed methods; `.exactCents` is trusted.
    /// Unknown people and non-positive weights are ignored; an `.equally`
    /// split with no valid participants falls back to the payer, so money
    /// is never created or lost.
    public static func owedShares(for expense: Expense, knownPeople: Set<Person.ID>) -> [Person.ID: Int] {
        switch expense.split {
        case .equally(let participantIDs):
            let valid = participantIDs.filter { knownPeople.contains($0) }
            let recipients = valid.isEmpty ? [expense.payerID] : valid
            let cents = SplitEngine.apportion(expense.amountCents, weights: Array(repeating: 1, count: recipients.count))
            return Dictionary(uniqueKeysWithValues: zip(recipients, cents))

        case .shares(let weights):
            return apportionWeighted(expense.amountCents, weights: weights, knownPeople: knownPeople, payerID: expense.payerID)

        case .percentages(let bips):
            return apportionWeighted(expense.amountCents, weights: bips, knownPeople: knownPeople, payerID: expense.payerID)

        case .exactCents(let cents):
            return cents.filter { knownPeople.contains($0.key) }
        }
    }

    private static func apportionWeighted(
        _ amount: Int,
        weights: [Person.ID: Int],
        knownPeople: Set<Person.ID>,
        payerID: Person.ID
    ) -> [Person.ID: Int] {
        // Deterministic order by the weights' keys, filtered to valid people.
        let entries = weights.filter { knownPeople.contains($0.key) && $0.value > 0 }
        guard !entries.isEmpty else {
            return [payerID: amount]
        }
        let ids = Array(entries.keys)
        let cents = SplitEngine.apportion(amount, weights: ids.map { entries[$0]! })
        return Dictionary(uniqueKeysWithValues: zip(ids, cents))
    }

    /// Net balance per person, in the group's people order. Sums to zero.
    /// Deleted entries don't count; a payment moves its amount from payer
    /// to payee.
    public static func balances(for group: ExpenseGroup) -> [Balance] {
        let known = Set(group.people.map(\.id))
        var net = Dictionary(uniqueKeysWithValues: group.people.map { ($0.id, 0) })
        for entry in group.liveEntries {
            switch entry {
            case .expense(let expense):
                net[expense.payerID, default: 0] += expense.amountCents
                for (personID, owed) in owedShares(for: expense, knownPeople: known) {
                    net[personID, default: 0] -= owed
                }
            case .payment(let payment):
                guard known.contains(payment.fromID), known.contains(payment.toID) else { continue }
                net[payment.fromID, default: 0] += payment.cents
                net[payment.toID, default: 0] -= payment.cents
            }
        }
        return group.people.map { Balance(personID: $0.id, cents: net[$0.id] ?? 0) }
    }

    /// Debts as they were incurred, netted per pair of people: for every
    /// expense each participant owes the payer their share, and a payment
    /// reduces what the payer owed the payee. One transfer per pair with a
    /// non-zero net, in people order. Never rearranges who owes whom, which
    /// is what people expect to see unless they ask for simplification.
    public static func pairwiseDebts(for group: ExpenseGroup) -> [Transfer] {
        let known = Set(group.people.map(\.id))
        var owed: [Pair: Int] = [:]
        for entry in group.liveEntries {
            switch entry {
            case .expense(let expense):
                for (personID, cents) in owedShares(for: expense, knownPeople: known) where personID != expense.payerID {
                    owed[Pair(personID, expense.payerID), default: 0] += cents
                }
            case .payment(let payment):
                owed[Pair(payment.fromID, payment.toID), default: 0] -= payment.cents
            }
        }

        var transfers: [Transfer] = []
        let ids = group.people.map(\.id)
        for i in ids.indices {
            for j in ids.indices where j > i {
                let net = (owed[Pair(ids[i], ids[j])] ?? 0) - (owed[Pair(ids[j], ids[i])] ?? 0)
                if net > 0 {
                    transfers.append(Transfer(fromID: ids[i], toID: ids[j], cents: net))
                } else if net < 0 {
                    transfers.append(Transfer(fromID: ids[j], toID: ids[i], cents: -net))
                }
            }
        }
        return transfers
    }

    private struct Pair: Hashable {
        let from: Person.ID
        let to: Person.ID
        init(_ from: Person.ID, _ to: Person.ID) {
            self.from = from
            self.to = to
        }
    }

    /// Greedy minimum-cash-flow settlement: repeatedly send the largest
    /// remaining debt to the largest remaining credit. Produces at most
    /// `people.count - 1` transfers that clear every balance exactly.
    /// Ties break by the balances' order, so the result is deterministic.
    public static func simplify(_ balances: [Balance]) -> [Transfer] {
        var creditors = balances.enumerated()
            .filter { $0.element.cents > 0 }
            .map { (id: $0.element.personID, amount: $0.element.cents, order: $0.offset) }
            .sorted { ($0.amount, -$0.order) > ($1.amount, -$1.order) }
        var debtors = balances.enumerated()
            .filter { $0.element.cents < 0 }
            .map { (id: $0.element.personID, amount: -$0.element.cents, order: $0.offset) }
            .sorted { ($0.amount, -$0.order) > ($1.amount, -$1.order) }

        var transfers: [Transfer] = []
        var ci = 0, di = 0
        while ci < creditors.count && di < debtors.count {
            let pay = min(creditors[ci].amount, debtors[di].amount)
            transfers.append(Transfer(fromID: debtors[di].id, toID: creditors[ci].id, cents: pay))
            creditors[ci].amount -= pay
            debtors[di].amount -= pay
            if creditors[ci].amount == 0 { ci += 1 }
            if debtors[di].amount == 0 { di += 1 }
        }
        return transfers
    }

    /// Balances plus the transfers to show, honoring `group.simplifyDebts`.
    public static func settlement(for group: ExpenseGroup) -> Settlement {
        let bals = balances(for: group)
        let transfers = group.simplifyDebts ? simplify(bals) : pairwiseDebts(for: group)
        return Settlement(balances: bals, transfers: transfers, isSimplified: group.simplifyDebts)
    }

    /// Net of a set of transfers per person (received minus sent), for
    /// checking that a transfer list clears a balance list.
    public static func netOfTransfers(_ transfers: [Transfer], people: [Person.ID]) -> [Person.ID: Int] {
        var net = Dictionary(uniqueKeysWithValues: people.map { ($0, 0) })
        for t in transfers {
            net[t.fromID, default: 0] -= t.cents
            net[t.toID, default: 0] += t.cents
        }
        return net
    }
}
