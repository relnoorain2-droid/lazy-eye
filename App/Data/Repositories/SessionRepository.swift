//
//  SessionRepository.swift
//
//  Session and trial persistence.
//
//  PERFORMANCE NOTE: a session generates 150-400 trials. Do NOT save after every
//  trial — batch them and save on session end or every 25 trials. Saving per
//  trial on an iPad 7th gen costs frames, and a dropped frame invalidates the
//  trial (docs/04-ARCHITECTURE.md section 5). The irony would be expensive.
//

import Foundation
import SwiftData

@MainActor
struct SessionRepository {

    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    /// Trials buffered before a save is forced.
    static let saveBatchSize = 25

    // MARK: Lifecycle

    @discardableResult
    func begin(profile: Profile, track: Track, plannedSeconds: Int,
               fellowEyeContrast: Double? = nil) throws -> SessionRecord {
        let session = SessionRecord(
            profile: profile,
            startedAt: .now,
            plannedSeconds: plannedSeconds,
            track: track,
            fellowEyeContrast: fellowEyeContrast
        )
        context.insert(session)
        try context.save()
        return session
    }

    func append(_ trial: TrialRecord, to session: SessionRecord) throws {
        trial.session = session
        context.insert(trial)
        if session.trials.count % Self.saveBatchSize == 0 {
            try context.save()
        }
    }

    func end(_ session: SessionRecord, reason: EndReason, actualSeconds: Int,
             breakCount: Int = 0) throws {
        session.endedAt = .now
        session.endedReason = reason
        session.actualSeconds = actualSeconds
        session.breakCount = breakCount
        try context.save()
    }

    // MARK: Reads

    func sessions(for profile: Profile, since: Date? = nil, limit: Int? = nil) throws -> [SessionRecord] {
        let profileID = profile.id
        var descriptor: FetchDescriptor<SessionRecord>
        if let since {
            descriptor = FetchDescriptor<SessionRecord>(
                predicate: #Predicate { $0.profile?.id == profileID && $0.startedAt >= since },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<SessionRecord>(
                predicate: #Predicate { $0.profile?.id == profileID },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
        }
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func mostRecent(for profile: Profile) throws -> SessionRecord? {
        try sessions(for: profile, limit: 1).first
    }

    /// Total training seconds today. Feeds the daily cap.
    func secondsToday(for profile: Profile, now: Date = .now) throws -> Int {
        let startOfDay = Calendar.current.startOfDay(for: now)
        return try sessions(for: profile, since: startOfDay)
            .reduce(0) { $0 + $1.actualSeconds }
    }

    /// True when the age-group daily cap has been reached.
    /// docs/04-ARCHITECTURE.md section 6.
    func hasReachedDailyCap(for profile: Profile, now: Date = .now) throws -> Bool {
        try secondsToday(for: profile, now: now) >= profile.ageGroup.dailyCapSeconds
    }

    /// Trials for one exercise, newest first. Input to threshold estimation.
    func trials(for profile: Profile, exerciseID: String, limit: Int = 200) throws -> [TrialRecord] {
        let profileID = profile.id
        var descriptor = FetchDescriptor<TrialRecord>(
            predicate: #Predicate {
                $0.exerciseID == exerciseID
                    && $0.session?.profile?.id == profileID
                    && !$0.discarded
            },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Distinct days with at least one adherence-qualifying session, newest first.
    func activeDays(for profile: Profile, since: Date) throws -> [Date] {
        let days = try sessions(for: profile, since: since)
            .filter(\.countsTowardAdherence)
            .map(\.day)
        return Array(Set(days)).sorted(by: >)
    }

    /// Consecutive-day streak ending today or yesterday. Missing *today* does not
    /// break the streak until the day is over — breaking someone's streak at
    /// 00:01 is hostile, and this app is used by children.
    func currentStreak(for profile: Profile, now: Date = .now) throws -> Int {
        let calendar = Calendar.current
        let lookback = calendar.date(byAdding: .day, value: -400, to: now) ?? now
        let days = Set(try activeDays(for: profile, since: lookback))
        guard !days.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)
        var cursor = days.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today)!

        var streak = 0
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
