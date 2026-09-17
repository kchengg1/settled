import SwiftUI
import SwiftData
import SplitChecksCore

@main
struct SplitChecksApp: App {
    @State private var model = BillFlowModel()
    private let container: ModelContainer

    init() {
        let screenshots = DemoData.isScreenshotRun
        // Screenshot runs use a throwaway in-memory store seeded with demo
        // data; real launches use the persistent store as before.
        let configuration = ModelConfiguration(isStoredInMemoryOnly: screenshots)
        let container = try! ModelContainer(for: SavedBill.self, SavedTrip.self, SavedPerson.self,
                                            configurations: configuration)
        if screenshots {
            DemoData.seed(into: container.mainContext)
            _model = State(initialValue: DemoData.receiptModel())
        }
        self.container = container
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .modelContainer(container)
    }
}

/// Four tabs, each its own navigation stack so switching preserves where
/// you were: split a single receipt, track groups, see what changed, and
/// settings (who you are, the people directory).
struct RootView: View {
    @Bindable var model: BillFlowModel
    @Environment(\.modelContext) private var context
    @AppStorage(Me.onboardedKey) private var onboarded = false
    @State private var showingOnboarding = false

    var body: some View {
        TabView {
            NavigationStack(path: $model.path) {
                ItemsEntryView()
            }
            .environment(model)
            .tabItem { Label("Receipt", systemImage: "doc.viewfinder") }

            NavigationStack {
                GroupsListView()
            }
            .tabItem { Label("Groups", systemImage: "person.3") }

            NavigationStack {
                ActivityView()
            }
            .tabItem { Label("Activity", systemImage: "clock") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            PeopleDirectory.backfillIfNeeded(in: context)
            if !onboarded { showingOnboarding = true }
        }
        // Dismissing by any route counts as "asked once"; Settings can
        // always set it later.
        .sheet(isPresented: $showingOnboarding, onDismiss: { onboarded = true }) {
            MeOnboardingView()
        }
    }
}

/// The linear steps after item entry, plus history. Item entry is the
/// stack root.
enum BillStep: Hashable {
    case people
    case assign
    case tipTax
    case summary
    case history
}
