//
//  AmblyoApp.swift
//  Amblyo — Lazy Eye Training
//
//  Entry point. See docs/04-ARCHITECTURE.md and docs/02-PRD.md section 4.
//
//  The launch-order comments in `body` are load-bearing — audio configuration
//  and StoreKit transaction listening both have to happen before the first UI
//  frame, for reasons written next to each. Read them before reordering.
//

import SwiftUI
import SwiftData

@main
struct AmblyoApp: App {

    /// Shared model container. Schema in docs/04-ARCHITECTURE.md section 3.
    let modelContainer: ModelContainer

    /// Audio must be configured before ANY view appears, because every channel
    /// defaults to off and the session category must be `.ambient` so the
    /// hardware silent switch works. docs/05-DESIGN-SYSTEM.md section 7.
    @State private var settings = SettingsStore()

    /// StoreKit transaction listening must start before the first UI frame, or a
    /// purchase completed elsewhere (or an Ask-to-Buy approval) arrives with
    /// nobody listening. docs/07-MONETIZATION-PAYWALL.md section 4.
    @State private var subscriptions = SubscriptionManager()

    @State private var launchState = LaunchState()

    /// Set when the on-disk store could not be opened and had to be rebuilt.
    /// The user is told; a silent recovery is how data loss goes unnoticed.
    let storeWasReset: Bool

    init() {
        // WHY THIS IS NO LONGER A FALLBACK TO IN-MEMORY.
        //
        // The old version caught a container failure and swapped in an
        // in-memory store "so the user gets a working app rather than a dead
        // launch". It does the opposite. An in-memory store is EMPTY and is
        // wiped on every launch, so the app comes up with no profile, no
        // history and no way to keep any — and says nothing. Build 2 shipped
        // exactly that: the store from build 1 would not open, every screen
        // reported "No profile yet", and the app could not be recovered by
        // using it.
        //
        // A store that will not open has to be REBUILT ON DISK, and the user
        // has to be told, because the honest description of what happened is
        // "your data is gone" and they may want to know why before starting
        // over.
        do {
            modelContainer = try .amblyo(inMemory: LaunchArguments.isUITesting)
            storeWasReset = false
        } catch {
            assertionFailure("ModelContainer failed: \(error)")
            do {
                try ModelContainer.destroyAmblyoStore()
                modelContainer = try .amblyo()
                storeWasReset = true
            } catch {
                // Rebuilding failed too. In-memory now IS the least-bad option
                // — but the flag still says so, so the app admits it.
                modelContainer = try! .amblyo(inMemory: true)
                storeWasReset = true
            }
        }

        // NO SWIFTDATA WORK HERE. See the seeding task in `body`.
        //
        // The previous attempt seeded the demo fixture in this initialiser, to
        // guarantee a profile existed before the first frame. The app then died
        // at launch — "Lost connection to the app" — on the one UI test that
        // passes the seeding argument, while the launch WITHOUT it was fine.
        // Touching `modelContainer.mainContext` before the container has been
        // attached to the scene is the difference between those two launches,
        // and one initialiser is not the place to find out what SwiftData is
        // willing to do that early.
        //
        // The race it was trying to fix was never about `init` anyway: seeding
        // sat behind a StoreKit network call. That is fixed by giving it its
        // own task, which costs a frame or two of setup screen in a test run
        // and nothing in production.
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeWasReset: storeWasReset)
                .environment(settings)
                .environment(subscriptions)
                .environment(launchState)
                // THREE TASKS, NOT ONE CHAIN. These were sequential statements
                // in a single `.task`, which meant each one waited on the one
                // before it. Only StoreKit touches the network, and it was
                // first, so it held up everything: entitlements stayed
                // `.unknown` and Profile read "Checking…" indefinitely, and the
                // demo fixture did not exist until a product lookup returned,
                // which timed out the smoke test.
                //
                // Independent work gets independent tasks. The only ordering
                // that ever mattered was audio-before-first-sound, and that is
                // satisfied by it starting at launch rather than by it being
                // first in a queue.
                .task { AudioEngine.configureSession() }
                .task {
                    guard LaunchArguments.shouldSeedDemoData else { return }
                    // ITS OWN CONTEXT, NOT `mainContext`.
                    //
                    // Seeding against `mainContext` terminated the app. Every
                    // seeded launch died — first reported as "Lost connection
                    // to the application", then as the diagnostic itself
                    // failing with "Application com.amblyo.app is not running"
                    // — while the launch WITHOUT the seed argument was fine.
                    //
                    // The seeder writes twelve weeks of sessions and trials in
                    // one pass, and `mainContext` is the context `@Query` is
                    // actively observing while that happens. Its own tests
                    // never did this: they build a separate `ModelContext` and
                    // read back from it, which is why they passed throughout.
                    // The app now does what the tested path does.
                    //
                    // Writes still land in the same store, so `@Query` picks
                    // them up on the next update — which is the whole point.
                    // PRINTED, NOT LOGGED. `os.Logger` output does not reach the
                    // xcodebuild log, and that log is the only view available
                    // when working without a Mac. The app's stdout DOES reach
                    // it — the CoreData warnings in every CI run arrive that
                    // way. Six runs were spent unable to tell "seeding crashed"
                    // from "seeding finished and something after it crashed";
                    // these two lines settle that permanently, and they only
                    // run behind a launch argument no shipping build passes.
                    print("AMBLYO-SEED: starting")
                    let seedContext = ModelContext(modelContainer)
                    DemoDataSeeder.seed(into: seedContext)
                    let count = (try? seedContext.fetchCount(
                        FetchDescriptor<Profile>())) ?? -1
                    print("AMBLYO-SEED: finished, profiles=\(count)")
                }
                .task {
                    await subscriptions.start()
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Root

/// Decides between onboarding and the app.
///
/// IT ASKS THE DATA, NOT A FLAG, AND THAT IS THE WHOLE POINT.
/// This used to branch on `launchState.hasCompletedOnboarding` alone — a
/// UserDefaults boolean that knows nothing about whether a profile exists.
/// Those are two sources of truth for one fact, and they can disagree:
///
///   - Onboarding finishes, the flag is written, the profile save then fails.
///   - The app updates, the store cannot be opened, and the data is gone while
///     UserDefaults survives untouched — which is exactly what UserDefaults is
///     designed to do.
///
/// In both cases the old code sent the user to a tab bar with no profile in it.
/// Every screen said "No profile yet. Finish setup to start training", and there
/// was NO WAY TO FINISH SETUP: the flag said setup was already done. Deleting
/// and reinstalling the app was the only exit, and nothing on screen said so.
///
/// A profile in the store is the fact that matters, so it is what gets asked.
/// The flag is now only a tiebreaker for the ordinary case.
struct RootView: View {
    var storeWasReset = false

    @Environment(LaunchState.self) private var launchState

    /// Filtered to ACTIVE profiles, matching what every screen inside the tab
    /// bar queries. Counting soft-deleted ones here would put the user back in
    /// the same dead end by a slower route: profiles exist, none are usable.
    @Query(filter: #Predicate<Profile> { $0.isActive }) private var profiles: [Profile]

    private var needsOnboarding: Bool {
        RootRoute.needsOnboarding(activeProfileCount: profiles.count,
                                  flagSaysComplete: launchState.hasCompletedOnboarding)
    }

    /// What the UI tests read to find out WHICH screen they are looking at.
    ///
    /// Three CI runs were spent guessing why the smoke test could not find a
    /// "Today" tab, because a failing XCUITest can say "element not found" and
    /// nothing else — the hierarchy dump it prints is swallowed by the log
    /// formatter. The app can simply say which branch it took, and then a
    /// failure names its own cause.
    ///
    /// The profile count rides along because "setup is showing" has two very
    /// different meanings — no profile, or a profile the flag is hiding — and
    /// they need different fixes.
    private var stateIdentifier: String {
        "root:\(needsOnboarding ? "onboarding" : "main"):profiles-\(profiles.count)"
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingFlow(storeWasReset: storeWasReset)
            } else {
                MainTabView()
            }
        }
        .accessibilityIdentifier(stateIdentifier)
        .animation(.easeInOut(duration: 0.25), value: needsOnboarding)
        // NO `onAppear` RECONCILIATION HERE, AND IT WAS WRITTEN AND REMOVED.
        //
        // The first version cleared a stale flag on appearance, to "heal" it
        // rather than re-decide every launch. That reintroduces the same class
        // of bug from the other side: on the first frame the profile may not
        // exist YET — a seeded test run, a store still opening — and clearing
        // the flag then would strand the user in setup permanently even once
        // the profile arrived a frame later.
        //
        // The reconciliation is also unnecessary. `needsOnboarding` reads the
        // store every time, so a stale flag cannot route anyone wrongly, and
        // finishing setup sets the flag honestly. Deriving the answer beats
        // caching it and then repairing the cache.
    }
}

// MARK: - Routing
//
// Pulled out of the view so it can be TESTED. The app shipped to TestFlight
// unable to reach setup, past 460 passing tests, because not one of them
// touched this decision — it was three words inside a `body`, and a `body` is
// not something the test suite can ask a question of.

enum RootRoute {

    /// Whether to show setup instead of the app.
    ///
    /// Both conditions matter and they are ORed, not ANDed:
    ///
    ///   - No usable profile means setup, whatever the flag claims. This is the
    ///     one that was missing, and its absence made a stale flag permanent.
    ///   - The flag not being set means setup even if a profile somehow exists,
    ///     so a partially-written profile does not skip the disclaimer — which
    ///     is a compliance gate, not a formality.
    static func needsOnboarding(activeProfileCount: Int, flagSaysComplete: Bool) -> Bool {
        activeProfileCount == 0 || !flagSaysComplete
    }
}

// MARK: - Main navigation
//
// iPad regular width gets a NavigationSplitView; everything else gets a TabView.
// docs/05-DESIGN-SYSTEM.md section 6.

struct MainTabView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: Tab = .today

    enum Tab: String, CaseIterable, Identifiable {
        case today, train, progress, learn, profile
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today:    "Today"
            case .train:    "Train"
            case .progress: "Progress"
            case .learn:    "Learn"
            case .profile:  "Profile"
            }
        }

        var systemImage: String {
            switch self {
            case .today:    "sun.max"
            case .train:    "eye"
            case .progress: "chart.line.uptrend.xyaxis"
            case .learn:    "book"
            case .profile:  "person.crop.circle"
            }
        }
    }

    /// iOS's `List(selection:)` takes an OPTIONAL binding. Passing a
    /// non-optional `Binding<Tab>` makes Swift resolve to a macOS-only overload
    /// and fail with "unavailable in iOS" — which is a confusing way to report
    /// a type mismatch. This bridges the two, and refuses to go nil so the
    /// detail pane always has something to show.
    private var sidebarSelection: Binding<Tab?> {
        Binding(
            get: { selection },
            set: { newValue in if let newValue { selection = newValue } }
        )
    }

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(selection: sidebarSelection) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.title, systemImage: tab.systemImage).tag(tab)
                    }
                }
                .navigationTitle("Amblyo")
                .navigationSplitViewColumnWidth(min: Layout.sidebarMin,
                                                ideal: Layout.sidebarIdeal,
                                                max: Layout.sidebarMax)
            } detail: {
                NavigationStack { destination(for: selection) }
            }
        } else {
            TabView(selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    NavigationStack { destination(for: tab) }
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                        // A STABLE IDENTIFIER, BECAUSE THE VISIBLE LABEL IS NOT
                        // A STABLE TEST HOOK. The tab bar's rendering is
                        // Apple's, it changes between iOS versions, and a test
                        // that searches for the word "Today" is really asserting
                        // how the system chose to draw a tab this year.
                        .accessibilityIdentifier("tab.\(tab.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: Tab) -> some View {
        switch tab {
        case .today:    TodayView()
        case .train:    TrainView()
        case .progress: ProgressDashboardView()
        case .learn:    LearnView()
        case .profile:  ProfileTabView()
        }
    }
}

// MARK: - Launch state

@Observable
final class LaunchState {
    private static let onboardingKey = "amblyo.hasCompletedOnboarding"

    var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    init() {
        hasCompletedOnboarding = LaunchArguments.isUITesting
            ? true
            : UserDefaults.standard.bool(forKey: Self.onboardingKey)
    }
}

// MARK: - Launch arguments
//
// Used by fastlane snapshot and the UI tests. docs/11-SCREENSHOTS-SPEC.md.

enum LaunchArguments {
    static var isUITesting: Bool { has("-uitest-seed-demo-data") || has("-uitest-unlock-pro") }
    static var shouldSeedDemoData: Bool { has("-uitest-seed-demo-data") }
    static var shouldUnlockPro: Bool { has("-uitest-unlock-pro") }

    private static func has(_ flag: String) -> Bool {
        CommandLine.arguments.contains(flag)
    }
}
