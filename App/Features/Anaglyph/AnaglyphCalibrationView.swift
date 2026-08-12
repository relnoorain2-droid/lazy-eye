//
//  AnaglyphCalibrationView.swift
//
//  The four-step setup the dichoptic track needs before it can run: put the
//  glasses on, check the eyes can separate the colours at all, measure how much
//  each lens leaks, and confirm.
//
//  ORDER MATTERS AND IS NOT ARBITRARY.
//  The colour-discrimination check comes BEFORE the crosstalk measurement. If
//  someone cannot tell red from cyan, measuring their filters is a waste of
//  their time and — worse — produces a number that looks like a successful
//  calibration. Screening first means the failure path is short and kind.
//
//  docs/01-RESEARCH-BRIEF.md section 4, docs/05-DESIGN-SYSTEM.md section 8.
//

import SwiftUI
import SwiftData

@MainActor
struct AnaglyphCalibrationView: View {

    let profile: Profile
    var onFinish: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    private enum Step: Int, CaseIterable {
        case glassesOn, colourCheck, redLeak, cyanLeak, done

        var title: String {
            switch self {
            case .glassesOn: "Put your glasses on"
            case .colourCheck: "Quick colour check"
            case .redLeak: "First adjustment"
            case .cyanLeak: "Second adjustment"
            case .done: "All set"
            }
        }
    }

    @State private var step: Step = .glassesOn
    @State private var redLeak: Double = 0.08
    @State private var cyanLeak: Double = 0.08
    @State private var colourTrials: [AnaglyphCalibrator.DiscriminationTrial] = []
    @State private var colourIndex = 0
    @State private var colourCorrect = 0
    @State private var generator = SeededGenerator(seed: UInt64.random(in: 0..<UInt64.max))
    @State private var result: AnaglyphCalibrator.Result?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    content
                }
                .padding(Spacing.lg)
                .readableContentWidth()
            }
            .screenBackground()
            .navigationTitle("Glasses setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onFinish(false); dismiss() }
                }
            }
            .onAppear(perform: prepare)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ProgressView(value: Double(step.rawValue + 1) / Double(Step.allCases.count))
                .tint(.brandPrimary)
            Text(step.title).font(TypeScale.headline(rounded: theme.usesRoundedFont))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .glassesOn: glassesOnStep
        case .colourCheck: colourCheckStep
        case .redLeak: leakStep(channel: .red)
        case .cyanLeak: leakStep(channel: .cyan)
        case .done: doneStep
        }
    }

    // MARK: 1 · Glasses on

    private var glassesOnStep: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("""
                 Put on your red-cyan glasses. The CYAN lens goes over your \
                 \(profile.amblyopicEye == .unknown ? "weaker" : profile.amblyopicEye.displayName.lowercased()).
                 """)
                .font(TypeScale.body(rounded: theme.usesRoundedFont))

            // Stated because the natural assumption is the opposite, and getting
            // it backwards dims the eye that needs the most light.
            AmblyoCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Why cyan on the weaker eye",
                          systemImage: "info.circle")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                    Text("""
                         A red lens blocks more light than a cyan one. Putting red \
                         over the weaker eye would dim the eye that needs the most \
                         to work with.
                         """)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            SafetyBanner(
                level: .info,
                title: "No glasses yet?",
                message: "You can skip this. Everything in the Train list will still work — the two-eye exercises just stay hidden until this is done."
            )

            AmblyoButton(title: "They're on", systemImage: "eyeglasses") {
                step = .colourCheck
            }
            AmblyoButton(title: "Skip for now", style: .tertiary) {
                onFinish(false); dismiss()
            }
        }
    }

    // MARK: 2 · Colour discrimination

    @ViewBuilder
    private var colourCheckStep: some View {
        if colourIndex < colourTrials.count {
            let trial = colourTrials[colourIndex]
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Which side looks red to you? \(colourIndex + 1) of \(colourTrials.count)")
                    .font(TypeScale.body(rounded: theme.usesRoundedFont))
                Text("Answer with the glasses on. Guess if you're not sure.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: Spacing.md) {
                    patchButton(isRed: trial.redIsOnLeft, side: "Left") {
                        answerColour(saidRedOnLeft: true)
                    }
                    patchButton(isRed: !trial.redIsOnLeft, side: "Right") {
                        answerColour(saidRedOnLeft: false)
                    }
                }
            }
        }
    }

    private func patchButton(isRed: Bool, side: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isRed
                          ? Color(red: 0.85, green: 0.12, blue: 0.12)
                          : Color(red: 0.10, green: 0.78, blue: 0.80))
                    .frame(height: 120)
                Text(side).font(TypeScale.callout(rounded: theme.usesRoundedFont))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(side) patch")
    }

    // MARK: 3 & 4 · Crosstalk null probes

    private func leakStep(channel: AnaglyphCalibrator.LeakProbe.Channel) -> some View {
        let leak = channel == .red ? redLeak : cyanLeak
        let probe = AnaglyphCalibrator.LeakProbe(channel: channel, leak: leak)
        let patch = probe.patch()

        return VStack(alignment: .leading, spacing: Spacing.md) {
            Text("""
                 Close your \(channel == .red ? "cyan" : "red")-lens eye. Move the \
                 slider until the square below disappears into the background.
                 """)
                .font(TypeScale.body(rounded: theme.usesRoundedFont))

            // A NULL task, not a threshold task. "Make it vanish" is far easier
            // to judge reliably than "tell me when you can just about see it",
            // and the calibration is only as good as this judgement.
            Text("It won't go perfectly invisible — just get it as faint as you can.")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            ZStack {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color(white: AnaglyphCompositor.layerMidpoint))
                    .frame(height: 200)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: patch.red, green: patch.green, blue: patch.blue))
                    .frame(width: 110, height: 110)
            }
            .accessibilityHidden(true)

            Slider(
                value: channel == .red ? $redLeak : $cyanLeak,
                in: AnaglyphCalibrator.plausibleLeak,
                step: 0.005
            )
            .tint(.brandPrimary)
            .accessibilityLabel("Adjustment")
            .accessibilityValue(String(format: "%.0f percent", leak * 100))

            AmblyoButton(title: "That's as faint as it gets") {
                if channel == .red { step = .cyanLeak } else { finish() }
            }
        }
    }

    // MARK: 5 · Done

    @ViewBuilder
    private var doneStep: some View {
        if let result {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if result.isUsable {
                    AmblyoCard(accent: .success) {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Label("Ready", systemImage: "checkmark.circle.fill")
                                .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                                .foregroundStyle(Color.success)
                            Text(separationSentence(result))
                                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Text("The two-eye exercises are now available in Train.")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                } else if !result.colorVisionOK {
                    // Framed as routing, never as a deficiency. This is someone's
                    // eyes, and the useful message is what they CAN do.
                    SafetyBanner(
                        level: .info,
                        title: "We'll stick to the single-eye exercises",
                        message: "Red and cyan didn't separate clearly for you, so the two-eye exercises wouldn't work properly. Everything else in Train is unaffected, and it's worth mentioning to your eye doctor."
                    )
                } else {
                    SafetyBanner(
                        level: .caution,
                        title: "These glasses leak too much light",
                        message: "The lenses aren't separating the two images well enough to train with. A different pair usually fixes it — try again once you have one."
                    )
                }

                AmblyoButton(title: "Done") {
                    onFinish(result.isUsable); dismiss()
                }
                if !result.isUsable {
                    AmblyoButton(title: "Try again", style: .tertiary) { reset() }
                }
            }
        }
    }

    private func separationSentence(_ result: AnaglyphCalibrator.Result) -> String {
        let cross = result.crossModulation(
            amblyopicFilter: profile.calibration?.anaglyphFilter ?? .cyan,
            fellowEyeContrast: profile.calibration?.fellowEyeContrast ?? 0.2)
        return String(format: "Each eye now sees its own image with about %.1f%% bleed-through.",
                      cross * 100)
    }

    // MARK: Flow

    private func prepare() {
        guard colourTrials.isEmpty else { return }
        colourTrials = (0..<AnaglyphCalibrator.discriminationTrialCount).map { _ in
            AnaglyphCalibrator.DiscriminationTrial.make(generator: &generator)
        }
    }

    private func answerColour(saidRedOnLeft: Bool) {
        guard colourIndex < colourTrials.count else { return }
        if colourTrials[colourIndex].isCorrect(saidRedOnLeft: saidRedOnLeft) {
            colourCorrect += 1
        }
        colourIndex += 1

        if colourIndex >= colourTrials.count {
            // Fail fast: no point measuring filters that will never be used.
            if AnaglyphCalibrator.passed(correct: colourCorrect) {
                step = .redLeak
            } else {
                finish()
            }
        }
    }

    private func finish() {
        let outcome = AnaglyphCalibrator.Result(
            redLeakIntoCyan: redLeak,
            cyanLeakIntoRed: cyanLeak,
            colorVisionOK: AnaglyphCalibrator.passed(correct: colourCorrect))

        let calibration = profile.calibration ?? CalibrationProfile()
        AnaglyphCalibrator.apply(outcome, to: calibration)
        if profile.calibration == nil {
            try? ProfileRepository(context: context)
                .setCalibration(calibration, for: profile)
        } else {
            try? context.save()
        }

        result = outcome
        step = .done
    }

    private func reset() {
        colourIndex = 0
        colourCorrect = 0
        colourTrials = []
        redLeak = 0.08
        cyanLeak = 0.08
        result = nil
        prepare()
        step = .glassesOn
    }
}
