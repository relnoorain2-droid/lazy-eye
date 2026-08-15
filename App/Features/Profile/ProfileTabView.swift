//
//  ProfileTabView.swift
//
//  Profile and settings. Everything that isn't training lives here.
//
//  WHY ONE SCREEN AND NOT A SETTINGS TREE
//  The things people actually come here to change are few: who is training, how
//  long a session runs, whether it makes noise, and whether they're paying. A
//  three-level settings hierarchy hides those behind navigation for the sake of
//  tidiness. Sections in one scroll view are findable.
//
//  THE ORDER IS DELIBERATE.
//  Anything the user is missing comes first (unassigned eye, uncalibrated
//  screen), then who's training, then the session, then the subscription, then
//  legal, then the destructive things at the very bottom where nobody taps by
//  accident.
//
//  REVIEW-CRITICAL ITEMS ON THIS SCREEN
//    · Restore Purchases, reachable without a paywall (3.1.1)
//    · subscription price, period and management link (3.1.2)
//    · Privacy Policy and the medical disclaimer, in-app (1.4.1, 5.1.1)
//    · Delete All Data, which genuinely deletes and is gated behind a
//      confirmation, not a toast (5.1.1(v))
//
//  docs/02-PRD.md section 4, docs/08-COMPLIANCE-LEGAL.md sections 1-5.
//

import SwiftUI
import SwiftData
import StoreKit

@MainActor
struct ProfileTabView: View {

    @Query(sort: \Profile.createdAt) private var profiles: [Profile]

    @Environment(\.modelContext) private var context
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(LaunchState.self) private var launchState
    @Environment(\.theme) private var theme

    @State private var showingPaywall = false
    @State private var showingGlassesSetup = false
    @State private var showingSelfCheck = false
    @State private var showingScreenCalibration = false
    @State private var showingNewProfile = false
    @State private var openDocument: LegalDocument?
    @State private var confirmingDeleteAll = false
    @State private var confirmingDeleteProfile: Profile?
    @State private var isRestoring = false
    @State private var message: String?
    @State private var errorMessage: String?

    private var active: Profile? { profiles.first { $0.isActive } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {

                if let errorMessage {
                    SafetyBanner(level: .caution, title: "That didn't work",
                                 message: errorMessage)
                }
                if let message {
                    SafetyBanner(level: .info, title: message)
                }

                if let active {
                    setupSection(active)
                    peopleSection(active)
                    sessionSection(active)
                    glassesSection(active)
                }
                subscriptionSection
                appearanceSection
                soundSection
                legalSection
                dangerSection
                versionFooter
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle("Profile")
        .sheet(isPresented: $showingPaywall) {
            PaywallView(context: .general, isKidsMode: active?.isKidsMode ?? false)
        }
        .sheet(isPresented: $showingGlassesSetup) {
            if let active {
                AnaglyphCalibrationView(profile: active)
            }
        }
        .sheet(isPresented: $showingSelfCheck) {
            AnaglyphSelfCheckView(calibration: active?.calibration)
        }
        .sheet(isPresented: $showingScreenCalibration) {
            if let active {
                NavigationStack { ScreenCalibrationSheet(profile: active) }
            }
        }
        .sheet(isPresented: $showingNewProfile) {
            NavigationStack { NewProfileSheet() }
        }
        .sheet(item: $openDocument) { document in
            NavigationStack { LegalDocumentView(document: document) }
        }
        .confirmationDialog("Delete everything?",
                            isPresented: $confirmingDeleteAll,
                            titleVisibility: .visible) {
            Button("Delete all data", role: .destructive) { deleteAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every profile, session and measurement is removed from this device. This cannot be undone, and there is no cloud copy to restore from.")
        }
        .confirmationDialog("Delete this profile?",
                            isPresented: Binding(
                                get: { confirmingDeleteProfile != nil },
                                set: { if !$0 { confirmingDeleteProfile = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let target = confirmingDeleteProfile { delete(target) }
            }
            Button("Cancel", role: .cancel) { confirmingDeleteProfile = nil }
        } message: {
            Text("Their sessions and measurements go with them.")
        }
    }

    // MARK: Sections

    /// Only appears when something is genuinely missing, and names one thing at
    /// a time. A permanent checklist becomes wallpaper.
    @ViewBuilder
    private func setupSection(_ profile: Profile) -> some View {
        if !profile.isSetUp {
            AmblyoCard(accent: Color.caution) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Finish setting up")
                        .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                    Text(TodayView.setupMessage(for: profile))
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                    if profile.calibration?.isComplete != true {
                        AmblyoButton(title: "Measure my screen", systemImage: "ruler",
                                     style: .secondary) { showingScreenCalibration = true }
                    }
                }
            }
        }
    }

    private func peopleSection(_ active: Profile) -> some View {
        section("Who's training") {
            // Selection and delete are SIBLING buttons, not nested. A Button
            // inside another Button's label doesn't reliably get the tap — the
            // outer one swallows it — so the delete control would have switched
            // profiles instead of offering to remove one.
            ForEach(profiles) { profile in
                HStack {
                    Button {
                        makeActive(profile)
                    } label: {
                        HStack {
                            Image(systemName: profile.isActive
                                  ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(profile.isActive
                                                 ? Color.brandPrimary : Color.textSecondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(profile.name)
                                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                                    .foregroundStyle(Color.textPrimary)
                                Text(Self.subtitle(for: profile))
                                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                                    .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(profile.isActive ? [.isSelected] : [])

                    if profiles.count > 1 {
                        Button {
                            confirmingDeleteProfile = profile
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(Color.critical)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Delete \(profile.name)")
                    }
                }
                .padding(.vertical, Spacing.xs)
            }

            Divider().overlay(Color.separatorLine)

            // The limit is enforced by the repository; this button explains it
            // rather than failing silently when the fifth profile is refused.
            Button {
                if profiles.count >= ProfileRepository.limit(isPro: subscriptions.status.isPro) {
                    showingPaywall = true
                } else {
                    showingNewProfile = true
                }
            } label: {
                Label("Add someone", systemImage: "person.badge.plus")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
            }
            .tint(.brandPrimary)

            Text("Up to \(ProfileRepository.limit(isPro: subscriptions.status.isPro)) on your current plan.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
    }

    static func subtitle(for profile: Profile) -> String {
        var parts: [String] = [profile.ageGroup.displayName]
        parts.append(profile.amblyopicEye == .unknown
                     ? "eye not set"
                     : "\(profile.amblyopicEye.displayName) eye")
        if profile.isKidsMode { parts.append("kids mode") }
        return parts.joined(separator: " · ")
    }

    private func sessionSection(_ profile: Profile) -> some View {
        section("Your session") {
            // The picker offers only lengths at or under this age group's cap.
            // Offering 20 minutes to a six-year-old and then silently clipping
            // it to 10 is worse than not offering it.
            Picker("Session length", selection: Binding(
                get: { profile.preferences.preferredSessionSeconds ?? profile.ageGroup.defaultSessionSeconds },
                set: { newValue in
                    var preferences = profile.preferences
                    preferences.preferredSessionSeconds = newValue
                    profile.preferences = preferences
                    save()
                })) {
                ForEach(Self.sessionLengthOptions(cap: profile.ageGroup.dailyCapSeconds), id: \.self) { seconds in
                    Text("\(seconds / 60) min").tag(seconds)
                }
            }
            .font(TypeScale.callout(rounded: theme.usesRoundedFont))

            Text("Daily limit for this age group: \(profile.ageGroup.dailyCapSeconds / 60) minutes. Sessions can't run past it.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            Divider().overlay(Color.separatorLine)

            Picker("Weaker eye", selection: Binding(
                get: { profile.amblyopicEye },
                set: { profile.amblyopicEye = $0; save() })) {
                ForEach(Eye.allCases, id: \.self) { eye in
                    Text(eye.displayName).tag(eye)
                }
            }
            .font(TypeScale.callout(rounded: theme.usesRoundedFont))

            Toggle("I wear glasses or lenses for this", isOn: Binding(
                get: { profile.wearsCorrection },
                set: { profile.wearsCorrection = $0; save() }))
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .tint(.brandPrimary)

            Divider().overlay(Color.separatorLine)

            Button {
                showingScreenCalibration = true
            } label: {
                HStack {
                    Label("Screen and distance", systemImage: "ruler")
                    Spacer()
                    Text(calibrationSummary(profile))
                        .foregroundStyle(Color.textSecondary)
                }
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
            }
            .tint(.brandPrimary)
        }
    }

    /// Session lengths offered, in seconds. Never above the age cap, and never
    /// above the absolute per-session ceiling.
    static func sessionLengthOptions(cap: Int) -> [Int] {
        let ceiling = min(cap, SafetyLimits.maxSessionSeconds)
        return [5, 10, 15, 20, 25, 30]
            .map { $0 * 60 }
            .filter { $0 <= ceiling }
    }

    private func calibrationSummary(_ profile: Profile) -> String {
        guard let calibration = profile.calibration, calibration.isComplete else {
            return "Not set"
        }
        let inches = ScreenGeometry.diagonalInches(forPointsPerCM: calibration.screenPointsPerCM)
        return String(format: "%.1f\" · %.0f cm", inches, calibration.viewingDistanceCM)
    }

    @ViewBuilder
    private func glassesSection(_ profile: Profile) -> some View {
        section("Red-cyan glasses") {
            if profile.canUseDichopticTrack {
                Text("Set up. The two-eye exercises are available in Train.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                AmblyoButton(title: "Check they're working", systemImage: "eye.trianglebadge.exclamationmark",
                             style: .secondary) { showingSelfCheck = true }
                AmblyoButton(title: "Set up again", systemImage: "arrow.clockwise",
                             style: .tertiary) { showingGlassesSetup = true }
            } else {
                Text("A cheap pair of red-cyan anaglyph glasses unlocks the two-eye exercises. One-minute setup.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                AmblyoButton(title: "Set up glasses", systemImage: "eyeglasses",
                             style: .secondary) { showingGlassesSetup = true }
            }
        }
    }

    private var subscriptionSection: some View {
        section("Subscription") {
            HStack {
                Text(Self.statusLabel(subscriptions.status))
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                Spacer()
            }

            if !subscriptions.status.isPro {
                AmblyoButton(title: "See plans", systemImage: "sparkles") {
                    showingPaywall = true
                }
            }

            // Restore must be reachable WITHOUT going through the paywall.
            // Someone who has already paid should not have to look at a sales
            // screen to get their purchase back — and 3.1.1 agrees.
            Button {
                Task { await restore() }
            } label: {
                if isRestoring {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Restore Purchases")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                }
            }
            .tint(.brandPrimary)
            .disabled(isRestoring)

            Link("Manage or cancel", destination: ExternalLinks.manageSubscriptions)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .tint(.brandPrimary)
        }
    }

    static func statusLabel(_ status: EntitlementStatus) -> String {
        switch status {
        case .unknown: "Checking…"
        case .free: "Free plan"
        case .pro(let expires):
            if let expires {
                "Full access until \(expires.formatted(date: .abbreviated, time: .omitted))"
            } else {
                "Full access"
            }
        case .inGracePeriod:
            "Full access — there's a problem with your payment method"
        case .inBillingRetry:
            "Full access — Apple is retrying your payment"
        }
    }

    private var appearanceSection: some View {
        section("Appearance") {
            Picker("Theme", selection: Binding(
                get: { settings.themePreference },
                set: { settings.themePreference = $0 })) {
                ForEach(SettingsStore.ThemePreference.allCases, id: \.self) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var soundSection: some View {
        section("Sound and feel") {
            Toggle("Sound effects", isOn: Binding(
                get: { settings.soundEffectsEnabled },
                set: { settings.soundEffectsEnabled = $0 }))
            Toggle("Background music", isOn: Binding(
                get: { settings.musicEnabled },
                set: { settings.musicEnabled = $0 }))
            Toggle("Spoken guidance", isOn: Binding(
                get: { settings.voiceGuidanceEnabled },
                set: { settings.voiceGuidanceEnabled = $0 }))
            Toggle("Haptics", isOn: Binding(
                get: { settings.hapticsEnabled },
                set: { settings.hapticsEnabled = $0 }))

            Text("Sound effects and haptics are on; music and spoken guidance are off. Your phone's silent switch always wins.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
        .tint(.brandPrimary)
        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
    }

    private var legalSection: some View {
        section("About") {
            ForEach([LegalDocument.medicalDisclaimer, .privacyPolicy,
                     .subscriptionTerms, .evidenceAndMethods], id: \.self) { document in
                Button { openDocument = document } label: {
                    HStack {
                        Label(document.linkTitle, systemImage: document.systemImage)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                }
                .tint(.brandPrimary)
            }

            Link("Terms of Use (EULA)", destination: ExternalLinks.appleStandardEULA)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .tint(.brandPrimary)
        }
    }

    private var dangerSection: some View {
        section("Data") {
            Text("Everything stays on this device. There's no account, no server, and nothing is uploaded.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            AmblyoButton(title: "Delete all data", systemImage: "trash",
                         style: .destructive) { confirmingDeleteAll = true }
        }
    }

    private var versionFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Amblyo \(Self.versionString)")
            Text("Not a medical device. Not a substitute for professional eye care.")
        }
        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
        .foregroundStyle(Color.textSecondary)
        .padding(.top, Spacing.md)
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    // MARK: Section shell

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        // `content` is non-escaping, and `AmblyoCard` STORES its closure — so
        // calling `content()` inside that closure would let a non-escaping
        // parameter escape. Building the subtree first and capturing the
        // resulting VALUE sidesteps it without marking anything @escaping,
        // which would force every caller's closure to be heap-allocated.
        let inner = content()
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont).weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
            AmblyoCard {
                VStack(alignment: .leading, spacing: Spacing.sm) { inner }
            }
        }
    }

    // MARK: Actions

    private func save() {
        do {
            try context.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeActive(_ profile: Profile) {
        do {
            try ProfileRepository(context: context).makeActive(profile)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ profile: Profile) {
        confirmingDeleteProfile = nil
        do {
            try ProfileRepository(context: context).delete(profile)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAllData() {
        do {
            try ProfileRepository(context: context).deleteAllData()
            // The onboarding flag has to go with the data. Leaving it set drops
            // the user into a main tab view with no profile in it — every screen
            // saying "No profile yet" and no route back to setup. Clearing it
            // sends them to onboarding, which is the only honest place to be
            // after deleting everything.
            launchState.hasCompletedOnboarding = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isRestoring = true
        let restored = await subscriptions.restore()
        isRestoring = false
        message = restored
            ? "Your subscription is active again."
            : "No previous subscription found on this Apple account."
    }
}

// MARK: - Screen calibration, from settings

/// Re-runs the screen measurement outside onboarding.
///
/// It reuses `CardCheckView` and `DiagonalEntryView` rather than reimplementing
/// them — those two views are where the actual geometry lives, and a second
/// implementation would be a second thing to get wrong. What this adds is
/// writing the result to the live `CalibrationProfile` instead of a draft.
@MainActor
struct ScreenCalibrationSheet: View {

    let profile: Profile

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var pointsPerCM: Double = 0
    @State private var userVerified = false
    @State private var distanceCM: Double = 50
    @State private var showingCardCheck = false
    @State private var showingDiagonalEntry = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let errorMessage {
                    SafetyBanner(level: .caution, title: "Couldn't save", message: errorMessage)
                }

                Text("Exercise sizes are angles, not pixels. Getting these two numbers right is what makes a difficulty level mean the same thing on any device.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                AmblyoCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Screen")
                            .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                        Text(ScreenGeometry.isPlausible(pointsPerCM)
                             ? String(format: "About %.1f inches diagonal.",
                                      ScreenGeometry.diagonalInches(forPointsPerCM: pointsPerCM))
                             : "Not measured yet.")
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                        AmblyoButton(title: "Check with a bank card", systemImage: "creditcard",
                                     style: .secondary) { showingCardCheck = true }
                        AmblyoButton(title: "Type the screen size instead", systemImage: "keyboard",
                                     style: .tertiary) { showingDiagonalEntry = true }
                    }
                }

                AmblyoCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Viewing distance")
                            .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                        Text(String(format: "%.0f cm", distanceCM))
                            .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))
                        Slider(value: $distanceCM,
                               in: ScreenGeometry.plausibleViewingDistanceCM,
                               step: 1)
                            .tint(.brandPrimary)
                            .accessibilityValue(String(format: "%.0f centimetres", distanceCM))
                        Text("Hold the device where you'll actually use it, then set this to match. Guessing high makes everything easier than it should be.")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                AmblyoButton(title: "Save", systemImage: "checkmark") { commit() }
                    .disabled(!ScreenGeometry.isPlausible(pointsPerCM))
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle("Screen and distance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: $showingCardCheck) {
            CardCheckView(pointsPerCM: $pointsPerCM, userVerified: $userVerified)
        }
        .sheet(isPresented: $showingDiagonalEntry) {
            DiagonalEntryView(pointsPerCM: $pointsPerCM, userVerified: $userVerified)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let calibration = profile.calibration, calibration.isComplete {
            pointsPerCM = calibration.screenPointsPerCM
            userVerified = calibration.screenSizeUserVerified
            distanceCM = calibration.viewingDistanceCM
        } else {
            pointsPerCM = ScreenGeometry.currentPointsPerCM()
            distanceCM = ScreenGeometry.suggestedViewingDistanceCM()
        }
    }

    private func commit() {
        do {
            if let existing = profile.calibration {
                // Updated in place, so the ANAGLYPH half of the calibration
                // survives. Replacing the row would silently un-set the glasses
                // setup, which has nothing to do with screen size.
                existing.screenPointsPerCM = pointsPerCM
                existing.screenSizeUserVerified = userVerified
                existing.viewingDistanceCM = distanceCM
                existing.calibratedAt = .now
                existing.deviceIdentifier = ScreenGeometry.deviceIdentifier()
                try context.save()
            } else {
                let calibration = CalibrationProfile(
                    screenPointsPerCM: pointsPerCM,
                    screenSizeUserVerified: userVerified,
                    viewingDistanceCM: distanceCM,
                    deviceIdentifier: ScreenGeometry.deviceIdentifier())
                try ProfileRepository(context: context)
                    .setCalibration(calibration, for: profile)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - New profile

@MainActor
struct NewProfileSheet: View {

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var name = ""
    @State private var ageGroup: AgeGroup = .thirteenPlus
    @State private var amblyopicEye: Eye = .unknown
    @State private var wearsCorrection = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let errorMessage {
                    SafetyBanner(level: .caution, title: "Couldn't add", message: errorMessage)
                }

                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(TypeScale.body(rounded: theme.usesRoundedFont))

                Picker("Age", selection: $ageGroup) {
                    ForEach(AgeGroup.allCases, id: \.self) { group in
                        Text(group.displayName).tag(group)
                    }
                }
                Picker("Weaker eye", selection: $amblyopicEye) {
                    ForEach(Eye.allCases, id: \.self) { eye in
                        Text(eye.displayName).tag(eye)
                    }
                }
                Toggle("Wears glasses or lenses", isOn: $wearsCorrection)
                    .tint(.brandPrimary)

                Text("Each person gets their own screen measurement, plan and history. Under-13s get shorter sessions and a parent gate by default.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                AmblyoButton(title: "Add", systemImage: "person.badge.plus") { create() }
            }
            .font(TypeScale.callout(rounded: theme.usesRoundedFont))
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
        .navigationTitle("Add someone")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try ProfileRepository(context: context).create(
                name: trimmed.isEmpty ? "Someone" : trimmed,
                ageGroup: ageGroup,
                amblyopicEye: amblyopicEye,
                wearsCorrection: wearsCorrection,
                isPro: subscriptions.status.isPro)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
