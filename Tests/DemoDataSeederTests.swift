//
//  DemoDataSeederTests.swift
//
//  The seeder feeds every App Store screenshot, so these tests protect two
//  things: reproducibility (a regenerated screenshot must be byte-identical) and
//  honesty (the demo curve must not imply results we cannot support —
//  docs/08-COMPLIANCE-LEGAL.md section 3).
//

import Testing
import Foundation
import SwiftData
@testable import Amblyo

@MainActor
struct DemoDataSeederTests {

    private func seededContext(seed: UInt64 = DemoDataSeeder.defaultSeed) throws -> ModelContext {
        let container = try ModelContainer.amblyo(inMemory: true)
        let context = ModelContext(container)
        DemoDataSeeder.seed(into: context, seed: seed, now: Date(timeIntervalSince1970: 1_785_000_000))
        return context
    }

    @Test("Seeding creates one fully set-up profile")
    func createsProfile() throws {
        let context = try seededContext()
        let profiles = try context.fetch(FetchDescriptor<Profile>())

        #expect(profiles.count == 1)
        let profile = try #require(profiles.first)
        #expect(profile.isSetUp)
        #expect(profile.canUseDichopticTrack)
        #expect(profile.amblyopicEye == .left)
    }

    @Test("Seeding is idempotent")
    func doesNotDoubleSeed() throws {
        let context = try seededContext()
        let firstCount = try context.fetchCount(FetchDescriptor<SessionRecord>())

        DemoDataSeeder.seed(into: context)

        #expect(try context.fetchCount(FetchDescriptor<SessionRecord>()) == firstCount)
        #expect(try context.fetchCount(FetchDescriptor<Profile>()) == 1)
    }

    @Test("Same seed produces identical output")
    func deterministic() throws {
        let a = try seededContext(seed: 12345)
        let b = try seededContext(seed: 12345)

        let sessionsA = try a.fetch(FetchDescriptor<SessionRecord>(
            sortBy: [SortDescriptor(\.startedAt)]))
        let sessionsB = try b.fetch(FetchDescriptor<SessionRecord>(
            sortBy: [SortDescriptor(\.startedAt)]))

        #expect(sessionsA.count == sessionsB.count)
        for (x, y) in zip(sessionsA, sessionsB) {
            #expect(x.startedAt == y.startedAt)
            #expect(x.actualSeconds == y.actualSeconds)
            #expect(x.endedReasonRaw == y.endedReasonRaw)
        }
    }

    @Test("Produces twelve weekly assessments")
    func twelveAssessments() throws {
        let context = try seededContext()
        let results = try context.fetch(FetchDescriptor<AssessmentResult>(
            sortBy: [SortDescriptor(\.date)]))
        #expect(results.count == DemoDataSeeder.Plan.weeks)
    }

    @Test("Adherence is realistic — neither perfect nor abandoned")
    func realisticAdherence() throws {
        let context = try seededContext()
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        let days = Set(sessions.map(\.day)).count
        let ratio = Double(days) / Double(DemoDataSeeder.Plan.totalDays)

        #expect(ratio > 0.55, "too sparse to look like a committed user")
        #expect(ratio < 0.90, "perfect adherence looks fake and teaches the analyzer nothing")
    }

    @Test("Session outcomes include stops, fatigue and interruptions")
    func mixedOutcomes() throws {
        let context = try seededContext()
        let sessions = try context.fetch(FetchDescriptor<SessionRecord>())
        let reasons = Set(sessions.compactMap(\.endedReason))

        #expect(reasons.contains(.completed))
        #expect(reasons.count >= 3, "a demo history of only perfect sessions is not useful")
    }

    // MARK: Honesty of the curve

    @Test("Acuity improves but stays well short of normal")
    func acuityCurveIsHonest() throws {
        let first = DemoDataSeeder.Plan.acuity(week: 0)
        let last = DemoDataSeeder.Plan.acuity(week: 11)

        #expect(last < first, "the demo should show improvement")

        // 0.1 logMAR is one line on a chart. More than three lines in twelve
        // weeks would imply an outcome no consumer app can support.
        let linesGained = (first - last) * 10
        #expect(linesGained > 1.0, "too flat to be a useful demo")
        #expect(linesGained < 3.0, "overclaims — see docs/08-COMPLIANCE-LEGAL.md section 3")
    }

    @Test("The curve plateaus rather than improving forever")
    func plateauExists() {
        let w9 = DemoDataSeeder.Plan.acuity(week: 9)
        let w11 = DemoDataSeeder.Plan.acuity(week: 11)
        #expect(abs(w9 - w11) < 0.001, "the last weeks must be flat — real curves plateau")
    }

    @Test("Binocular balance improves but never reaches parity")
    func balanceStaysHonest() {
        let first = DemoDataSeeder.Plan.balance(week: 0)
        let last = DemoDataSeeder.Plan.balance(week: 11)

        #expect(last > first)
        #expect(last < 0.5, "0.5 is perfect balance — implying a cure is not acceptable")
    }

    @Test("The fellow-eye contrast ramp rises and stays within range")
    func contrastRamp() {
        let start = DemoDataSeeder.Plan.fellowContrast(dayIndex: 0)
        let end = DemoDataSeeder.Plan.fellowContrast(dayIndex: DemoDataSeeder.Plan.totalDays - 1)

        #expect(start >= 0.1 && start <= 0.3)
        #expect(end > start)
        #expect(end <= 0.80)
    }

    @Test("Stereo is absent in the early weeks")
    func stereoAppearsLate() throws {
        let context = try seededContext()
        let results = try context.fetch(FetchDescriptor<AssessmentResult>(
            sortBy: [SortDescriptor(\.date)]))

        #expect(results.first?.stereoNotDetected == true)
        #expect(results.last?.stereoArcmin != nil)
    }

    @Test("Some trials are discarded, as they are in real sessions")
    func discardedTrialsExist() throws {
        let context = try seededContext()
        let trials = try context.fetch(FetchDescriptor<TrialRecord>())

        #expect(trials.count > 500, "not enough trials to exercise the charts")
        #expect(trials.contains { $0.discarded }, "dropped-frame handling must be represented")
    }
}
