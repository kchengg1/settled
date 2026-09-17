import SwiftUI
import SwiftData
import SplitChecksCore

/// One group: its ledger of expenses and payments, balances with settle-up,
/// the activity trail, and members. Every edit goes through
/// `ExpenseGroup.apply` on a local copy and is persisted back to the
/// `SavedTrip` on change.
struct GroupDetailView: View {
    let saved: SavedTrip
    @State private var group: ExpenseGroup
    @State private var mode: Mode = .expenses
    @State private var showingAddExpense = false
    @State private var editingExpense: Expense?
    @State private var paymentDraft: PaymentDraft?
    @State private var showingMemberPicker = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var undoEntryID: UUID?
    @State private var undoTitle = ""
    @State private var undoTask: Task<Void, Never>?
    @AppStorage(Me.defaultsKey) private var meIDString = ""
    @Environment(\.modelContext) private var context

    enum Mode: String, CaseIterable {
        case expenses = "Expenses"
        case balances = "Balances"
        case activity = "Activity"
        case people = "People"
    }

    init(saved: SavedTrip) {
        self.saved = saved
        _group = State(initialValue: saved.group)
    }

    private var meID: Person.ID? { Me.parse(meIDString) }
    private var namer: Namer { Namer(group: group, meID: meID) }

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
            case .activity: activityList
            case .people: peopleList
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingAddExpense) {
            ExpenseEditorView(group: group, existing: nil, meID: meID) { expense in
                group.apply(.addEntry(.expense(expense)), by: meID)
            }
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditorView(group: group, existing: expense, meID: meID) { updated in
                group.apply(.updateEntry(.expense(updated)), by: meID)
            }
        }
        .sheet(item: $paymentDraft) { draft in
            RecordPaymentView(group: group, draft: draft, meID: meID) { payment in
                if draft.existing == nil {
                    group.apply(.addEntry(.payment(payment)), by: meID)
                } else {
                    group.apply(.updateEntry(.payment(payment)), by: meID)
                }
            }
        }
        .sheet(isPresented: $showingMemberPicker) {
            MemberPickerView(existingIDs: Set(group.people.map(\.id))) { people in
                for person in people {
                    group.apply(.addMember(person.withColorIndex(group.people.count)), by: meID)
                }
            }
        }
        .alert("Rename group", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Save") { group.apply(.rename(renameText), by: meID) }
            Button("Cancel", role: .cancel) {}
        }
        // Any mutation of `group` is written straight back to storage, and
        // a change made elsewhere (restore from the Activity tab) is picked up.
        .onChange(of: group) { saved.update(from: group) }
        .onChange(of: saved.updatedAt) {
            let latest = saved.group
            if latest != group { group = latest }
        }
        .safeAreaInset(edge: .bottom) {
            if let id = undoEntryID {
                undoBanner(id)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if mode == .expenses {
                Button { showingAddExpense = true } label: { Label("Add expense", systemImage: "plus") }
                    .disabled(group.people.isEmpty)
            }
            if mode == .balances {
                ShareLink(item: settlementText) { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(group.liveEntries.isEmpty)
            }
            if mode == .people {
                Button { showingMemberPicker = true } label: { Label("Add people", systemImage: "person.badge.plus") }
            }
            Menu {
                Button {
                    paymentDraft = PaymentDraft()
                } label: {
                    Label("Record a payment", systemImage: "arrow.right.circle")
                }
                .disabled(group.people.count < 2)
                Button {
                    renameText = group.name
                    showingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Picker("Group type", selection: kindBinding) {
                    ForEach(GroupKind.allCases, id: \.self) { kind in
                        Label(kind.title, systemImage: kind.systemImage).tag(kind)
                    }
                }
                Toggle("Simplify debts", isOn: simplifyBinding)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private var kindBinding: Binding<GroupKind> {
        Binding(get: { group.kind }, set: { group.apply(.setKind($0), by: meID) })
    }

    private var simplifyBinding: Binding<Bool> {
        Binding(get: { group.simplifyDebts }, set: { group.apply(.setSimplifyDebts($0), by: meID) })
    }

    // MARK: - Expenses

    private var sortedEntries: [LedgerEntry] {
        group.liveEntries.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
    }

    @ViewBuilder
    private var expensesList: some View {
        if group.people.isEmpty {
            ContentUnavailableView {
                Label("Add people first", systemImage: "person.2")
            } description: {
                Text("Add who's in this group, then record expenses.")
            } actions: {
                Button("Add people") { showingMemberPicker = true }
                    .buttonStyle(.borderedProminent)
            }
        } else if sortedEntries.isEmpty {
            ContentUnavailableView {
                Label("No expenses yet", systemImage: "creditcard")
            } description: {
                Text("Tap + to add what someone paid for.")
            }
        } else {
            List {
                ForEach(sortedEntries) { entry in
                    entryRow(entry)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                delete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                Section {
                    HStack {
                        Text("Total spent").fontWeight(.semibold)
                        Spacer()
                        Text(Money.format(group.totalCents, currencyCode: group.currencyCode))
                            .monospacedDigit().fontWeight(.semibold)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func entryRow(_ entry: LedgerEntry) -> some View {
        switch entry {
        case .expense(let expense):
            Button {
                editingExpense = expense
            } label: {
                expenseRow(expense)
            }
            .foregroundStyle(.primary)
        case .payment(let payment):
            Button {
                paymentDraft = PaymentDraft(existing: payment)
            } label: {
                paymentRow(payment)
            }
            .foregroundStyle(.primary)
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title)
                Text("Paid by \(namer.name(expense.payerID)) · \(splitSummary(expense))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(expense.amountCents, currencyCode: group.currencyCode))
                    .monospacedDigit()
                if let line = myLine(for: expense) {
                    Text(line.text)
                        .font(.caption)
                        .foregroundStyle(line.color)
                }
            }
        }
    }

    private func paymentRow(_ payment: Payment) -> some View {
        HStack {
            Image(systemName: "arrow.right.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(namer.paymentLine(payment))
                Text("\(payment.method.title) · \(payment.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money.format(payment.cents, currencyCode: payment.currencyCode))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// "you lent $40" / "you borrowed $12" for an expense I'm part of.
    private func myLine(for expense: Expense) -> (text: String, color: Color)? {
        guard let meID else { return nil }
        let known = Set(group.people.map(\.id))
        let owed = SettlementEngine.owedShares(for: expense, knownPeople: known)[meID] ?? 0
        let paid = expense.payerID == meID ? expense.amountCents : 0
        let net = paid - owed
        if net > 0 { return ("you lent \(Money.format(net, currencyCode: group.currencyCode))", .green) }
        if net < 0 { return ("you borrowed \(Money.format(-net, currencyCode: group.currencyCode))", .orange) }
        return nil
    }

    private func delete(_ entry: LedgerEntry) {
        guard group.apply(.deleteEntry(entry.id), by: meID) else { return }
        undoTitle = group.title(of: entry)
        undoEntryID = entry.id
        undoTask?.cancel()
        undoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { undoEntryID = nil }
        }
    }

    private func undoBanner(_ id: UUID) -> some View {
        HStack {
            Text("Deleted \(undoTitle)")
                .lineLimit(1)
            Spacer()
            Button("Undo") {
                group.apply(.restoreEntry(id), by: meID)
                undoTask?.cancel()
                undoEntryID = nil
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.bar)
    }

    // MARK: - Balances & settle up

    private var balancesList: some View {
        let settlement = SettlementEngine.settlement(for: group)
        return List {
            Section("Balances") {
                if group.liveEntries.isEmpty {
                    Text("No expenses yet.").foregroundStyle(Color.secondary)
                }
                ForEach(settlement.balances) { balance in
                    balanceRow(balance)
                }
            }

            Section {
                if settlement.transfers.isEmpty {
                    settledUpLabel
                } else {
                    ForEach(settlement.transfers, id: \.self) { transfer in
                        transferRow(transfer)
                    }
                }
                Toggle("Simplify debts", isOn: simplifyBinding)
            } header: {
                Text("Settle up")
            } footer: {
                Text(settlement.isSimplified
                     ? "The fewest payments that clear every balance."
                     : "Debts as they happened, netted per pair. Turn on simplify for the fewest payments.")
            }
        }
    }

    private func balanceRow(_ balance: Balance) -> some View {
        HStack {
            if let person = group.person(withID: balance.personID) {
                PersonChip(person: person)
            }
            Spacer()
            Text(namer.balanceLabel(balance))
                .monospacedDigit()
                .foregroundStyle(balanceColor(balance.cents))
        }
    }

    private func transferRow(_ transfer: Transfer) -> some View {
        HStack {
            Text(namer.name(transfer.fromID))
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(Color.secondary)
            Text(namer.name(transfer.toID))
            Spacer()
            Text(Money.format(transfer.cents, currencyCode: group.currencyCode))
                .monospacedDigit().fontWeight(.medium)
            Button("Record") {
                paymentDraft = PaymentDraft(fromID: transfer.fromID, toID: transfer.toID, cents: transfer.cents)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var settledUpLabel: some View {
        let empty = group.liveEntries.isEmpty
        return Label(empty ? "Nothing to settle yet" : "All settled up 🎉",
                     systemImage: empty ? "tray" : "checkmark.seal.fill")
            .foregroundStyle(empty ? Color.secondary : Color.green)
    }

    private func balanceColor(_ cents: Int) -> Color {
        if cents == 0 { return .secondary }
        return cents > 0 ? .green : .red
    }

    // MARK: - Activity

    @ViewBuilder
    private var activityList: some View {
        if group.activity.isEmpty {
            ContentUnavailableView {
                Label("Nothing yet", systemImage: "clock")
            } description: {
                Text("Expenses, payments, and edits show up here.")
            }
        } else {
            List {
                ForEach(Array(group.activity.reversed())) { event in
                    ActivityEventRow(
                        event: event,
                        groupName: nil,
                        actorName: event.actorID.map { namer.name($0) },
                        restorable: isRestorable(event)
                    ) {
                        if let id = event.subjectID { group.apply(.restoreEntry(id), by: meID) }
                    }
                }
            }
        }
    }

    private func isRestorable(_ event: ActivityEvent) -> Bool {
        guard event.kind == .entryDeleted, let id = event.subjectID else { return false }
        return group.entry(withID: id)?.isDeleted == true
    }

    // MARK: - People

    private var peopleList: some View {
        List {
            Section {
                ForEach(group.people) { person in
                    HStack {
                        PersonChip(person: person)
                        if namer.isMe(person.id) {
                            Text("you").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if group.isReferenced(person.id) {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    // `apply` refuses to remove anyone tied to an entry, so
                    // balances stay consistent.
                    for person in offsets.map({ group.people[$0] }) {
                        group.apply(.removeMember(person.id), by: meID)
                    }
                }
            } footer: {
                Text("People in an expense or payment can't be removed. A lock marks them.")
            }

            Section {
                Button {
                    showingMemberPicker = true
                } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                }
                if let meID, group.person(withID: meID) == nil,
                   let me = PeopleDirectory.find(id: meID, in: context) {
                    Button {
                        group.apply(.addMember(me.person(colorIndex: group.people.count)), by: meID)
                    } label: {
                        Label("Add yourself (\(me.name))", systemImage: "person.crop.circle.badge.plus")
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func splitSummary(_ expense: Expense) -> String {
        switch expense.split {
        case .equally(let ids): return "split \(ids.count) ways"
        case .shares: return "by shares"
        case .percentages: return "by percent"
        case .exactCents: return "exact amounts"
        }
    }

    /// Neutral names (no "You") since this goes to the group chat.
    private var settlementText: String {
        let settlement = SettlementEngine.settlement(for: group)
        var lines = ["\(group.name) — settle up"]
        if settlement.transfers.isEmpty {
            lines.append("All settled up.")
        } else {
            for transfer in settlement.transfers {
                lines.append("\(group.name(of: transfer.fromID)) → \(group.name(of: transfer.toID)): \(Money.format(transfer.cents, currencyCode: group.currencyCode))")
            }
        }
        lines.append("")
        lines.append("Total spent \(Money.format(group.totalCents, currencyCode: group.currencyCode))")
        return lines.joined(separator: "\n")
    }
}

/// What the payment sheet opens with: a suggested transfer, an existing
/// payment to edit, or nothing.
struct PaymentDraft: Identifiable {
    let id = UUID()
    var fromID: Person.ID?
    var toID: Person.ID?
    var cents: Int
    var existing: Payment?

    init(fromID: Person.ID? = nil, toID: Person.ID? = nil, cents: Int = 0, existing: Payment? = nil) {
        self.fromID = existing?.fromID ?? fromID
        self.toID = existing?.toID ?? toID
        self.cents = existing?.cents ?? cents
        self.existing = existing
    }
}
