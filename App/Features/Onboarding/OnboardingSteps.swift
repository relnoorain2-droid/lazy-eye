//
//  OnboardingSteps.swift
//
//  The five non-calibration steps. Calibration lives in its own file because it
//  carries real measurement logic; these are forms and copy.
//
//  TONE RULES FOR EVERY WORD IN THIS FILE (docs/08-COMPLIANCE-LEGAL.md section 3)
//    - never "treat", "cure", "correct", "fix", "improve your vision"
//    - never a number that sounds like an outcome ("40% better in 6 weeks")
//    - training language only: practise, train, exercise, session
//    - cite the METHOD the research used, never borrow its OUTCOME
//  scripts/lint_claims.py fails CI on the banned words, so a slip here breaks
//  the build rather than reaching review.
//

import SwiftUI

// MARK: - Welcome

struct WelcomeStepView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: "eye")
                .font(.system(size: 56))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            Text("Daily practice for a lazy eye")
                .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))

            Text("""
                 Amblyopia - a lazy eye - happens when the brain learns to favour \
                 one eye and stops using the other properly. The exercises here \
                 ask the weaker eye to do the work, and ask both eyes to work \
                 together.
                 """)
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                bullet("figure.walk", "A short daily session",
                       "Ten to twenty-five minutes, planned for you and capped for safety.")
                bullet("ruler", "Sized to your screen",
                       "Two quick measurements make every exercise the same difficulty on any device.")
                bullet("speaker.slash", "Silent unless you ask",
                       "Music, effects and voice all start switched off.")
                bullet("text.book.closed", "Sources you can check",
                       "Every exercise says what kind of research it came from, and what that research did not test.")
            }
            .padding(.top, Spacing.sm)
        }
    }

    private func bullet(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                Text(body)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Disclaimer

struct DisclaimerStepView: View {
    @Binding var draft: OnboardingDraft

    @State private var showFullDocument = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SafetyBanner(
                level: .caution,
                title: "This is a training app, not a medical device",
                // "diagnose" is banned as a CAPABILITY claim. Here it appears in
                // the negative, in the disclaimer that exists to deny exactly that
                // capability. Removing the word would weaken the disclaimer the
                // linter is protecting. docs/08-COMPLIANCE-LEGAL.md section 3.
                // claims-lint:disable-next-line
                message: "It does not diagnose anything and it does not replace care from an eye doctor."
            )

            VStack(alignment: .leading, spacing: Spacing.md) {
                point("Keep your appointments",
                      "Amblyopia is managed by an optometrist or ophthalmologist. Nothing here changes that, and this app is not a substitute for the plan they gave you.")
                point("Keep wearing what you were prescribed",
                      "If you have glasses or a patch, carry on exactly as instructed. Do not change or stop anything because of this app.")
                point("Stop if something hurts",
                      "Headache, eye pain, double vision that does not settle, or nausea means stop the session and speak to your eye doctor.")
                point("Under 18? A grown-up sets this up",
                      "Children's amblyopia care is time-sensitive. A parent or carer should be involved and should have spoken to the eye doctor first.")
            }

            Button {
                showFullDocument = true
            } label: {
                Label("Read the full disclaimer", systemImage: "doc.text")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
            }
            .tint(.brandPrimary)

            Toggle(isOn: $draft.hasAcknowledgedDisclaimer) {
                Text("I understand this app is for training and does not replace medical care.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
            }
            .tint(.brandPrimary)
            .padding(Spacing.md)
            .background(Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        }
        .sheet(isPresented: $showFullDocument) {
            NavigationStack {
                LegalDocumentView(document: .medicalDisclaimer)
            }
        }
    }

    private func point(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
            Text(body)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Profile

struct ProfileStepView: View {
    @Binding var draft: OnboardingDraft

    @FocusState private var nameFocused: Bool
    @Environment(\.theme) private var theme

    private var currentYear: Int { Calendar.current.component(.year, from: .now) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {

            field("Who is this for?",
                  hint: "Only stored on this device. Leave it blank if you'd rather not say.") {
                TextField("Name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .font(TypeScale.body(rounded: theme.usesRoundedFont))
            }

            field("Age group",
                  hint: "Sets the session length and the daily limit. Younger eyes get shorter sessions.") {
                Picker("Age group", selection: ageGroupBinding) {
                    ForEach(AgeGroup.allCases, id: \.self) { group in
                        Text(group.displayName).tag(group)
                    }
                }
                .pickerStyle(.segmented)
            }

            field("Which eye is the weaker one?",
                  hint: eyeHint) {
                Picker("Amblyopic eye", selection: $draft.amblyopicEye) {
                    Text("Left").tag(Eye.left)
                    Text("Right").tag(Eye.right)
                    Text("Not sure").tag(Eye.unknown)
                }
                .pickerStyle(.segmented)
            }

            Toggle(isOn: $draft.wearsCorrection) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("I wear glasses or contact lenses")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    Text("Wear them for every session unless your eye doctor said otherwise.")
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .tint(.brandPrimary)

            if draft.isKidsMode {
                SafetyBanner(
                    level: .info,
                    title: "Set up by a grown-up",
                    message: "Settings and purchases will ask a quick maths question first, so a child can practise without changing anything."
                )
            }
        }
        .onTapGesture { nameFocused = false }
    }

    /// "Not sure" is a first-class answer, not a failure state. Being told to go
    /// away and find out is where people abandon setup - so the app trains both
    /// eyes evenly until they know, and says so plainly.
    private var eyeHint: String {
        switch draft.amblyopicEye {
        case .unknown:
            "That's fine. Sessions will train both eyes evenly until you know. Your eye doctor can tell you, and you can change this any time in Settings."
        case .left, .right:
            "Exercises will give the \(draft.amblyopicEye.displayName.lowercased()) the harder half of the work."
        }
    }

    /// The draft stores age either as a birth year or as an explicit group. This
    /// screen only offers the group, so the binding writes the explicit side and
    /// clears any inferred year to avoid two sources of truth.
    private var ageGroupBinding: Binding<AgeGroup> {
        Binding(
            get: { draft.ageGroup },
            set: { newValue in
                draft.explicitAgeGroup = newValue
                draft.birthYear = nil
            }
        )
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String, hint: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(TypeScale.headline(rounded: theme.usesRoundedFont))
            content()
            Text(hint)
                .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sound

struct SoundStepView: View {
    @Binding var draft: OnboardingDraft
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("You choose the sound")
                .font(TypeScale.title(rounded: theme.usesRoundedFont))

            // Rewritten when feedback sound started defaulting on. The heading
            // said "Everything is off" while the toggle below it was on, which
            // is worse than either state on its own: a user cannot tell whether
            // the app is lying or broken.
            Text("""
                 The most common complaint about apps like this one is sound you \
                 can't switch off. So these are three separate switches, your \
                 phone's silent switch always wins, and nothing here needs sound \
                 to work. A quiet tick when you answer is on to start with; \
                 music and the spoken guide are not.
                 """)
                .font(TypeScale.body(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)

            VStack(spacing: 0) {
                channel($draft.soundEffectsEnabled, "speaker.wave.2", "Sound effects",
                        "A quiet tick when you answer.")
                Divider().overlay(Color.separatorLine).padding(.leading, 52)
                channel($draft.musicEnabled, "music.note", "Background music",
                        "Calm loops during a session.")
                Divider().overlay(Color.separatorLine).padding(.leading, 52)
                channel($draft.voiceGuidanceEnabled, "waveform", "Voice guidance",
                        "Spoken instructions at the start of each exercise.")
            }
            .background(Color.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.separatorLine, lineWidth: 1)
            )

            Label {
                Text("The silent switch always wins, and there's a mute button inside every session.")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            } icon: {
                Image(systemName: "bell.slash")
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func channel(_ isOn: Binding<Bool>, _ icon: String,
                         _ title: String, _ subtitle: String) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    Text(subtitle)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .tint(.brandPrimary)
        .padding(Spacing.md)
    }
}

// MARK: - Ready

struct ReadyStepView: View {
    let draft: OnboardingDraft
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.success)
                .accessibilityHidden(true)

            Text("You're set up")
                .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))

            AmblyoCard {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    row("Name", draft.resolvedName)
                    row("Age group", draft.ageGroup.displayName)
                    row("Weaker eye", draft.amblyopicEye.displayName)
                    row("Session length", "\(draft.ageGroup.defaultSessionSeconds / 60) minutes")
                    row("Daily limit", "\(draft.ageGroup.dailyCapSeconds / 60) minutes")
                    row("Viewing distance", "\(Int(draft.viewingDistanceCM)) cm")
                }
            }

            Text("""
                 Consistency matters more than length. A short session most days \
                 beats a long one now and then. You can change any of this in \
                 Settings.
                 """)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}
