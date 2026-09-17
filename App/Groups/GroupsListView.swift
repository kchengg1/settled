import SwiftUI
import SwiftData
import SplitChecksCore

/// The Groups tab home: an overall "you owe / you are owed" header when
/// the app knows who you are, then every group by last activity.
struct GroupsListView: View {
    @Query(sort: \SavedTrip.updatedAt, order: .reverse) private var groups: [SavedTrip]
    @Environment(\.modelContext) private var context
    @AppStorage(Me.defaultsKey) private var meIDString = ""
    @State private var showingNew = false

    private var meID: Person.ID? { Me.parse(meIDString) }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView {
                    Label("No groups yet", systemImage: "person.3")
                } description: {
                    Text("Create a group for a trip, a home, or any shared tab to track who owes whom.")
                } actions: {
                    Button("New group") { showingNew = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    if let overall = overallBalance {
                        Section {
                            overallHeader(overall)
                        }
                    }
                    Section {
                        ForEach(groups) { saved in
                            NavigationLink(value: saved.id) {
                                row(saved)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(groups[index]) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingNew = true } label: { Label("New group", systemImage: "plus") }
            }
        }
        .navigationDestination(for: UUID.self) { id in
            if let saved = groups.first(where: { $0.id == id }) {
                GroupDetailView(saved: saved)
            }
        }
        .sheet(isPresented: $showingNew) {
            NewGroupSheet { group in
                context.insert(SavedTrip(group: group))
            }
        }
    }

    // MARK: - Rows

    private func row(_ saved: SavedTrip) -> some View {
        let group = saved.group
        return HStack {
            Image(systemName: saved.kind.systemImage)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(saved.name).font(.headline)
                Text("\(saved.peopleCount) people · \(Money.format(saved.totalCents, currencyCode: group.currencyCode))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let meID, let balance = SettlementEngine.balances(for: group).first(where: { $0.personID == meID }) {
                Text(Namer(group: group, meID: meID).balanceLabel(balance))
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(balanceColor(balance.cents))
            }
        }
    }

    // MARK: - Overall balance

    /// My net position summed across groups, per currency: what I owe in
    /// total and what I'm owed in total.
    private struct Overall {
        var owe: [String: Int] = [:]
        var owed: [String: Int] = [:]
        var isEmpty: Bool { owe.isEmpty && owed.isEmpty }
    }

    private var overallBalance: Overall? {
        guard let meID else { return nil }
        var overall = Overall()
        var involved = false
        for saved in groups {
            let group = saved.group
            guard let balance = SettlementEngine.balances(for: group).first(where: { $0.personID == meID }) else { continue }
            involved = true
            if balance.cents < 0 { overall.owe[group.currencyCode, default: 0] += -balance.cents }
            if balance.cents > 0 { overall.owed[group.currencyCode, default: 0] += balance.cents }
        }
        return involved ? overall : nil
    }

    @ViewBuilder
    private func overallHeader(_ overall: Overall) -> some View {
        if overall.isEmpty {
            Label("You're all settled up", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } else {
            ForEach(overall.owe.keys.sorted(), id: \.self) { code in
                LabeledContent("You owe") {
                    Text(Money.format(overall.owe[code] ?? 0, currencyCode: code))
                        .monospacedDigit().foregroundStyle(.red)
                }
            }
            ForEach(overall.owed.keys.sorted(), id: \.self) { code in
                LabeledContent("You are owed") {
                    Text(Money.format(overall.owed[code] ?? 0, currencyCode: code))
                        .monospacedDigit().foregroundStyle(.green)
                }
            }
        }
    }

    private func balanceColor(_ cents: Int) -> Color {
        if cents == 0 { return .secondary }
        return cents > 0 ? .green : .red
    }
}

/// Name and type for a new group. You're added as the first member when
/// the app knows who you are.
struct NewGroupSheet: View {
    let onCreate: (ExpenseGroup) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(Me.defaultsKey) private var meIDString = ""
    @State private var name = ""
    @State private var kind: GroupKind = .trip
    @State private var includeMe = true
    @FocusState private var nameFocused: Bool

    private var me: SavedPerson? {
        Me.parse(meIDString).flatMap { PeopleDirectory.find(id: $0, in: context) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onSubmit(create)
                    Picker("Type", selection: $kind) {
                        ForEach(GroupKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.systemImage).tag(kind)
                        }
                    }
                } footer: {
                    Text("A getaway, a shared house, a couple's tab — the type only changes the icon.")
                }
                if let me {
                    Section {
                        Toggle(isOn: $includeMe) {
                            HStack {
                                Text("Add yourself")
                                Spacer()
                                PersonChip(person: me.person)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { nameFocused = true }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var group = ExpenseGroup(name: trimmed, kind: kind)
        if includeMe, let me {
            group.apply(.addMember(me.person(colorIndex: 0)), by: me.id)
            me.lastUsedAt = .now
        }
        onCreate(group)
        dismiss()
    }
}
