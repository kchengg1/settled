import SwiftUI
import SwiftData
import SplitChecksCore

/// One trip: browse and add expenses, manage people, and see balances with a
/// minimized "settle up". Edits mutate a local `Trip` value and persist back
/// to the `SavedTrip` on every change.
struct TripDetailView: View {
    let saved: SavedTrip
    @State private var trip: Trip
    @State private var mode: Mode = .expenses
    @State private var showingAddExpense = false
    @State private var newPersonName = ""
    @FocusState private var personFieldFocused: Bool

    enum Mode: String, CaseIterable {
        case expenses = "Expenses"
        case balances = "Balances"
        case people = "People"
    }

    init(saved: SavedTrip) {
        self.saved = saved
        _trip = State(initialValue: saved.trip)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            switch mode {
            case .expenses: expensesList
            case .balances: balancesList
            case .people: peopleList
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(trip.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .expenses {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddExpense = true } label: { Label("Add expense", systemImage: "plus") }
                        .disabled(trip.people.isEmpty)
                }
            }
            if mode == .balances {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: settlementText) { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(trip.expenses.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(trip: trip) { expense in
                trip.expenses.insert(expense, at: 0)
            }
        }
        // Any mutation of `trip` is written straight back to storage.
        .onChange(of: trip) { saved.update(from: trip) }
    }

    // MARK: - Expenses

    @ViewBuilder
    private var expensesList: some View {
        if trip.people.isEmpty {
            ContentUnavailableView {
                Label("Add people first", systemImage: "person.2")
            } description: {
                Text("Switch to the People tab to add who's on this trip, then record expenses.")
            }
        } else if trip.expenses.isEmpty {
            ContentUnavailableView {
                Label("No expenses yet", systemImage: "creditcard")
            } description: {
                Text("Tap + to add what someone paid for.")
            }
        } else {
            List {
                ForEach(trip.expenses) { expense in
                    expenseRow(expense)
                }
                .onDelete { offsets in
                    trip.expenses.remove(atOffsets: offsets)
                }
                Section {
                    HStack {
                        Text("Total").fontWeight(.semibold)
                        Spacer()
                        Text(Money.format(trip.totalCents, currencyCode: trip.currencyCode))
                            .monospacedDigit().fontWeight(.semibold)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                Text("Paid by \(name(expense.payerID)) · \(splitSummary(expense))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(expense.amountCents, currencyCode: trip.currencyCode))
                .monospacedDigit()
                .foregroundStyle(expense.amountCents < 0 ? .green : .primary)
        }
    }

    // MARK: - Balances & settle up

    private var balancesList: some View {
        let settlement = SettlementEngine.settlement(for: trip)
        return ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(settlement.balances) { balance in
                        balanceCard(balance)
                    }
                }
                settleUpCard(settlement.transfers)
            }
            .padding(16)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    private func balanceCard(_ balance: Balance) -> some View {
        let person = trip.people.first { $0.id == balance.personID }
        return HStack(spacing: 12) {
            Avatar(name: person?.name ?? "?", colorIndex: person?.colorIndex ?? 0, size: 36)
            Text(person?.name ?? "?")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Spacer()
            if balance.cents == 0 {
                Text("settled").font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.muted)
            } else {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(balance.cents > 0 ? "gets back" : "owes")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                    Text(Money.format(abs(balance.cents), currencyCode: trip.currencyCode))
                        .font(.system(size: 16, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(balance.cents > 0 ? Palette.positive : Palette.negative)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func settleUpCard(_ transfers: [Transfer]) -> some View {
        VStack(spacing: 0) {
            if transfers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: trip.expenses.isEmpty ? "tray" : "checkmark.seal.fill")
                        .foregroundStyle(trip.expenses.isEmpty ? Palette.muted : Palette.positive)
                    Text(trip.expenses.isEmpty ? "Nothing to settle yet" : "All settled up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(14)
            } else {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.positive)
                    Text("Settle up in \(transfers.count) payment\(transfers.count == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 9)

                ForEach(Array(transfers.enumerated()), id: \.offset) { index, transfer in
                    if index > 0 {
                        Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 14)
                    }
                    settleRow(transfer)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.cardBorder, lineWidth: 1))
    }

    private func settleRow(_ transfer: Transfer) -> some View {
        HStack(spacing: 9) {
            Avatar(name: name(transfer.fromID), colorIndex: colorIndex(transfer.fromID), size: 27)
            Text(name(transfer.fromID)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
            Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
            Avatar(name: name(transfer.toID), colorIndex: colorIndex(transfer.toID), size: 27)
            Text(name(transfer.toID)).font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
            Spacer()
            Text(Money.format(transfer.cents, currencyCode: trip.currencyCode))
                .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func colorIndex(_ id: Person.ID) -> Int {
        trip.people.first { $0.id == id }?.colorIndex ?? 0
    }

    // MARK: - People

    private var peopleList: some View {
        List {
            Section {
                ForEach(trip.people) { person in
                    HStack {
                        PersonChip(person: person)
                        Spacer()
                        if isReferenced(person) {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    // Only remove people not tied to any expense, so balances
                    // stay consistent.
                    let removable = offsets.filter { !isReferenced(trip.people[$0]) }
                    trip.people.remove(atOffsets: IndexSet(removable))
                }
            } footer: {
                Text("People in an expense can't be removed. A locked icon marks them.")
            }

            Section {
                HStack {
                    TextField("Add person", text: $newPersonName)
                        .focused($personFieldFocused)
                        .submitLabel(.done)
                        .onSubmit(addPerson)
                    Button(action: addPerson) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .disabled(newPersonName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("Add person")
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func addPerson() {
        let trimmed = newPersonName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        trip.people.append(Person(name: trimmed, colorIndex: trip.people.count))
        newPersonName = ""
        personFieldFocused = true
    }

    // MARK: - Helpers

    private func name(_ id: Person.ID) -> String {
        trip.people.first { $0.id == id }?.name ?? "?"
    }

    private func isReferenced(_ person: Person) -> Bool {
        trip.expenses.contains { expense in
            if expense.payerID == person.id { return true }
            switch expense.split {
            case .equally(let ids): return ids.contains(person.id)
            case .shares(let w): return w[person.id] != nil
            case .percentages(let p): return p[person.id] != nil
            case .exactCents(let c): return c[person.id] != nil
            }
        }
    }

    private func splitSummary(_ expense: Expense) -> String {
        switch expense.split {
        case .equally(let ids): return "split \(ids.count) ways"
        case .shares: return "by shares"
        case .percentages: return "by percent"
        case .exactCents: return "exact amounts"
        }
    }

    private var settlementText: String {
        let settlement = SettlementEngine.settlement(for: trip)
        var lines = ["✈️ \(trip.name) — settle up"]
        if settlement.transfers.isEmpty {
            lines.append("All settled up.")
        } else {
            for transfer in settlement.transfers {
                lines.append("\(name(transfer.fromID)) → \(name(transfer.toID)): \(Money.format(transfer.cents, currencyCode: trip.currencyCode))")
            }
        }
        lines.append("")
        lines.append("Total \(Money.format(trip.totalCents, currencyCode: trip.currencyCode))")
        return lines.joined(separator: "\n")
    }
}
