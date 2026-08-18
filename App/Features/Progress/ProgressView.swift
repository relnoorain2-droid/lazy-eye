//
//  ProgressView.swift
//
//  The Progress tab.
//
//  THE HARD RULE THIS SCREEN EXISTS TO ENFORCE:
//  every number carries "training score, not a clinical measurement", and no
//  direction is stated unless the confidence interval supports it. When the
//  analyser says `noClearChange`, this screen says so plainly rather than
//  drawing an encouraging line. That is the difference between a measurement and
//  a motivational graphic, and it is what App Review guideline 1.4.1 is looking
//  for in a health-adjacent app.
//
//  docs/06-AI-ENGINE-SPEC.md section 3, docs/08-COMPLIANCE-LEGAL.md section 2.
//

import SwiftUI
import SwiftData
import Charts

@MainActor
struct ProgressDashboardView: View {

    @Query(filter: #Predicate<Profile> { $0.isActive }) private var activeProfiles: [Profile]
    @Environment(\.modelContext) private var context
    @Environment(\.theme) private var theme

    @State private var analysis: ProgressAnalysis?
    @State private var series: [String: [(day: Date, value: Double)]] = [:]
    @State private var loadError: String?

    /// The last few sessions, newest first.
    ///
    /// WHY THIS EXISTS SEPARATELY FROM THE TRENDS.
    /// Everything else on this screen is inferential and refuses to speak early
    /// — a trend needs eight practice days before it will claim a direction,
    /// which is correct and which means that after a user's FIRST session this
    /// screen said, in effect, nothing at all. Refusing to over-claim is not the
    /// same as refusing to acknowledge, and a person who has just finished five
    /// minutes of work is owed a record that it happened.
    ///
    /// This list makes no claim about vision. It reports what was done.
    @State private var recent: [SessionRecord] = []

    private var profile: Profile? { activeProfiles.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let loadError {
                    SafetyBanner(level: .caution, title: "Couldn't read your history",
                                 message: loadError)
                } else if let analysis, let profile {
                    content(analysis, profile: profile)
                } else if profile == nil {
                    // A SPINNER HERE WAS A LIE. With no profile there is nothing
                    // being loaded and nothing that will ever arrive, so the old
                    // code span forever and looked like a hang — which is what
                    // it was, from the user's side. An empty state has to say
                    // which empty it is.
                    ContentUnavailableView(
                        "Nothing to chart yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Finish setup and complete a session, and your history appears here."))
                        .padding(.top, Spacing.xl)
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Spacing.xxl)
                }
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
        .navigationTitle("Progress")
        .task(id: profile?.id) { reload() }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ analysis: ProgressAnalysis, profile: Profile) -> some View {

        // The referral card comes FIRST and cannot be dismissed. Everything
        // below it is secondary to the message that this needs a professional.
        if analysis.shouldEscalateToProfessional {
            EscalationCard(blocks: analysis.blocksWithoutImprovement)
        }

        HStack(spacing: Spacing.md) {
            StreakRing(days: analysis.currentStreak)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                MetricTile(title: "Practice",
                           value: "\(analysis.totalMinutes)",
                           unit: "min total",
                           needsScoreQualifier: false)
            }
        }

        MetricTile(title: "Last 4 weeks",
                   value: "\(Int((analysis.adherence28d * 100).rounded()))",
                   unit: "% of days",
                   needsScoreQualifier: false)

        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Recent sessions")
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                ForEach(recent, id: \.persistentModelID) { session in
                    RecentSessionRow(session: session)
                }
            }
        }

        if analysis.isTooEarlyToTell {
            AmblyoCard {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Too early to show a trend")
                        .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                    Text("""
                         A reliable trend needs at least \(Trend.minimumPointsForAClaim) \
                         sessions of an exercise. Keep going and the chart will appear \
                         here — an early line would be guesswork.
                         """)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }

        ForEach(analysis.thresholdTrends.keys.sorted(), id: \.self) { exerciseID in
            if let trend = analysis.thresholdTrends[exerciseID],
               let descriptor = ExerciseRegistry.descriptor(for: exerciseID) {
                TrendCard(descriptor: descriptor,
                          trend: trend,
                          points: series[exerciseID] ?? [])
            }
        }

        Text(AssessmentTest.scoreQualifier)
            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
            .foregroundStyle(Color.textSecondary)
            .padding(.top, Spacing.sm)
    }

    // MARK: Recent activity

    /// One completed session, described in the terms the user experienced it in:
    /// what, when, how long, how many answers.
    ///
    /// Deliberately says nothing about whether it went well. Accuracy on a
    /// staircase is meaningless as a score — it converges on about 79% for
    /// everybody, by construction, so showing "you got 79%" would invite a
    /// comparison that means nothing and would look like a bad mark to a child.
    struct RecentSessionRow: View {
        let session: SessionRecord
        @Environment(\.theme) private var theme

        private var trialCount: Int { session.trials.filter { !$0.discarded }.count }

        private var when: String {
            let calendar = Calendar.current
            if calendar.isDateInToday(session.startedAt) { return "Today" }
            if calendar.isDateInYesterday(session.startedAt) { return "Yesterday" }
            return session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        }

        private var stoppedEarly: Bool {
            session.endedReason == .fatigue || session.endedReason == .userStopped
        }

        var body: some View {
            AmblyoCard {
                HStack(spacing: Spacing.md) {
                    Image(systemName: session.track.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                        .frame(width: 34, height: 34)
                        .background(Color.brandPrimary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(when)
                            .font(TypeScale.callout(rounded: theme.usesRoundedFont).weight(.semibold))
                        Text("\(session.actualSeconds / 60) min · \(trialCount) answers")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }

                    Spacer(minLength: 0)

                    // Said plainly rather than hidden. Stopping early is an
                    // allowed, encouraged outcome in this app, and a record that
                    // quietly omitted it would misrepresent the history.
                    if stoppedEarly {
                        Text("Stopped early")
                            .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Loading

    private func reload() {
        guard let profile else { return }
        do {
            let repository = SessionRepository(context: context)
            let sessions = try repository.sessions(for: profile)
            recent = Array(sessions.prefix(6))

            var observations: [ProgressAnalyzer.Observation] = []
            var built: [String: [(day: Date, value: Double)]] = [:]

            for descriptor in ExerciseRegistry.all {
                let trials = try repository.trials(for: profile,
                                                   exerciseID: descriptor.id,
                                                   limit: 2_000)
                // One threshold per DAY, not per trial: several trials in a
                // session are not independent observations of ability, and
                // treating them as such would make the interval far too tight.
                let byDay = Dictionary(grouping: trials.filter { !$0.discarded }) {
                    Calendar.current.startOfDay(for: $0.timestamp)
                }
                let lowerIsBetter = descriptor.staircase.polarity == .lowerIsHarder

                for (day, dayTrials) in byDay where dayTrials.count >= 8 {
                    let values = dayTrials.map(\.difficultyValue).sorted()
                    // Median rather than mean: a staircase spends most of its
                    // time near threshold but visits extremes during the coarse
                    // descent, and the mean is dragged by them.
                    let median = values[values.count / 2]
                    observations.append(.init(exerciseID: descriptor.id, day: day,
                                              threshold: median,
                                              lowerIsBetter: lowerIsBetter))
                    built[descriptor.id, default: []].append((day, median))
                }
            }
            for key in built.keys {
                built[key]?.sort { $0.day < $1.day }
            }

            let totalMinutes = sessions.reduce(0) { $0 + $1.actualSeconds } / 60
            analysis = ProgressAnalyzer().analyse(
                observations: observations,
                sessionDays: sessions.map(\.startedAt),
                totalMinutes: totalMinutes)
            series = built
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Trend card

private struct TrendCard: View {
    let descriptor: ExerciseDescriptor
    let trend: Trend
    let points: [(day: Date, value: Double)]

    @Environment(\.theme) private var theme

    var body: some View {
        AmblyoCard(accent: tint) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text(descriptor.title)
                        .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                    Spacer()
                    Text(trend.direction.userFacing)
                        .font(TypeScale.caption(rounded: theme.usesRoundedFont).weight(.semibold))
                        .foregroundStyle(tint)
                }

                if points.count >= 2 {
                    // Indexed rather than iterating the tuples directly:
                    // destructuring a tuple element inside a ForEach closure is
                    // legal Swift but leans on inference I would rather not bet
                    // a CI round on.
                    Chart {
                        ForEach(points.indices, id: \.self) { index in
                            LineMark(x: .value("Day", points[index].day),
                                     y: .value(descriptor.staircase.dimensionName,
                                               points[index].value))
                                .foregroundStyle(Color.brandPrimary)
                            PointMark(x: .value("Day", points[index].day),
                                      y: .value(descriptor.staircase.dimensionName,
                                                points[index].value))
                                .foregroundStyle(Color.brandPrimary.opacity(0.5))
                        }
                    }
                    .chartYAxis { AxisMarks(position: .leading) }
                    .frame(height: 120)
                    .accessibilityLabel("\(descriptor.title) over time")
                    .accessibilityValue(trend.direction.userFacing)
                }

                Text(explanation)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)

                Text(AssessmentTest.scoreQualifier)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private var tint: Color {
        switch trend.direction {
        case .improving: .success
        case .worsening: .caution
        case .noClearChange: .textSecondary
        }
    }

    /// Says what the data supports and nothing more. In particular the
    /// `noClearChange` wording never implies failure — with this many sessions,
    /// no detectable change is the expected result, not a bad one.
    private var explanation: String {
        switch trend.direction {
        case .improving:
            "Across \(trend.pointCount) sessions, your \(descriptor.staircase.dimensionName) has moved in the right direction by more than day-to-day variation."
        case .worsening:
            "Across \(trend.pointCount) sessions, your \(descriptor.staircase.dimensionName) has moved the other way. Worth mentioning at your next eye appointment."
        case .noClearChange:
            "\(trend.pointCount) sessions so far — not enough separation from normal day-to-day variation to call a direction yet."
        }
    }
}

// MARK: - Escalation

/// Non-dismissible by design. docs/04-ARCHITECTURE.md section 6.
private struct EscalationCard: View {
    let blocks: Int
    @Environment(\.theme) private var theme

    var body: some View {
        AmblyoCard(accent: .critical) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Worth booking an eye appointment",
                      systemImage: "exclamationmark.circle.fill")
                    .font(TypeScale.headline(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.critical)

                Text("""
                     Your scores have held steady for about \(blocks * 4) weeks. That \
                     can happen for lots of reasons, and it is worth an eye doctor \
                     looking at it rather than carrying on unchanged.
                     """)
                    .font(TypeScale.callout(rounded: theme.usesRoundedFont))

                Text("""
                     Amblyopia is time-sensitive, particularly in children. Please \
                     don't wait for this app to change on its own.
                     """)
                    .font(TypeScale.caption(rounded: theme.usesRoundedFont))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
