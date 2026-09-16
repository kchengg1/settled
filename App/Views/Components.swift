import SwiftUI
import UIKit
import SplitChecksCore

/// Chip colors, indexed by `Person.colorIndex`. Delegates to the shared
/// muted avatar palette so colors stay consistent app-wide.
enum ChipPalette {
    static func color(for person: Person) -> Color {
        Palette.avatar(person.colorIndex)
    }
}

/// A tappable person chip: muted avatar plus the name. Selected chips fill
/// with the accent; unselected read as a quiet outlined card.
struct PersonChip: View {
    let person: Person
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Avatar(name: person.name, colorIndex: person.colorIndex, size: 26,
                   ringColor: isSelected ? .white.opacity(0.3) : nil)
            Text(person.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? .white : Palette.ink)
                .lineLimit(1)
        }
        .padding(.leading, 5)
        .padding(.trailing, 11)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(isSelected ? Palette.accent : Palette.card)
        )
        .overlay(
            Capsule().strokeBorder(isSelected ? .clear : Palette.cardBorder, lineWidth: 1)
        )
        .accessibilityLabel(Text(person.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Tiny stacked avatars showing who's on an item.
struct AssigneeStack: View {
    let people: [Person]

    var body: some View {
        HStack(spacing: -9) {
            ForEach(people) { person in
                Avatar(name: String(person.name.prefix(1)), colorIndex: person.colorIndex,
                       size: 27, ringColor: Palette.card)
            }
        }
        .accessibilityLabel(Text(people.map(\.name).joined(separator: ", ")))
    }
}

/// A text field that edits an integer-cents binding through `Money` parsing,
/// committing on every keystroke that parses and restoring on focus loss.
struct CurrencyField: View {
    let title: String
    @Binding var cents: Int
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .focused($focused)
            .multilineTextAlignment(.trailing)
            .onAppear { text = cents == 0 ? "" : displayString }
            .onChange(of: text) {
                if let parsed = Money.parse(text) { cents = parsed }
                else if text.isEmpty { cents = 0 }
            }
            .onChange(of: focused) {
                if !focused { text = cents == 0 ? "" : displayString }
            }
            // The decimal pad has no return key, so give it an explicit
            // Done button to dismiss. Guarded by `focused` so only the
            // active field contributes a keyboard toolbar.
            .toolbar {
                if focused {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = false }
                    }
                }
            }
    }

    private var displayString: String {
        String(format: "%.2f", Double(cents) / 100)
    }
}
