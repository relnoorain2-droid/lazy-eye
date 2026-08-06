//
//  RepositoryTests.swift
//
//  Repository invariants: the profile limit, the single-active-profile rule,
//  streak counting, adherence windows, and the daily safety cap.
//
//  All run against an in-memory container — no disk, no ordering between tests.
//

import Testing
import Foundation
import SwiftData
@testable import Amblyo

@MainActor
struct RepositoryTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer.amblyo(inMemory: true)
        return ModelContext(container)
    }

    private func makeProfile(
        in context: ModelContext,
        ageGroup: AgeGroup = .thirteenPlus,
        createdAt: Date = Date(timeIntervalSinceNow: -90 * 86400)
    ) -> Profile {
        let profile = Profile(name: "Test", ageGroup: ageGroup, createdAt: createdAt)
        context.insert(profile)
        return profile
    }

    // MARK: Profile limits

    @Test("Free tier allows one profile")
    func freeTierLimit() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)

        try repo.create(name: "First", ageGroup: .thirteenPlus, isPro: false)

        #expect(throws: ProfileRepository.RepositoryError.self) {
            try repo.create(name: "Second", ageGroup: .thirteenPlus, isPro: false)
        }
    }

    @Test("Pro tier allows five profiles but not six")
    func proTierLimit() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)

        for i in 1...5 {
            try repo.create(name: "Profile \(i)", ageGroup: .thirteenPlus, isPro: true)
        }
        #expect(try repo.count() == 5)

        #expect(throws: ProfileRepository.RepositoryError.self) {
            try repo.create(name: "Sixth", ageGroup: .thirteenPlus, isPro: true)
        }
    }

    @Test("Exactly one profile is active at a time")
    func singleActiveProfile() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)

        let a = try repo.create(name: "A", ageGroup: .thirteenPlus, isPro: true)
        let b = try repo.create(name: "B", ageGroup: .thirteenPlus, isPro: true)

        #expect(try repo.all().filter(\.isActive).count == 1)
        #expect(b.isActive)
        #expect(a.isActive == false)

        try repo.makeActive(a)
        #expect(try repo.active()?.id == a.id)
        #expect(try repo.all().filter(\.isActive).count == 1)
    }

    @Test("The last profile cannot be deleted")
    func cannotDeleteLastProfile() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)
        let only = try repo.create(name: "Only", ageGroup: .thirteenPlus, isPro: false)

        #expect(throws: ProfileRepository.RepositoryError.self) {
            try repo.delete(only)
        }
    }

    @Test("Deleting the active profile promotes another")
    func deletingActivePromotesAnother() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)
        let a = try repo.create(name: "A", ageGroup: .thirteenPlus, isPro: true)
        let b = try repo.create(name: "B", ageGroup: .thirteenPlus, isPro: true)

        try repo.makeActive(b)
        try repo.delete(b)

        #expect(try repo.active()?.id == a.id)
    }

    @Test("Under-13 profiles default to kids mode")
    func kidsModeDefault() throws {
        let context = try makeContext()
        let repo = ProfileRepository(context: context)

        let child = try repo.create(name: "Child", ageGroup: .fiveToTwelve, isPro: true)
        let adult = try repo.create(name: "Adult", ageGroup: .thirteenPlus, isPro: true)

        #expect(child.isKidsMode)
        #expect(adult.isKidsMode == false)
    }

    // MARK: Sessions

    @Test("A 60%-complete session counts toward adherence; 40% does not")
    func adherenceThreshold() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)

        let good = SessionRecord(profile: profile, plannedSeconds: 1000, actualSeconds: 600,
                                 track: .monocular, endedReason: .userStopped)
        let poor = SessionRecord(profile: profile, plannedSeconds: 1000, actualSeconds: 400,
                                 track: .monocular, endedReason: .userStopped)

        #expect(good.countsTowardAdherence)
        #expect(poor.countsTowardAdherence == false)
    }

    @Test("Interrupted sessions never count, however long they ran")
    func interruptedNeverCounts() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)

        let session = SessionRecord(profile: profile, plannedSeconds: 1000, actualSeconds: 1000,
                                    track: .monocular, endedReason: .interrupted)
        #expect(session.countsTowardAdherence == false)
        #expect(session.validTrials.isEmpty)
    }

    @Test("Streak counts consecutive days and tolerates today being unfinished")
    func streakCounting() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        let repo = SessionRepository(context: context)
        let calendar = Calendar.current
        let now = Date()

        // Trained on each of the last 3 days, but not yet today.
        for offset in 1...3 {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            let session = SessionRecord(profile: profile, startedAt: day, endedAt: day,
                                        plannedSeconds: 600, actualSeconds: 600,
                                        track: .monocular, endedReason: .completed)
            context.insert(session)
        }
        try context.save()

        #expect(try repo.currentStreak(for: profile, now: now) == 3,
                "missing today must not break a live streak")
    }

    @Test("A gap breaks the streak")
    func streakBreaks() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context)
        let repo = SessionRepository(context: context)
        let calendar = Calendar.current
        let now = Date()

        for offset in [1, 2, 5, 6] {
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            context.insert(SessionRecord(profile: profile, startedAt: day, endedAt: day,
                                         plannedSeconds: 600, actualSeconds: 600,
                                         track: .monocular, endedReason: .completed))
        }
        try context.save()

        #expect(try repo.currentStreak(for: profile, now: now) == 2)
    }

    @Test("Daily cap is enforced per age group")
    func dailyCap() throws {
        let context = try makeContext()
        let profile = makeProfile(in: context, ageGroup: .fiveToTwelve)
        let repo = SessionRepository(context: context)
        let now = Date()

        #expect(try repo.hasReachedDailyCap(for: profile, now: now) == false)

        // 20 minutes is the under-13 ceiling.
        context.insert(SessionRecord(profile: profile, startedAt: now, endedAt: now,
                                     plannedSeconds: 1200, actualSeconds: 1200,
                                     track: .monocular, endedReason: .completed))
        try context.save()

        #expect(try repo.hasReachedDailyCap(for: profile, now: now))
    }

    // MARK: Adherence window

    @Test("Adherence never reports a window longer than the profile has existed")
    func adherenceWindowClamped() throws {
        let context = try makeContext()
        let now = Date()
        // Profile created 2 days ago; asking for a 28-day window.
        let profile = makeProfile(in: context, createdAt: Calendar.current.date(byAdding: .day, value: -2, to: now)!)
        let repo = ProgressRepository(context: context)

        let adherence = try repo.adherence(for: profile, days: 28, now: now)
        #expect(adherence.windowDays == 3, "a 2-day-old profile must not be judged over 28 days")
    }

    // MARK: Assessments

    @Test("Contrast sensitivity index rises as thresholds fall")
    func contrastIndexDirection() throws {
        let worse = AssessmentResult(contrastThresholds: [0.05, 0.06, 0.10, 0.20])
        let better = AssessmentResult(contrastThresholds: [0.01, 0.02, 0.04, 0.08])

        let w = try #require(worse.contrastSensitivityIndex)
        let b = try #require(better.contrastSensitivityIndex)
        #expect(b > w, "lower thresholds must produce a higher sensitivity index")
    }

    @Test("Interocular gap is amblyopic minus fellow")
    func interocularGap() {
        let result = AssessmentResult(acuityAmblyopic: 0.50, acuityFellow: 0.02)
        #expect(abs((result.interocularAcuityGap ?? 0) - 0.48) < 0.0001)
    }
}
