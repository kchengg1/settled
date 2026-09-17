import Foundation
import SwiftData
import SplitChecksCore

/// Sample data used only for App Store screenshots. Activated by the
/// `UITEST_SCREENSHOTS` launch argument, which routes the app to an in-memory
/// store — it never touches a real user's data.
enum DemoData {

    static var isScreenshotRun: Bool {
        ProcessInfo.processInfo.arguments.contains("UITEST_SCREENSHOTS")
    }

    /// A trip with balances, a recorded payment, and activity worth
    /// showing, plus a lighter second group so the list looks lived-in.
    /// "Alex" is *me*, so the screens use "you" wording.
    static func seed(into context: ModelContext) {
        let alex = Person(name: "Alex", colorIndex: 0)
        let sam = Person(name: "Sam", colorIndex: 1)
        let jordan = Person(name: "Jordan", colorIndex: 2)
        let taylor = Person(name: "Taylor", colorIndex: 3)
        let robin = Person(name: "Robin", colorIndex: 4)
        for person in [alex, sam, jordan, taylor, robin] {
            context.insert(SavedPerson(person: person))
        }

        let defaults = UserDefaults.standard
        defaults.set(alex.id.uuidString, forKey: Me.defaultsKey)
        defaults.set(true, forKey: Me.onboardedKey)
        defaults.set(true, forKey: PeopleDirectory.backfilledKey)

        let day: TimeInterval = 86_400
        var tacos = ExpenseGroup(name: "Taco Tuesday", kind: .event, people: [alex, taylor, robin])
        tacos.apply(.addEntry(.expense(Expense(title: "Tacos & margs", payerID: taylor.id, amountCents: 6300,
                                               date: .now.addingTimeInterval(-3 * day),
                                               split: .equally(participantIDs: [alex.id, taylor.id, robin.id])))),
                    by: alex.id, at: .now.addingTimeInterval(-3 * day))
        context.insert(SavedTrip(group: tacos))

        var lisbon = ExpenseGroup(name: "Lisbon Trip", kind: .trip, people: [alex, sam, jordan])
        let entries: [(LedgerEntry, TimeInterval)] = [
            (.expense(Expense(title: "Airbnb", payerID: sam.id, amountCents: 42000, date: .now.addingTimeInterval(-6 * day),
                              split: .equally(participantIDs: [alex.id, sam.id, jordan.id]))), -6 * day),
            (.expense(Expense(title: "Seafood dinner", payerID: alex.id, amountCents: 12600, date: .now.addingTimeInterval(-5 * day),
                              split: .equally(participantIDs: [alex.id, sam.id, jordan.id]))), -5 * day),
            (.expense(Expense(title: "Tram tickets", payerID: jordan.id, amountCents: 1800, date: .now.addingTimeInterval(-4 * day),
                              split: .equally(participantIDs: [alex.id, sam.id, jordan.id]))), -4 * day),
            (.expense(Expense(title: "Pastéis de nata", payerID: alex.id, amountCents: 900, date: .now.addingTimeInterval(-2 * day),
                              split: .equally(participantIDs: [alex.id, sam.id]))), -2 * day),
            (.payment(Payment(fromID: jordan.id, toID: sam.id, cents: 5000, date: .now.addingTimeInterval(-1 * day),
                              method: .venmo)), -1 * day),
        ]
        for (entry, offset) in entries {
            lisbon.apply(.addEntry(entry), by: alex.id, at: .now.addingTimeInterval(offset))
        }
        context.insert(SavedTrip(group: lisbon))
    }

    /// A finished-looking receipt for the Receipt tab: items that sum to the
    /// scanned subtotal, so the green "items add up" checksum shows.
    static func receiptModel() -> BillFlowModel {
        let model = BillFlowModel()
        model.merchantName = "Trattoria Roma"
        model.items = [
            LineItem(name: "Margherita", priceCents: 1400),
            LineItem(name: "Carbonara", priceCents: 1650),
            LineItem(name: "Tiramisu", priceCents: 800),
            LineItem(name: "Espresso", quantity: 2, priceCents: 600),
        ]
        model.scannedSubtotalCents = 4450 // == sum of items
        model.taxCents = 400
        return model
    }
}
