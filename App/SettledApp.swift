import SwiftUI
import SwiftData
import CloudKit
import SettledCore

@main
struct SettledApp: App {
    // An app delegate, purely so an accepted iCloud share invitation
    // reaches the app.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = BillFlowModel()
    @State private var cloud = CloudSyncEngine()
    private let container: ModelContainer
    /// Why the saved data couldn't be opened, when it couldn't.
    private let storeFailure: String?

    init() {
        let screenshots = DemoData.isScreenshotRun
        // Screenshot runs use a throwaway in-memory store seeded with demo
        // data; real launches use the persistent store as before.
        let (container, failure) = Self.openStore(inMemory: screenshots)
        if screenshots {
            DemoData.seed(into: container.mainContext)
            _model = State(initialValue: DemoData.receiptModel())
        }
        self.container = container
        self.storeFailure = failure
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, storeFailure: storeFailure)
                .environment(cloud)
        }
        .modelContainer(container)
    }

    /// Opens the local store without ever taking the app down with it. A
    /// store that won't open is moved aside (kept, not deleted) and a fresh
    /// one is used; the reason is returned so the app can show it.
    ///
    /// The store stays on this device: group sharing has its own CloudKit
    /// sync. Left at its default, SwiftData would see the app's iCloud
    /// entitlement and try to mirror the store to CloudKit, which rejects
    /// the store's unique attributes.
    private static func openStore(inMemory: Bool) -> (ModelContainer, String?) {
        let schema = Schema([SavedBill.self, SavedTrip.self, SavedPerson.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory,
                                               cloudKitDatabase: .none)
        do {
            return (try ModelContainer(for: schema, configurations: configuration), nil)
        } catch {
            let failure = String(describing: error)
            setAside(configuration.url)
            if let fresh = try? ModelContainer(for: schema, configurations: configuration) {
                return (fresh, failure)
            }
            // Nothing on disk will open; run for this session in memory.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true,
                                            cloudKitDatabase: .none)
            return (try! ModelContainer(for: schema, configurations: memory), failure)
        }
    }

    /// Renames the store and its journal files so a fresh store can take
    /// their place without losing what they held.
    private static func setAside(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(fileURLWithPath: url.path + suffix)
            let kept = URL(fileURLWithPath: url.path + suffix + ".unreadable-\(stamp)")
            try? FileManager.default.moveItem(at: file, to: kept)
        }
    }
}

/// Four tabs, each its own navigation stack so switching preserves where
/// you were: split a single receipt, track groups, see what changed, and
/// settings (who you are, the people directory).
struct RootView: View {
    @Bindable var model: BillFlowModel
    /// Set when the saved data couldn't be opened and a fresh store was used.
    var storeFailure: String? = nil
    @State private var storeFailureDismissed = false
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CloudSyncEngine.self) private var cloud
    @AppStorage(Me.onboardedKey) private var onboarded = false
    @AppStorage(Me.defaultsKey) private var meIDString = ""
    @State private var showingOnboarding = false
    @State private var incoming: GroupDocument?
    @State private var openFailed = false

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
            .tabItem { Label("Groups", systemImage: "person.3.fill") }

            NavigationStack {
                FriendsView()
            }
            .tabItem { Label("Friends", systemImage: "person.2.fill") }

            NavigationStack {
                ActivityView()
            }
            .tabItem { Label("Activity", systemImage: "clock.fill") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(Theme.accent)
        // Shown rather than crashing, with the reason, so it can be reported.
        .safeAreaInset(edge: .top) {
            if let storeFailure, !storeFailureDismissed {
                StoreFailureBanner(reason: storeFailure) { storeFailureDismissed = true }
            }
        }
        .task {
            PeopleDirectory.backfillIfNeeded(in: context)
            materializeRecurring()
            if !onboarded { showingOnboarding = true }
            await GroupSyncCoordinator.syncAll(engine: cloud, context: context)
        }
        // No server generates recurring expenses or pushes changes; the app
        // does both whenever it comes to the foreground.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            materializeRecurring()
            Task { await GroupSyncCoordinator.syncAll(engine: cloud, context: context) }
        }
        // Someone tapped an invitation to a shared group.
        .onReceive(NotificationCenter.default.publisher(for: AppDelegate.didReceiveShare)) { notification in
            guard let metadata = notification.object as? CKShare.Metadata else { return }
            Task {
                try? await cloud.accept(metadata)
                await GroupSyncCoordinator.syncAll(engine: cloud, context: context)
            }
        }
        // Dismissing by any route counts as "asked once"; Settings can
        // always set it later.
        .sheet(isPresented: $showingOnboarding, onDismiss: { onboarded = true }) {
            MeOnboardingView()
        }
        // A `.settled` file tapped in Messages, Files, or AirDrop.
        .onOpenURL { url in
            if let document = GroupSharing.read(from: url) {
                incoming = document
            } else {
                openFailed = true
            }
        }
        .sheet(item: $incoming) { document in
            ImportGroupSheet(document: document)
        }
        .alert("Couldn't open that file", isPresented: $openFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It isn't a Settled group file, or it's from a newer version of the app.")
        }
    }
}

extension RootView {
    private func materializeRecurring() {
        let groups = (try? context.fetch(FetchDescriptor<SavedTrip>())) ?? []
        for saved in groups {
            var group = saved.group
            if group.materializeRecurring(by: Me.parse(meIDString)) > 0 {
                saved.update(from: group)
            }
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

/// Says that saved data couldn't be opened, and why. The old file is kept
/// beside the new one, so nothing is lost for good.
private struct StoreFailureBanner: View {
    let reason: String
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Saved data couldn't be opened", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Dismiss", action: dismiss)
                    .font(.subheadline)
            }
            Text("Settled started with a fresh copy and kept the old file. Please screenshot this for support:")
                .font(.caption)
            Text(reason)
                .font(.caption2.monospaced())
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
