//
//  AssessmentView.swift
//
//  The check-in screen. Four short sub-tests, a rest between each, and a summary
//  that refuses to overstate what was measured.
//
//  WHY THE REST BETWEEN SUB-TESTS IS A SCREEN AND NOT A PAUSE
//  Each sub-test changes what the user has to do — cover an eye, put the glasses
//  on, look for depth rather than detail. Sliding straight from one into the next
//  means the first few trials of every sub-test measure confusion. A deliberate
//  card, read at the user's own pace, costs twenty seconds and removes that.
//
//  THE SUMMARY NEVER SAYS "BETTER"
//  Direction of travel belongs to the Progress screen's trend logic, which
//  refuses to claim one until the confidence interval supports it. This screen
//  reports what today's numbers were and stops.
//
//  docs/03-EXERCISE-CATALOG.md assessment battery, docs/08-COMPLIANCE-LEGAL.md
//  section 2.
//

import SwiftUI
import SwiftData

@MainActor
struct AssessmentView: View {

    let profile: Profile
    var onFinish: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    @State private var runner: AssessmentRunner?
    @State private var saveError: String?

    /// `forDrawing`, for the same reason as `ExerciseSessionScreen`: an
    /// uncalibrated profile makes every angular size zero, and the check-in
    /// would present a stimulus with no pixels in it. `CalibrationProfile()`
    /// with no arguments is uncalibrated by default, so the old line produced
    /// exactly that whenever a profile had never been measured.
    private var calibration: CalibrationProfile {
        (profile.calibration ?? CalibrationProfile()).forDrawing
    }

    var body: some View {
        NavigationStack {
            Group {
                if let runner {
                    content(runner)
                } else {
                    intro
                }
            }
            .padding()
            .readableContentWidth()
            .screenBackground()
            .navigationTitle("Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Always available. Someone whose eyes hurt must be able to
                    // stop, and stopping DISCARDS the unfinished sub-tests
                    // rather than writing partial numbers to the chart.
                    Button("Stop") {
                        runner?.abandon()
                        onFinish()
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: Screens

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("A few short measurements")
                .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))

            Text("About \(AssessmentBattery.estimatedSeconds / 60) minutes. These are the numbers the Progress screen compares over time, so it is worth doing them when you are not tired.")
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            let plan = AssessmentRunner(profile: profile, calibration: calibration,
                                        isPro: subscriptions.status.isPro).plan
            ForEach(plan, id: \.rawValue) { test in
                AmblyoCard {
                    HStack(spacing: Spacing.md) {
                        Image(systemName: AssessmentBattery.requiresGlasses(test)
                              ? "eyeglasses" : "eye")
                            .foregroundStyle(Color.brandPrimary)
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(test.displayName)
                                .font(TypeScale.callout(rounded: theme.usesRoundedFont)
                                    .weight(.semibold))
                            Text(AssessmentBattery.requiresGlasses(test)
                                 ? "Glasses on, both eyes"
                                 : "One eye at a time")
                                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }

            if !subscriptions.status.isPro {
                Text("On the free plan you get the Balance check-in. The others come with a subscription.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }

            Text(AssessmentTest.scoreQualifier)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            AmblyoButton(title: "Start", systemImage: "play.fill") {
                let made = AssessmentRunner(profile: profile, calibration: calibration,
                                            isPro: subscriptions.status.isPro)
                made.start()
                runner = made
            }
        }
    }

    @ViewBuilder
    private func content(_ runner: AssessmentRunner) -> some View {
        switch runner.phase {
        case .ready:
            ProgressView()

        case .running(let index):
            running(runner, index: index)

        case .betweenTests(let next):
            rest(runner, nextIndex: next)

        case .finished(let result):
            finished(result)

        case .abandoned:
            VStack(spacing: Spacing.md) {
                Text("Stopped")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Text("Nothing was recorded. Coming back to this another day is fine — a rushed measurement is worse than none.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                AmblyoButton(title: "Close") { onFinish(); dismiss() }
            }
        }
    }

    private func running(_ runner: AssessmentRunner, index: Int) -> some View {
        VStack(spacing: Spacing.lg) {
            ProgressView(value: Double(runner.trialsInSubtest),
                         total: Double(AssessmentBattery.trialsPerSubtest))
                .tint(.brandPrimary)

            if let test = runner.currentTest {
                Text(test.displayName)
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                if runner.currentEye != .unknown {
                    Text("Cover your \(runner.currentEye.fellow.displayName.lowercased())")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // THE STIMULUS, NOT A ROW OF NUMBERS.
            //
            // This screen shipped to TestFlight showing buttons labelled 1, 2,
            // 3, 4 over an empty white area, with a comment saying the real
            // stimulus would arrive "in a later pass". A measurement screen with
            // nothing to measure is not an incomplete feature, it is a broken
            // one, and it should never have gone out. The sub-tests borrow real
            // registered exercises precisely so they can borrow the real
            // renderers too.
            if let trial = runner.currentTrial, let presenter = runner.currentPresenter {
                AssessmentTrialView(trial: trial,
                                    presenter: presenter,
                                    calibration: calibration,
                                    isAnswerable: true) { answer in
                    runner.respond(answer: answer)
                }
                .id(trial.id)
            } else if let trial = runner.currentTrial, runner.currentTest == .balance {
                // The free tier's ONLY measurement, and the one a reviewer is
                // most likely to open. It showed "not in this build yet" over an
                // empty panel — a broken free tier and a Guideline 2.1 rejection
                // in one screen.
                AssessmentBalanceView(trial: trial,
                                      calibration: calibration,
                                      isAnswerable: true) { answer in
                    runner.respond(answer: answer)
                }
                .id(trial.id)

            } else if let trial = runner.currentTrial, runner.currentTest == .stereo {
                AssessmentStereoView(trial: trial,
                                     calibration: calibration,
                                     isAnswerable: true) { answer in
                    runner.respond(answer: answer)
                }
                .id(trial.id)

            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 220)
            }

            Text("Answer as accurately as you can. Guessing is expected near the end.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func rest(_ runner: AssessmentRunner, nextIndex: Int) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "pause.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text("Take a moment")
                .font(TypeScale.headline(rounded: theme.usesRoundedFont))

            let next = runner.plan[nextIndex]
            Text(AssessmentBattery.requiresGlasses(next)
                 ? "Next: \(next.displayName). Put your red-cyan glasses on."
                 : "Next: \(next.displayName). You will cover one eye at a time.")
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            AmblyoButton(title: "I'm ready") { runner.continueToNextTest() }
        }
    }

    private func finished(_ result: AssessmentResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Done")
                .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))

            if let saveError {
                SafetyBanner(level: .caution, title: "Couldn't save", message: saveError)
            }

            ForEach(AssessmentBattery.summary(for: result), id: \.self) { line in
                AmblyoCard {
                    Text(line)
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                }
            }

            Text(AssessmentTest.scoreQualifier)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            AmblyoButton(title: "Save and close", systemImage: "checkmark") {
                save(result)
            }
        }
        .onAppear { saveError = nil }
    }

    private func save(_ result: AssessmentResult) {
        do {
            _ = try ProgressRepository(context: context).record(result, for: profile)
            onFinish()
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
