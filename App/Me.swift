import Foundation
import SplitChecksCore

/// The person using this phone. Optional: without it every screen falls
/// back to neutral wording ("Alex owes Sam"); with it, "you owe Sam".
/// Stored in UserDefaults so views can observe it with `@AppStorage`.
enum Me {
    static let defaultsKey = "me.personID"
    static let onboardedKey = "me.onboarded"

    static var id: Person.ID? {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap { UUID(uuidString: $0) } }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: defaultsKey) }
    }

    static func parse(_ stored: String) -> Person.ID? {
        UUID(uuidString: stored)
    }
}

/// Wording for one group: names people, says "You" for me, and phrases
/// balances and transfers.
struct Namer {
    let group: ExpenseGroup
    let meID: Person.ID?

    func isMe(_ id: Person.ID) -> Bool { id == meID }

    func name(_ id: Person.ID) -> String {
        isMe(id) ? "You" : group.name(of: id)
    }

    func balanceLabel(_ balance: Balance) -> String {
        if balance.cents == 0 { return "settled" }
        let amount = Money.format(abs(balance.cents), currencyCode: group.currencyCode)
        if balance.cents > 0 {
            return isMe(balance.personID) ? "you get back \(amount)" : "gets back \(amount)"
        }
        return isMe(balance.personID) ? "you owe \(amount)" : "owes \(amount)"
    }

    func transferLine(_ transfer: Transfer) -> String {
        let verb = isMe(transfer.fromID) ? "pay" : "pays"
        return "\(name(transfer.fromID)) \(verb) \(name(transfer.toID)) \(Money.format(transfer.cents, currencyCode: group.currencyCode))"
    }

    func paymentLine(_ payment: Payment) -> String {
        "\(name(payment.fromID)) paid \(name(payment.toID))"
    }
}

extension GroupKind {
    var title: String {
        switch self {
        case .trip: return "Trip"
        case .home: return "Home"
        case .couple: return "Couple"
        case .event: return "Event"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .trip: return "airplane"
        case .home: return "house"
        case .couple: return "heart"
        case .event: return "party.popper"
        case .other: return "folder"
        }
    }
}

extension PaymentMethod {
    var title: String {
        switch self {
        case .cash: return "Cash"
        case .venmo: return "Venmo"
        case .paypal: return "PayPal"
        case .cashApp: return "Cash App"
        case .zelle: return "Zelle"
        case .bankTransfer: return "Bank transfer"
        case .other: return "Other"
        }
    }
}

extension Person {
    /// The same person with a chip color chosen for one bill or group.
    func withColorIndex(_ index: Int) -> Person {
        Person(id: id, name: name, colorIndex: index, handles: handles)
    }
}
