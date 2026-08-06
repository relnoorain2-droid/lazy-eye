//
//  ProgressRepository.swift
//
//  Assessment history and the derived numbers the Progress screen shows.
//
//  The statistics live in Intelligence/ProgressAnalyzer (Phase 9). This file
//  only fetches and shapes — but the adherence and block maths are here because
//  they are storage questions, not analysis questions.
//
//  docs/06-AI-ENGINE-SPEC.md section 3.
//

import Foundation
import SwiftData

@MainActor
struct ProgressRepository {

    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    /// The programme is organised in 4-week blocks. Two consecutive blocks
    /// without improvement triggers the professional-referral card.
    static let blockLengthDays = 28

    // MARK: Assessments

    func assessments(for profile: Profile, limit: Int? = nil) throws -> [AssessmentResult] {
        let profileID = profile.id
        var descriptor = FetchDescriptor<AssessmentResult>(
            predicate: #Predicate { $0.profile?.id == profileID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func latestAssessment(for profile: Profile) throws -> AssessmentResult? {
        try assessments(for: profile, limit: 1).first
    }

    @discardableResult
    func record(_ result: AssessmentResult, for profile: Profile) throws -> AssessmentResult {
        result.profile = profile
        result.blockIndex = try blockIndex(for: profile, at: result.date)
        context.insert(result)
        try context.save()
        return result
    }

    /// Which 4-week block a date falls in, counted from the profile's first
    /// session (not from account creation — someone may sign up and start later).
    func blockIndex(for profile: Profile, at date: Date = .now) throws -> Int {
        let sessionRepo = SessionRepository(context: context)
        let all = try sessionRepo.sessions(for: profile)
        guard let first = all.last?.startedAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: first, to: date).day ?? 0
        return max(0, days / Self.blockLengthDays)
    }

    /// True when the weekly check-in is due: none yet, or the last one was 7+
    /// days ago.
    func isAssessmentDue(for profile: Profile, now: Date = .now) throws -> Bool {
        guard let latest = try latestAssessment(for: profile) else { return true }
        let days = Calendar.current.dateComponents([.day], from: latest.date, to: now).day ?? 0
        return days >= 7
    }

    // MARK: Adherence
    //
    // The single strongest predictor of outcome in the literature, so it is the
    // headline metric rather than a vanity score.
    // docs/01-RESEARCH-BRIEF.md section 3.

    struct Adherence: Sendable, Equatable {
        let activeDays: Int
        let windowDays: Int
        var ratio: Double { windowDays > 0 ? Double(activeDays) / Double(windowDays) : 0 }
        var percent: Int { Int((ratio * 100).rounded()) }
    }

    func adherence(for profile: Profile, days windowDays: Int, now: Date = .now) throws -> Adherence {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now))!
        let sessionRepo = SessionRepository(context: context)
        let active = try sessionRepo.activeDays(for: profile, since: start).count

        // Never claim a window longer than the profile has existed — a user on
        // day 3 should not be told they have 10% adherence.
        let age = calendar.dateComponents([.day], from: profile.createdAt, to: now).day ?? 0
        let effectiveWindow = max(1, min(windowDays, age + 1))

        return Adherence(activeDays: min(active, effectiveWindow), windowDays: effectiveWindow)
    }

    // MARK: Series for charts

    struct DataPoint: Sendable, Equatable, Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    /// Time series for one assessment metric, oldest first, ready for Swift Charts.
    func series(for profile: Profile, test: AssessmentTest) throws -> [DataPoint] {
        try assessments(for: profile)
            .compactMap { result in
                result.value(for: test).map { DataPoint(date: result.date, value: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// The contrast-rebalance ramp over time — the therapeutic variable, and the
    /// most meaningful line on the Progress screen for dichoptic users.
    func fellowContrastSeries(for profile: Profile) throws -> [DataPoint] {
        let sessionRepo = SessionRepository(context: context)
        return try sessionRepo.sessions(for: profile)
            .filter { $0.track == .dichoptic }
            .compactMap { session in
                session.fellowEyeContrast.map { DataPoint(date: session.startedAt, value: $0) }
            }
            .sorted { $0.date < $1.date }
    }

    /// Daily training minutes for the last N days, including zero days — the
    /// gaps are the informative part.
    func minutesPerDay(for profile: Profile, days: Int, now: Date = .now) throws -> [DataPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)!

        let sessionRepo = SessionRepository(context: context)
        let sessions = try sessionRepo.sessions(for: profile, since: start)

        var totals: [Date: Int] = [:]
        for session in sessions {
            totals[session.day, default: 0] += session.actualSeconds
        }

        return (0..<days).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return DataPoint(date: day, value: Double(totals[day] ?? 0) / 60.0)
        }
    }
}
