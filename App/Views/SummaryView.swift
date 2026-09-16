import SwiftUI
import SplitChecksCore

/// Step 5: the payoff. A hero total, one expandable card per person, and a
/// share button for the group chat.
struct SummaryView: View {
    @Environment(BillFlowModel.self) private var model
    @Environment(\.modelContext) private var context
    @State private var expandedPersonIDs: Set<Person.ID> = []
    @State private var saved = false

    var body: some View {
        let result = model.result

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                heroTotal(result)

                Text("EVERYONE'S SHARE")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.muted)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)

                ForEach(result.shares) { share in
                    if let person = model.people.first(where: { $0.id == share.personID }) {
                        personCard(person: person, share: share, result: result)
                    }
                }

                Text("Every share adds up to the bill exactly — no lost pennies.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .appBackground()
        .navigationTitle("The split")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: model.summaryText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .safeAreaInset(edge: .bottom) {
            Button { saveAndFinish() } label: {
                PrimaryButtonLabel(title: "Save & start a new bill")
            }
            .padding(16)
            .background(.bar)
        }
    }

    private func heroTotal(_ result: SplitResult) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOTAL SPLIT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))
            Text(Money.format(result.grandTotalCents))
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("\(model.people.count) people · tax & tip included")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Palette.hero)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func personCard(person: Person, share: PersonShare, result: SplitResult) -> some View {
        let isExpanded = expandedPersonIDs.contains(person.id)

        return Card(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy) {
                        if isExpanded { expandedPersonIDs.remove(person.id) }
                        else { expandedPersonIDs.insert(person.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Avatar(name: person.name, colorIndex: person.colorIndex, size: 38)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(person.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            Text(itemsSubtitle(person: person, result: result))
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(Money.format(share.totalCents))
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .padding(14)
                }
                .accessibilityHint(Text(isExpanded ? "Collapse details" : "Show the math"))

                if isExpanded {
                    VStack(spacing: 6) {
                        ForEach(model.items) { item in
                            if let cents = result.itemBreakdown[item.id]?[person.id] {
                                detailRow(label: itemLabel(item, cents: cents), cents: cents)
                            }
                        }
                        if share.taxCents != 0 {
                            detailRow(label: "Tax (\(ruleName(model.taxRule)))", cents: share.taxCents)
                        }
                        if share.tipCents != 0 {
                            detailRow(label: "Tip (\(ruleName(model.tipRule)))", cents: share.tipCents)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private func itemsSubtitle(person: Person, result: SplitResult) -> String {
        let names = model.items.compactMap { item in
            result.itemBreakdown[item.id]?[person.id] != nil ? item.name : nil
        }
        return names.isEmpty ? "tax & tip only" : names.joined(separator: " · ")
    }

    private func itemLabel(_ item: LineItem, cents: Int) -> String {
        cents == item.priceCents ? item.name : "\(item.name) (shared)"
    }

    private func ruleName(_ rule: AllocationRule) -> String {
        rule == .proportional ? "proportional" : "even"
    }

    private func detailRow(label: String, cents: Int) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Palette.muted)
            Spacer()
            Text(Money.format(cents)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.muted)
        }
    }

    private func saveAndFinish() {
        if let bill = try? SavedBill(snapshot: model.snapshot, merchantName: model.merchantName) {
            context.insert(bill)
        }
        saved = true
        model.startOver()
    }
}
