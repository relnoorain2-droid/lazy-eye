//
//  RepositoryExecutionTests.swift
//
//  EVERY READ, EXECUTED ONCE, AGAINST A STORE WITH REAL DATA IN IT.
//
//  This suite exists because of one line that shipped to TestFlight:
//
//      $0.session?.profile?.id == profileID
//
//  Two optional relationship hops in a `#Predicate`. Core Data cannot build SQL
//  for that. It does not return an error or an empty result — it throws an
//  Objective-C exception inside `NSSQLFetchRequestContext _createStatement`,
//  and an uncaught ObjC exception is SIGABRT. The app died every time the Today
//  screen rendered for a profile with any history, which is to say for every
//  real user immediately after finishing setup.
//
//  It compiled. It read perfectly. 466 tests passed. Not one of them had ever
//  CALLED `trials(for:exerciseID:)`, so the predicate had never been handed to
//  the SQL generator, so the defect was invisible until a device ran it.
//
//  The general rule this encodes: a `#Predicate` is not checked by the Swift
//  compiler in the way it appears to be. It is a program compiled a second time,
//  at runtime, by Core Data — and the only way to know that compilation succeeds
//  is to run it. So every repository read gets called here at least once, with
//  data present, and the assertions are deliberately weak. The point is not what
//  they return. The point is that they return at all.
//

import Testing
import Foundation
import SwiftData
@testable import Amblyo

@MainActor
@Suite("Repository queries execute")
struct RepositoryExecutionTests {

    /// A container with the full demo history in it — 84 days, ~180 sessions,
    /// several thousand trials. An empty store would let a broken predicate
    /// pass, because Core Data can sometimes shortcut a fetch it knows matches
    /// nothing.
    private func seededStore() throws -> (ModelContext, Profile) {
        let container = try ModelContainer.amblyo(inMemory: true)
        let context = ModelContext(container)
        DemoDataSeeder.seed(into: context)
        let profile = try #require(try context.fetch(FetchDescriptor<Profile>()).first)
        return (context, profile)
    }

    @Test("every SessionRepository read runs against real data")
    func sessionReadsExecute() throws {
        let (context, profile) = try seededStore()
        let repository = SessionRepository(context: context)

        _ = try repository.sessions(for: profile)
        _ = try repository.sessions(for: profile, since: .now.addingTimeInterval(-86_400 * 30))
        _ = try repository.sessions(for: profile, limit: 5)
        _ = try repository.mostRecent(for: profile)
        _ = try repository.secondsToday(for: profile)
        _ = try repository.hasReachedDailyCap(for: profile)
        _ = try repository.activeDays(for: profile, since: .now.addingTimeInterval(-86_400 * 90))
        _ = try repository.currentStreak(for: profile)

        // THE ONE THAT CRASHED. Called for every exercise the demo history
        // touches, because the failure is in translating the predicate and it
        // does not depend on which exercise is asked for.
        for exerciseID in ExerciseRegistry.all.map(\.id) {
            _ = try repository.trials(for: profile, exerciseID: exerciseID)
        }
    }

    @Test("trials come back newest first, capped, and never discarded")
    func trialsContractHolds() throws {
        // Weak assertions on purpose, but not zero: the crash fix moved this
        // query from one SQL predicate to a fetch plus in-memory filtering, and
        // the contract has to survive that change.
        let (context, profile) = try seededStore()
        let repository = SessionRepository(context: context)

        let id = "m.gaborOrientation"
        let trials = try repository.trials(for: profile, exerciseID: id, limit: 50)
        #expect(trials.count <= 50, "the limit is not being applied")
        #expect(trials.allSatisfy { $0.exerciseID == id })
        #expect(trials.allSatisfy { !$0.discarded },
                "discarded trials are excluded — they are not evidence")

        let timestamps = trials.map(\.timestamp)
        #expect(timestamps == timestamps.sorted(by: >), "newest first")
    }

    @Test("every ProgressRepository read runs against real data")
    func progressReadsExecute() throws {
        let (context, profile) = try seededStore()
        let repository = ProgressRepository(context: context)

        _ = try repository.assessments(for: profile)
        _ = try repository.assessments(for: profile, limit: 3)
        _ = try repository.latestAssessment(for: profile)
        _ = try repository.blockIndex(for: profile)
        _ = try repository.isAssessmentDue(for: profile)
        _ = try repository.adherence(for: profile, days: 28)
        _ = try repository.fellowContrastSeries(for: profile)
        _ = try repository.minutesPerDay(for: profile, days: 30)
        for test in AssessmentTest.allCases {
            _ = try repository.series(for: profile, test: test)
        }
    }

    @Test("every ProfileRepository read runs against real data")
    func profileReadsExecute() throws {
        let (context, profile) = try seededStore()
        let repository = ProfileRepository(context: context)

        _ = try repository.all()
        _ = try repository.active()
        _ = try repository.profile(id: profile.id)
        _ = try repository.count()
    }
}
