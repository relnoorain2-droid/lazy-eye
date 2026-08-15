//
//  OnboardingFlow.swift
//
//  The six-step setup wizard, and the one place a Profile gets created.
//
//  STRUCTURE
//  A single scrolling page per step with a fixed footer, rather than a TabView of
//  cards. Two reasons: a card carousel cannot hold the disclaimer or the
//  calibration step without scrolling inside a paging view, which fights the
//  gesture; and a fixed footer means the Continue button is in the same place on
//  every step, which matters more than novelty for a screen people see once.
//
//  COMMIT SEMANTICS
//  Nothing touches SwiftData until `commit()` on the final step. If that throws -
//  realistically only a disk-full or a corrupt store - the user stays on the last
//  step with a visible error instead of landing in an app with no profile.
//
//  docs/02-PRD.md section 4, docs/13-BUILD-ROADMAP.md phase 3c.
//

import SwiftUI
import SwiftData

@MainActor
struct OnboardingFlow: View {

    /// True when the previous store could not be opened and was rebuilt. Setup
    /// then explains why the user is here again rather than letting them think
    /// the app simply forgot them.
    var storeWasReset = false

    @State private var step: OnboardingStep = .welcome
    @State private var draft = OnboardingDraft()
    @State private var commitError: String?
    @State private var isCommitting = false

    @Environment(\.modelContext) private var context
    @Environment(LaunchState.self) private var launchState
    @Environment(SettingsStore.self) private var settings
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                if storeWasReset, step == .welcome {
                    SafetyBanner(
                        level: .caution,
                        title: "Your saved data couldn't be opened",
                        message: "The app had to start a fresh store, so previous profiles and history are gone. Nothing was sent anywhere — it was only ever on this device. Setting up again takes a couple of minutes.")
                        .padding(.horizontal)
                        .padding(.bottom, Spacing.sm)
                }
                content
                footer
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ProgressView(value: step.progress)
                .tint(.brandPrimary)
                .accessibilityLabel("Setup progress")
                .accessibilityValue("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")

            HStack {
                Text(step.title)
                    .font(TypeScale.caption().weight(.semibold))
                Text("· \(step.subtitle)")
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(step.rawValue + 1)/\(OnboardingStep.allCases.count)")
                    .font(TypeScale.caption().monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .readableContentWidth()
    }

    // MARK: Content

    private var content: some View {
        ScrollView {
            currentStepView
                .padding(.horizontal)
                .padding(.bottom, Spacing.xl)
                .readableContentWidth()
                // Re-runs the transition and, importantly, resets scroll position
                // when the step changes. Without the id, step 5 opens scrolled to
                // wherever step 4 was left.
                .id(step)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                          removal: .opacity))
        }
        .scrollDismissesKeyboard(.interactively)
        .animation(reduceMotion ? nil : Motion.standard, value: step)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .welcome:     WelcomeStepView()
        case .disclaimer:  DisclaimerStepView(draft: $draft)
        case .profile:     ProfileStepView(draft: $draft)
        case .sound:       SoundStepView(draft: $draft)
        case .calibration: CalibrationStepView(draft: $draft)
        case .ready:       ReadyStepView(draft: draft)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: Spacing.sm) {
            if let commitError {
                SafetyBanner(level: .critical,
                             title: "Couldn't save your setup",
                             message: commitError)
            }

            if let reason = draft.blockingReason(for: step) {
                Text(reason)
                    .font(TypeScale.caption())
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isStaticText)
            }

            AmblyoButton(
                title: step.isLast ? "Start training" : "Continue",
                systemImage: step.isLast ? "play.fill" : nil,
                isLoading: isCommitting
            ) {
                advance()
            }
            .disabled(!draft.canAdvance(from: step) || isCommitting)
        }
        .padding(.horizontal)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
        .readableContentWidth()
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let previous = step.previous {
                Button {
                    withAnimation(reduceMotion ? nil : Motion.standard) { step = previous }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }

    // MARK: Navigation

    private func advance() {
        guard draft.canAdvance(from: step) else { return }

        if let next = step.next {
            withAnimation(reduceMotion ? nil : Motion.standard) { step = next }
            return
        }
        commit()
    }

    // MARK: Commit

    private func commit() {
        isCommitting = true
        commitError = nil

        do {
            try persist()
            launchState.hasCompletedOnboarding = true
        } catch {
            commitError = error.localizedDescription
        }
        isCommitting = false
    }

    /// One transaction: profile, calibration, and the app-level sound settings.
    private func persist() throws {
        let repository = ProfileRepository(context: context)

        let profile = try repository.create(
            name: draft.resolvedName,
            birthYear: draft.birthYear,
            ageGroup: draft.ageGroup,
            amblyopicEye: draft.amblyopicEye,
            wearsCorrection: draft.wearsCorrection,
            // `isPro` lives on EntitlementStatus, not on the manager - the
            // manager exposes `status`, and grace period and billing retry both
            // still count as entitled.
            isPro: subscriptions.status.isPro
        )
        profile.preferences = draft.preferences

        let calibration = CalibrationProfile(
            screenPointsPerCM: draft.screenPointsPerCM,
            screenSizeUserVerified: draft.screenSizeUserVerified,
            viewingDistanceCM: draft.viewingDistanceCM,
            deviceIdentifier: draft.deviceIdentifier
        )
        try repository.setCalibration(calibration, for: profile)

        // Audio lives in SettingsStore (device-wide), not on the Profile, because
        // the person holding the device is the one who hears it regardless of
        // which family member's profile is active.
        settings.musicEnabled = draft.musicEnabled
        settings.soundEffectsEnabled = draft.soundEffectsEnabled
        settings.voiceGuidanceEnabled = draft.voiceGuidanceEnabled
        settings.hasSeenSoundChoice = true
    }
}

// MARK: - Previews

#Preview("Onboarding") {
    OnboardingFlow()
        .environment(LaunchState())
        .environment(SettingsStore())
        .environment(SubscriptionManager())
        .modelContainer(try! .amblyo(inMemory: true))
}
