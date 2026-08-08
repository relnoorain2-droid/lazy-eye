//
//  TrainView.swift
//
//  The exercise library, and the only route into a session.
//
//  WHY THE CAP CHECK LIVES HERE AND NOT IN THE SESSION
//  A user who has used their daily allowance should be told before they commit
//  to starting, not thirty seconds in. `SessionRunner` still enforces the cap
//  independently - it must, because it is the thing that writes the record - but
//  a guard the user only discovers by hitting it is a bad guard.
//
//  docs/02-PRD.md section 4, docs/03-EXERCISE-CATALOG.md.
//

import SwiftUI
import SwiftData

@MainActor
struct TrainView: View {

    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.theme) private var theme

    @State private var launching: ExerciseDescriptor?
    @State private var secondsUsedToday = 0
    @State private var loadError: String?

    private var profile: Profile? { activeProfiles.first }

    var body: some View {
        Group {
            if let profile {
                content(for: profile)
            } else {
                ContentUnavailableView(
                    "No profile yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Finish setup to start training.")
                )
            }
        }
        .navigationTitle("Train")
        .task(id: profile?.id) { refreshUsage() }
        .fullScreenCover(item: $launching) { descriptor in
            sessionScreen(for: descriptor)
        }
    }

    // MARK: Library

    private func content(for profile: Profile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {

                if let loadError {
                    SafetyBanner(level: .caution, title: "Couldn't read today's history",
                                 message: loadError)
                }

                let cap = sessionCap(for: profile)
                if cap.isDailyCapReached {
                    SafetyBanner(
                        level: .info,
                        title: "That's today's practice done",
                        message: capMessage(for: profile, cap: cap)
                    )
                }

                if profile.calibration?.isComplete != true {
                    SafetyBanner(
                        level: .caution,
                        title: "Screen not calibrated",
                        message: "Exercise sizes will be approximate until this is set."
                    )
                }

                ForEach(availableExercises(for: profile)) { descriptor in
                    exerciseCard(descriptor, profile: profile, cap: cap)
                }

                let locked = ExerciseRegistry.lockedByPaywall(
                    for: profile,
                    canUseAnaglyph: profile.canUseDichopticTrack)
                if !locked.isEmpty {
                    lockedSection(locked)
                }

                Text("More exercises are being added. Everything here is included at no extra cost once you have it.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
            }
            .padding()
            .readableContentWidth()
        }
        .screenBackground()
    }

    private func exerciseCard(_ descriptor: ExerciseDescriptor,
                              profile: Profile,
                              cap: SessionCap) -> some View {
        AmblyoCard(accent: descriptor.track.tint) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(descriptor.title)
                            .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                        Text("\(descriptor.track.displayName) · \(descriptor.defaultDurationSeconds / 60) min")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    EvidenceBadge(tier: descriptor.evidenceTier, compact: true)
                }

                Text(descriptor.summary)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                Text("Trains: \(descriptor.targets)")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                AmblyoButton(title: "Start", systemImage: "play.fill") {
                    launching = descriptor
                }
                .disabled(cap.isDailyCapReached)
            }
        }
    }

    private func lockedSection(_ locked: [ExerciseDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("With a subscription")
                .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                .padding(.top, Spacing.md)

            ForEach(locked) { descriptor in
                AmblyoCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(descriptor.title)
                                .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                            Text(descriptor.summary)
                                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "lock")
                            .foregroundStyle(Color.textSecondary)
                            .accessibilityLabel("Requires a subscription")
                    }
                }
            }
        }
    }

    // MARK: Session

    @ViewBuilder
    private func sessionScreen(for descriptor: ExerciseDescriptor) -> some View {
        if let profile,
           let runner = SessionRunner(
               descriptor: descriptor,
               profile: profile,
               targetEye: trainingEye(for: profile),
               context: context,
               cap: sessionCap(for: profile),
               resuming: nil) {
            GaborOrientationView(
                runner: runner,
                calibration: profile.calibration ?? CalibrationProfile()
            ) { _ in
                launching = nil
                refreshUsage()
            }
        } else {
            // Registry and UI disagreeing is a programming error, not a user
            // error - but it must not be a blank screen in a shipped build.
            ContentUnavailableView("Couldn't start", systemImage: "exclamationmark.triangle",
                                   description: Text("This exercise isn't available right now."))
        }
    }

    /// Which eye this session trains. The amblyopic eye when we know it;
    /// otherwise both, which is what `.unknown` means downstream - never a
    /// blocking error, because many adults have never been told.
    private func trainingEye(for profile: Profile) -> Eye {
        profile.amblyopicEye
    }

    private func sessionCap(for profile: Profile) -> SessionCap {
        SessionCap(ageGroup: profile.ageGroup, secondsUsedToday: secondsUsedToday)
    }

    private func capMessage(for profile: Profile, cap: SessionCap) -> String {
        cap.isOverridable
            ? "A grown-up can allow more, but a short daily session works better than a long one."
            : "Come back tomorrow. Little and often is what makes this work."
    }

    private func availableExercises(for profile: Profile) -> [ExerciseDescriptor] {
        ExerciseRegistry.available(
            for: profile,
            isPro: subscriptions.isPro,
            canUseAnaglyph: profile.canUseDichopticTrack
        )
    }

    private func refreshUsage() {
        guard let profile else { return }
        do {
            secondsUsedToday = try SessionRepository(context: context)
                .secondsToday(for: profile)
            loadError = nil
        } catch {
            secondsUsedToday = 0
            loadError = error.localizedDescription
        }
    }
}
