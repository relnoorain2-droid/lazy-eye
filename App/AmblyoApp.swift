//
//  AmblyoApp.swift
//  Amblyo — Lazy Eye Training
//
//  Entry point. See docs/04-ARCHITECTURE.md and docs/02-PRD.md section 4.
//
//  PHASE 1 SCAFFOLD: the tab shell and app-level wiring are real; every feature
//  view is a placeholder that Phase 2+ replaces. The launch-order comments below
//  are load-bearing — read them before reordering anything in `body`.
//

import SwiftUI
import SwiftData

@main
struct AmblyoApp: App {

    /// Shared model container. Phase 2 replaces the schema with the real models
    /// from docs/04-ARCHITECTURE.md section 3.
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

    init() {
        do {
            // UI test runs get a throwaway in-memory store so the seeder can
            // populate a clean 12-week history every time.
            modelContainer = try .amblyo(inMemory: LaunchArguments.isUITesting)
        } catch {
            // A container failure is unrecoverable. Crash loudly in debug; in
            // release fall back to an in-memory store so the user gets a working
            // app rather than a dead launch.
            assertionFailure("ModelContainer failed: \(error)")
            modelContainer = try! .amblyo(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(subscriptions)
                .environment(launchState)
                .task {
                    await subscriptions.start()
                    AudioEngine.configureSession()
                    if LaunchArguments.shouldSeedDemoData {
                        DemoDataSeeder.seed(into: modelContainer.mainContext)
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}

// MARK: - Root

struct RootView: View {
    @Environment(LaunchState.self) private var launchState

    var body: some View {
        Group {
            if launchState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingPlaceholderView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: launchState.hasCompletedOnboarding)
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

    var body: some View {
        if sizeClass == .regular {
            NavigationSplitView {
                List(Tab.allCases, selection: $selection) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
                .navigationTitle("Amblyo")
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
            } detail: {
                NavigationStack { destination(for: selection) }
            }
        } else {
            TabView(selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    NavigationStack { destination(for: tab) }
                        .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                        .tag(tab)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: Tab) -> some View {
        switch tab {
        case .today:    PlaceholderView(tab: .today)
        case .train:    PlaceholderView(tab: .train)
        case .progress: PlaceholderView(tab: .progress)
        case .learn:    PlaceholderView(tab: .learn)
        case .profile:  PlaceholderView(tab: .profile)
        }
    }
}

// MARK: - Phase 1 placeholders (deleted in Phase 2/3)

struct PlaceholderView: View {
    let tab: MainTabView.Tab

    var body: some View {
        ContentUnavailableView {
            Label(tab.title, systemImage: tab.systemImage)
        } description: {
            Text("Phase 1 scaffold. See docs/13-BUILD-ROADMAP.md.")
        }
        .navigationTitle(tab.title)
    }
}

struct OnboardingPlaceholderView: View {
    @Environment(LaunchState.self) private var launchState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eyeglasses")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Amblyo")
                .font(.largeTitle.bold())
            Text("Onboarding is built in Phase 3.")
                .foregroundStyle(.secondary)
            Button("Continue") {
                launchState.hasCompletedOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
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
