import SwiftUI
import SplitChecksCore

/// Step 3: "paint" items with people. Select a person chip, then tap items
/// to toggle them for that person. Items tapped by several people are shared.
struct AssignView: View {
    @Environment(BillFlowModel.self) private var model
    @State private var selectedPersonID: Person.ID?

    private var selectedPerson: Person? {
        model.people.first { $0.id == selectedPersonID }
    }

    private var assignedCount: Int {
        model.items.count - model.result.unassignedItemIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.people) { person in
                        Button {
                            selectedPersonID = person.id
                        } label: {
                            PersonChip(person: person, isSelected: person.id == selectedPersonID)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            if let selectedPerson {
                (Text("Tap items to add them for ")
                 + Text(selectedPerson.name).foregroundColor(Palette.accent).bold())
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.items) { item in
                        itemCard(item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Assign items")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.impact(weight: .light), trigger: model.assignments.count)
        .onAppear {
            if selectedPersonID == nil { selectedPersonID = model.people.first?.id }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                if assignedCount < model.items.count {
                    Text("\(assignedCount) of \(model.items.count) items assigned")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                NavigationLink(value: BillStep.tipTax) {
                    PrimaryButtonLabel(title: "Next: Tip & tax")
                }
                .disabled(assignedCount < model.items.count)
                .opacity(assignedCount < model.items.count ? 0.5 : 1)
            }
            .padding(16)
            .background(.bar)
        }
    }

    private func itemCard(_ item: LineItem) -> some View {
        let assignees = model.assignees(of: item)
        let isForSelected = selectedPerson.map { model.isAssigned(item: item, to: $0) } ?? false
        let unassigned = assignees.isEmpty

        return Button {
            guard let person = selectedPerson else { return }
            model.toggleAssignment(item: item, person: person)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isForSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isForSelected ? Palette.accent : Palette.muted.opacity(0.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(priceLine(item, assigneeCount: assignees.count))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                if unassigned {
                    Text("Unassigned")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Palette.hairline))
                } else {
                    AssigneeStack(people: assignees)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Palette.card)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(unassigned ? Palette.muted.opacity(0.45) : Palette.cardBorder,
                                  lineWidth: unassigned ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(unassigned ? "Unassigned" : "Assigned"))
    }

    private func priceLine(_ item: LineItem, assigneeCount: Int) -> String {
        let price = Money.format(item.priceCents)
        return assigneeCount > 1 ? "\(price) · shared \(assigneeCount) ways" : price
    }
}
