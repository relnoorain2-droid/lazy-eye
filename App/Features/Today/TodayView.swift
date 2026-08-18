//
//  TodayView.swift
//
//  The home screen, and the only screen most people will look at.
//
//  WHAT IT IS FOR
//  One question: "what should I do right now?" — answered in one tap. Everything
//  else on this screen is subordinate to that. The exercise library lives in
//  Train; this is the plan.
//
//  WHY THE PLAN IS SHOWN BEFORE IT IS STARTED
//  A plan the app silently chose and immediately ran would be indistinguishable
//  from a random exercise picker. Showing the three items, their lengths and the
//  one-line reason they were chosen is what makes it a plan the user can
//  disagree with — and they can, by starting anything they like from Train.
//
//  WHAT THIS SCREEN MUST NEVER DO
//  Congratulate a streak in a way that pressures someone into training when
//  their eyes hurt, or imply that today's practice will improve their vision.
//  The copy here is checked by the claims linter for exactly that reason.
//
//  docs/02-PRD.md section 3, docs/06-AI-ENGINE-SPEC.md section 3.
//

import SwiftUI
import SwiftData

@MainActor
struct TodayView: View {

    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]

    @Environment(\.modelContext) private var context
    @Environment(SubscriptionManager.self) private var subscriptions
    @Environment(SettingsStore.self) private var settings
    @Environment(\.theme) private var theme

    @State private var plan: SessionPlan?
    @State private var secondsUsedToday = 0
    @State private var streak = 0
    @State private var adherence7d: Double = 0
    @State private var isAssessmentDue = false
    @State private var loadError: String?
    @State private var startError: String?

    /// Same ownership rule as Train: the runner is built ONCE, when Start is
    /// tapped, and held here. Building it inside the cover's content closure
    /// makes a brand-new runner on every trial, which silently resets the
    /// session after the first answer.
    @State private var runner: SessionRunner?
    @State private var launching: ExerciseDescriptor?
    @State private var showingAssessment = false

    private var profile: Profile? { activeProfiles.first }

    var body: some View {
        Group {
            if let profile {
                content(for: profile)
            } else {
                ContentUnavailableView(
                    "No profile yet",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Finish setup to start training."))
            }
        }
        .navigationTitle("Today")
        .task(id: profile?.id) { reload() }
        .fullScreenCover(item: $launching) { descriptor in
            sessionScreen(for: descriptor)
        }
        .sheet(isPresented: $showingAssessment) {
            if let profile {
                AssessmentView(profile: profile) { reload() }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for profile: Profile) -> some View {
        let cap = SessionCap(ageGroup: profile.ageGroup, secondsUsedToday: secondsUsedToday)

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {

                if let loadError {
                    SafetyBanner(level: .caution, title: "Couldn't read your history",
                                 message: loadError)
                }
                if let startError {
                    SafetyBanner(level: .caution, title: "Couldn't start", message: startError)
                }

                hero(profile)

                if !profile.isSetUp {
                    setupCard(profile)
                } else if cap.isDailyCapReached {
                    doneForTodayCard(profile, cap: cap)
                } else if let plan, !plan.isEmpty {
                    planCard(plan, profile: profile, cap: cap)
                } else if plan != nil {
                    nothingToDoCard
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, Spacing.xl)
                }

                statsRow

                // Not a nag. One line, and only when an assessment is actually
                // due, because a permanent reminder is just furniture.
                if isAssessmentDue {
                    assessmentCard
                }

                Text(AssessmentTest.scoreQualifier)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.sm)
            }
            .padding()
            .readableContentWidth()
            // Clears the floating tab bar. On iOS 26 the tab bar hovers over
            // the scroll view rather than sitting below it, so the last card
            // ends up half-hidden behind it — visible in the first device
            // screenshots. The safe area does not cover this because the bar is
            // an overlay, not a bottom inset.
            .padding(.bottom, 72)
        }
        .screenBackground()
    }

    /// The header, rebuilt after the first device test called this screen "like
    /// a Word document".
    ///
    /// It was: a small grey word, a name in large type, then a column of white
    /// cards containing sentences. Every element the same weight, no colour, no
    /// focal point — accurate information arranged as a memo. A person opening
    /// a training app wants to know two things in the first second, and neither
    /// of them is a paragraph: **am I on track**, and **what do I press**.
    ///
    /// So the header now carries a ring for today's minutes and a streak, on a
    /// brand-tinted panel that anchors the screen. Not decoration for its own
    /// sake — a ring answers "how much is left today" faster than "12 min" in
    /// body text, which is the entire reason rings are on watches.
    private func hero(_ profile: Profile) -> some View {
        // The target is the profile's PLANNED session length, not the daily cap
        // and not what the cap will still allow. The cap is a safety ceiling —
        // ringing it as a goal would tell the user to aim at the maximum amount
        // of screen time the app permits, which is the opposite of its purpose.
        // And using the remaining allowance would shrink the target as the day
        // went on, so the ring could go backwards while the user did nothing.
        let target = max(60, profile.plannedSessionSeconds)
        let done = min(secondsUsedToday, target)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Radius.card + 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.brandPrimary.opacity(0.20),
                                 Color.brandSecondary.opacity(0.12)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.greetingWord(at: .now))
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                    Text(profile.name)
                        .font(TypeScale.displayLarge(rounded: theme.usesRoundedFont))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if streak > 0 {
                        Label("\(streak) day\(streak == 1 ? "" : "s") in a row",
                              systemImage: "flame.fill")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont).weight(.semibold))
                            .foregroundStyle(Color.brandPrimary)
                            .padding(.top, Spacing.xs)
                    } else {
                        // No streak yet is not a failure and is not shown as an
                        // empty flame or a zero. A zero on a counter reads as
                        // losing at something you have not started.
                        Text("Today is a good day to start")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.top, Spacing.xs)
                    }
                }

                Spacer(minLength: 0)

                TodayRing(done: done, target: target)
            }
            .padding(Spacing.lg)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Self.greetingWord(at: .now)) \(profile.name). \(done / 60) of \(target / 60) minutes done today.")
    }

    /// Today's minutes, as a ring.
    ///
    /// Fills, and then STOPS at full. It does not keep going, turn gold, or
    /// invite a second session — the daily cap exists because more screen time
    /// is not more benefit for amblyopia training, and a ring that rewarded
    /// overshooting would be arguing with the cap the app enforces two lines
    /// away.
    struct TodayRing: View {
        let done: Int
        let target: Int

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fraction: Double {
            guard target > 0 else { return 0 }
            return min(1, Double(done) / Double(target))
        }

        var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.surfaceRaised, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(fraction >= 1 ? Color.success : Color.brandPrimary,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : Motion.gentle, value: fraction)

                if fraction >= 1 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.success)
                } else {
                    VStack(spacing: 0) {
                        Text("\(done / 60)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("of \(target / 60) min")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .frame(width: 92, height: 92)
            .accessibilityHidden(true)
        }
    }

    /// Time-of-day greeting. Static and testable rather than inline, because
    /// "Good morning" at 3am is the kind of small wrongness people notice.
    static func greetingWord(at date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 5..<12:  "Good morning"
        case 12..<18: "Good afternoon"
        case 18..<23: "Good evening"
        default:      "Late one"
        }
    }

    // MARK: Cards

    private func setupCard(_ profile: Profile) -> some View {
        AmblyoCard(accent: Color.caution) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Finish setting up")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Text(Self.setupMessage(for: profile))
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// Names the FIRST missing thing rather than listing all three. A checklist
    /// of everything you have not done is discouraging; one next step is not.
    static func setupMessage(for profile: Profile) -> String {
        if profile.amblyopicEye == .unknown {
            return "Tell us which eye is weaker in Profile, so exercises train the right one. If you're not sure, choose \"not sure\" — the app will train both."
        }
        if !profile.preferences.hasAcknowledgedDisclaimer {
            return "Read the short note about what this app is and isn't, in Profile."
        }
        return "Measure your screen in Profile so the exercises are the right physical size. It takes a minute and everything below depends on it."
    }

    private func planCard(_ plan: SessionPlan, profile: Profile, cap: SessionCap) -> some View {
        AmblyoCard(accent: Color.brandPrimary) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Today's session")
                        .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                    Spacer()
                    Text("\(max(1, plan.totalSeconds / 60)) min")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }

                ForEach(Array(plan.items.enumerated()), id: \.element.exerciseID) { index, item in
                    if let descriptor = ExerciseRegistry.descriptor(for: item.exerciseID) {
                        planRow(index: index, descriptor: descriptor, seconds: item.seconds)
                    }
                }

                // Why these, in one sentence. Never a claim about outcomes.
                Text(plan.rationale)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                if let first = plan.items.first,
                   let descriptor = ExerciseRegistry.descriptor(for: first.exerciseID) {
                    AmblyoButton(title: "Start", systemImage: "play.fill") {
                        start(descriptor, profile: profile, cap: cap)
                    }
                }
            }
        }
    }

    private func planRow(index: Int, descriptor: ExerciseDescriptor,
                         seconds: Int) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text("\(index + 1)")
                .font(TypeScale.caption(rounded: theme.usesRoundedFont).weight(.bold))
                .frame(width: 22, height: 22)
                .background(Color.brandPrimary.opacity(0.15))
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                Text("\(descriptor.track.displayName) · \(max(1, seconds / 60)) min")
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            EvidenceBadge(tier: descriptor.evidenceTier, compact: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func doneForTodayCard(_ profile: Profile, cap: SessionCap) -> some View {
        AmblyoCard(accent: Color.success) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("That's today's practice done")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Text(cap.isOverridable
                     ? "A grown-up can allow more, but a short daily session works better than a long one."
                     : "Come back tomorrow. Little and often is what makes this work.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var nothingToDoCard: some View {
        AmblyoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Nothing scheduled")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Text("Pick anything from Train — the plan will pick up from what you do.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            StreakRing(days: streak)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MetricTile(title: "Last 7 days",
                           value: "\(Int((adherence7d * 100).rounded()))",
                           unit: "% of days",
                           needsScoreQualifier: false)
                MetricTile(title: "Today",
                           value: "\(secondsUsedToday / 60)",
                           unit: "min",
                           needsScoreQualifier: false)
            }
        }
    }

    private var assessmentCard: some View {
        AmblyoCard(accent: Color.brandPrimary) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Check-in available")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                Text("It's been four weeks since your last check-in. About \(AssessmentBattery.estimatedSeconds / 60) minutes of measurements — this is what the Progress screen compares over time.")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
                AmblyoButton(title: "Start check-in", systemImage: "checklist",
                             style: .secondary) { showingAssessment = true }
            }
        }
    }

    // MARK: Session

    private func start(_ descriptor: ExerciseDescriptor, profile: Profile, cap: SessionCap) {
        guard let session = SessionRunner(
            descriptor: descriptor,
            profile: profile,
            targetEye: profile.amblyopicEye,
            context: context,
            cap: cap,
            resuming: nil
        ) else {
            startError = "\(descriptor.title) isn't available in this build."
            return
        }
        session.feedback = SessionFeedback(settings: settings)
        startError = nil
        runner = session
        launching = descriptor
    }

    private func endSession() {
        runner?.stop()
        runner = nil
        launching = nil
        reload()
    }

    @ViewBuilder
    private func sessionScreen(for descriptor: ExerciseDescriptor) -> some View {
        if let runner, let profile {
            ExerciseSessionScreen(
                runner: runner,
                descriptor: descriptor,
                calibration: profile.calibration ?? CalibrationProfile(),
                onFinish: endSession)
        } else {
            Color.clear.onAppear { endSession() }
        }
    }

    // MARK: Loading

    private func reload() {
        guard let profile else { return }
        do {
            let sessions = SessionRepository(context: context)
            secondsUsedToday = try sessions.secondsToday(for: profile)
            streak = try sessions.currentStreak(for: profile)
            let progress = ProgressRepository(context: context)
            adherence7d = try progress.adherence(for: profile, days: 7).ratio
            // Read once here rather than from a computed property in `body`,
            // which would hit the store on every single render.
            isAssessmentDue = try progress.isAssessmentDue(for: profile)

            let descriptors = ExerciseRegistry.available(
                for: profile,
                isPro: subscriptions.status.isPro,
                canUseAnaglyph: profile.canUseDichopticTrack)

            var histories: [String: SessionPlanBuilder.History] = [:]
            var hardest: [String: Double] = [:]
            for descriptor in descriptors {
                let trials = try sessions.trials(for: profile,
                                                 exerciseID: descriptor.id,
                                                 limit: 2_000)
                    .filter { !$0.discarded }
                // A fatigue ending is the closest thing the store has to the
                // staircase's frustration counter, which is not persisted.
                let fatigue = Set(
                    trials.compactMap { $0.session }
                        .filter { $0.endedReason == .fatigue }
                        .map(\.id)
                ).count
                histories[descriptor.id] = SessionPlanBuilder.History(
                    exerciseID: descriptor.id,
                    trialDays: trials.map(\.timestamp),
                    difficulties: trials.map(\.difficultyValue),
                    fatigueEndings: fatigue)
                // On the STAIRCASE, not the descriptor — the descriptor holds a
                // `StaircaseConfiguration` and that is where the display clamp
                // lives. Same class of mistake as `isPro`, which is on
                // `EntitlementStatus` rather than `SubscriptionManager`.
                hardest[descriptor.id] = descriptor.staircase
                    .resolvedHardestValue(for: profile.calibration)
            }

            let builder = SessionPlanBuilder()
            let states = builder.states(for: descriptors,
                                        histories: histories,
                                        hardestValues: hardest)
            plan = PlanGenerator().plan(
                states: states,
                cap: SessionCap(ageGroup: profile.ageGroup,
                                secondsUsedToday: secondsUsedToday),
                requestedSeconds: profile.plannedSessionSeconds)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            plan = SessionPlan(items: [], totalSeconds: 0, rationale: "")
        }
    }
}
