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

    /// A trip with balances worth showing, plus a lighter second trip so the
    /// Trips list looks lived-in. Inserted so the richer trip sorts first.
    static func seed(into context: ModelContext) {
        let taylor = Person(name: "Taylor", colorIndex: 3)
        let robin = Person(name: "Robin", colorIndex: 4)
        var tacos = Trip(name: "Taco Tuesday", people: [taylor, robin])
        tacos.expenses = [
            Expense(title: "Tacos & margs", payerID: taylor.id, amountCents: 4200,
                    split: .equally(participantIDs: [taylor.id, robin.id]))
        ]
        context.insert(SavedTrip(trip: tacos))

        let alex = Person(name: "Alex", colorIndex: 0)
        let sam = Person(name: "Sam", colorIndex: 1)
        let jordan = Person(name: "Jordan", colorIndex: 2)
        var lisbon = Trip(name: "Lisbon Trip", people: [alex, sam, jordan])
        lisbon.expenses = [
            Expense(title: "Seafood dinner", payerID: alex.id, amountCents: 12600,
                    split: .equally(participantIDs: [alex.id, sam.id, jordan.id])),
            Expense(title: "Airbnb", payerID: sam.id, amountCents: 42000,
                    split: .equally(participantIDs: [alex.id, sam.id, jordan.id])),
            Expense(title: "Tram tickets", payerID: jordan.id, amountCents: 1800,
                    split: .equally(participantIDs: [alex.id, sam.id, jordan.id])),
            Expense(title: "Pastéis de nata", payerID: alex.id, amountCents: 900,
                    split: .equally(participantIDs: [alex.id, sam.id])),
        ]
        context.insert(SavedTrip(trip: lisbon))
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
