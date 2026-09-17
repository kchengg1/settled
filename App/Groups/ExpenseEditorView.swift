import SwiftUI
import SplitChecksCore

/// Add or edit a group expense: what, how much, who paid, and how it's
/// split. Editing keeps the expense's identity so the activity trail and
/// balances line up.
struct ExpenseEditorView: View {
    let group: ExpenseGroup
    let existing: Expense?
    let meID: Person.ID?
    let onSave: (Expense) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var amountCents: Int
    @State private var payerID: Person.ID
    @State private var date: Date
    @State private var mode: SplitMode
    @State private var selected: Set<Person.ID>
    @State private var weights: [Person.ID: Int]
    @State private var exact: [Person.ID: Int]

    enum SplitMode: String, CaseIterable {
        case equally = "Equally"
        case shares = "Shares"
        case exact = "Exact"
    }

    init(group: ExpenseGroup, existing: Expense?, meID: Person.ID?, onSave: @escaping (Expense) -> Void) {
        self.group = group
        self.existing = existing
        self.meID = meID
        self.onSave = onSave

        let everyone = group.people.map(\.id)
        let defaultPayer = meID.flatMap { id in everyone.contains(id) ? id : nil } ?? everyone.first ?? UUID()
        _title = State(initialValue: existing?.title ?? "")
        _amountCents = State(initialValue: existing?.amountCents ?? 0)
        _payerID = State(initialValue: existing?.payerID ?? defaultPayer)
        _date = State(initialValue: existing?.date ?? .now)

        var mode: SplitMode = .equally
        var selected = Set(everyone)
        var weights = Dictionary(uniqueKeysWithValues: everyone.map { ($0, 1) })
        var exact: [Person.ID: Int] = [:]
        if let existing {
            switch existing.split {
            case .equally(let ids):
                selected = Set(ids)
            case .shares(let map), .percentages(let map):
                // Basis points are just weights, so percentages edit as shares.
                mode = .shares
                weights = Dictionary(uniqueKeysWithValues: everyone.map { ($0, map[$0] ?? 0) })
            case .exactCents(let map):
                mode = .exact
                exact = map
            }
        }
        _mode = State(initialValue: mode)
        _selected = State(initialValue: selected)
        _weights = State(initialValue: weights)
        _exact = State(initialValue: exact)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What for?", text: $title)
                    HStack {
                        Text("Amount")
                        Spacer()
                        CurrencyField(title: "0.00", cents: $amountCents).frame(width: 110)
                    }
                    Picker("Paid by", selection: $payerID) {
                        ForEach(group.people) { Text(name($0)).tag($0.id) }
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }

                Section("Split") {
                    Picker("Split", selection: $mode) {
                        ForEach(SplitMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(group.people) { person in
                        splitRow(person)
                    }

                    if let hint = remainingHint {
                        Text(hint).font(.footnote).foregroundStyle(hintIsError ? .red : .secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New expense" : "Edit expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { save() }.disabled(!isValid)
                }
            }
        }
    }

    private func name(_ person: Person) -> String {
        person.id == meID ? "You" : person.name
    }

    @ViewBuilder
    private func splitRow(_ person: Person) -> some View {
        switch mode {
        case .equally:
            Button {
                if selected.contains(person.id) { selected.remove(person.id) } else { selected.insert(person.id) }
            } label: {
                HStack {
                    Image(systemName: selected.contains(person.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected.contains(person.id) ? ChipPalette.color(for: person) : .secondary)
                    Text(name(person)).foregroundStyle(.primary)
                    Spacer()
                    if selected.contains(person.id), !selected.isEmpty {
                        Text(Money.format(equalShare(for: person), currencyCode: group.currencyCode))
                            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
        case .shares:
            Stepper(value: Binding(get: { weights[person.id] ?? 0 }, set: { weights[person.id] = max(0, $0) }), in: 0...99) {
                HStack {
                    Text(name(person))
                    Spacer()
                    Text("\(weights[person.id] ?? 0)×").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        case .exact:
            HStack {
                Text(name(person))
                Spacer()
                CurrencyField(title: "0.00", cents: Binding(get: { exact[person.id] ?? 0 }, set: { exact[person.id] = $0 }))
                    .frame(width: 100)
            }
        }
    }

    private func equalShare(for person: Person) -> Int {
        let ids = group.people.map(\.id).filter { selected.contains($0) }
        guard let index = ids.firstIndex(of: person.id) else { return 0 }
        return SplitEngine.apportion(amountCents, weights: Array(repeating: 1, count: ids.count))[index]
    }

    // MARK: - Validation

    private var exactSum: Int { group.people.reduce(0) { $0 + (exact[$1.id] ?? 0) } }
    private var weightSum: Int { weights.values.reduce(0, +) }

    private var isValid: Bool {
        guard amountCents != 0, group.people.contains(where: { $0.id == payerID }) else { return false }
        switch mode {
        case .equally: return !selected.isEmpty
        case .shares: return weightSum > 0
        case .exact: return exactSum == amountCents
        }
    }

    private var remainingHint: String? {
        switch mode {
        case .equally:
            return selected.isEmpty ? "Select at least one person." : nil
        case .shares:
            return weightSum == 0 ? "Give at least one person a share." : nil
        case .exact:
            let diff = amountCents - exactSum
            if diff == 0 { return nil }
            let word = diff > 0 ? "left to assign" : "over"
            return "\(Money.format(abs(diff), currencyCode: group.currencyCode)) \(word)."
        }
    }

    private var hintIsError: Bool {
        switch mode {
        case .exact: return exactSum != amountCents
        default: return true
        }
    }

    private func save() {
        let split: SplitMethod
        switch mode {
        case .equally:
            let ids = group.people.map(\.id).filter { selected.contains($0) }
            split = .equally(participantIDs: ids)
        case .shares:
            split = .shares(weights.filter { $0.value > 0 })
        case .exact:
            split = .exactCents(exact.filter { $0.value != 0 })
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let expense = Expense(
            id: existing?.id ?? UUID(),
            title: cleanTitle.isEmpty ? "Expense" : cleanTitle,
            payerID: payerID,
            amountCents: amountCents,
            date: date,
            split: split,
            createdAt: existing?.createdAt ?? .now,
            updatedAt: .now
        )
        onSave(expense)
        dismiss()
    }
}
