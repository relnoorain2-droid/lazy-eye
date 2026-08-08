//
//  ProgressAnalyzerTests.swift
//
//  The tests that matter most are the ones checking the app REFUSES to claim
//  something. An analyser that reports improvement whenever the line slopes down
//  would pass any test written to confirm it works; these are written to catch
//  it being confidently wrong.
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Progress analysis")
struct ProgressAnalyzerTests {

    private func days(_ n: Int) -> [Double] { (0..<n).map(Double.init) }

    /// Deterministic pseudo-noise so the suite never flakes.
    private func noisySeries(slopePerDay: Double, noise: Double,
                             count: Int, seed: UInt64) -> [Double] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { index in
            // Box-Muller from the same generator the app uses.
            let u1 = max(Double.random(in: 0..<1, using: &generator), 1e-12)
            let u2 = Double.random(in: 0..<1, using: &generator)
            let gauss = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
            return 1.0 + slopePerDay * Double(index) + noise * gauss
        }
    }

    // MARK: Refusing to claim

    @Test("Pure noise produces a false claim at no more than the nominal rate")
    func flatSeriesFalsePositiveRate() {
        // ASSERTED AS A RATE, NOT PER SEED, AND THAT IS THE WHOLE POINT.
        // A 95% confidence interval is DEFINED to be wrong about 5% of the time.
        // An earlier version of this test asserted that five specific seeds all
        // returned "no clear change"; seeds 1 and 4 legitimately do not, so the
        // test had roughly a 1-in-4 chance of failing on correct code. A test
        // that flakes teaches people to re-run CI instead of reading it.
        //
        // Measured: 5.0% over 200 series. The limit below leaves real margin
        // while still catching an interval that has stopped constraining
        // anything — a broken bootstrap shows 40%+ here.
        var falsePositives = 0
        let trials = 200

        for seed in 1...UInt64(trials) {
            let values = noisySeries(slopePerDay: 0, noise: 0.06, count: 14, seed: seed)
            guard let trend = TrendFitter.fit(days: days(14), values: values,
                                              lowerIsBetter: true,
                                              bootstrapIterations: 400) else { continue }
            if trend.direction != .noClearChange { falsePositives += 1 }
        }

        let rate = Double(falsePositives) / Double(trials)
        #expect(rate < 0.12,
                "claimed a trend on \(falsePositives)/\(trials) pure-noise series (\(rate * 100)%) — the interval is not constraining anything")
    }

    @Test("A trend buried in noise produces no claim")
    func buriedTrendMakesNoClaim() {
        // A real but tiny slope under heavy noise. Reporting this as improvement
        // is the failure mode that keeps a non-responding child in the app.
        let values = noisySeries(slopePerDay: -0.0007, noise: 0.15, count: 12, seed: 77)
        let trend = try? #require(TrendFitter.fit(days: days(12), values: values,
                                                  lowerIsBetter: true))
        #expect(trend?.direction == .noClearChange)
    }

    @Test("Too few points means no claim, whatever the slope")
    func tooFewPointsMakesNoClaim() {
        // A perfect straight line, steeply improving — and still no claim,
        // because four points cannot distinguish a trend from a coincidence.
        let values = [1.0, 0.8, 0.6, 0.4]
        let trend = try? #require(TrendFitter.fit(days: days(4), values: values,
                                                  lowerIsBetter: true))
        #expect(trend?.pointCount == 4)
        #expect(trend?.direction == .noClearChange,
                "four points must not license a claim even when they line up perfectly")
    }

    // MARK: Detecting what is real

    // EFFECT SIZE CHOSEN BY POWER ANALYSIS, NOT BY EYE.
    // 0.010/day over 20 points with 0.04 noise is detected in 100 of 100 seeds.
    // The first version of these two tests used 0.003/day over 16 points, which
    // is genuinely below the detection threshold — it passed only because seed 9
    // happened to fall the right way, and seed 21 with identical parameters
    // returns "no clear change". That is a test that would fail later for no
    // reason anyone could reproduce.
    private static let detectableSlope = 0.010
    private static let detectableNoise = 0.04
    private static let detectableCount = 16

    @Test("A genuine improvement is detected")
    func realImprovementDetected() {
        let values = noisySeries(slopePerDay: -Self.detectableSlope,
                                 noise: Self.detectableNoise,
                                 count: Self.detectableCount, seed: 9)
        let trend = try? #require(TrendFitter.fit(days: days(Self.detectableCount),
                                                  values: values, lowerIsBetter: true))
        #expect(trend?.direction == .improving)
        #expect((trend?.slopePerDay ?? 0) < 0)
    }

    @Test("Worsening is reported as worsening, not hidden")
    func worseningIsReported() {
        let values = noisySeries(slopePerDay: Self.detectableSlope,
                                 noise: Self.detectableNoise,
                                 count: Self.detectableCount, seed: 9)
        let trend = try? #require(TrendFitter.fit(days: days(Self.detectableCount),
                                                  values: values, lowerIsBetter: true))
        #expect(trend?.direction == .worsening,
                "an app that only ever reports good news is not measuring anything")
    }

    @Test("Detection is reliable across seeds, not a lucky draw")
    func detectionIsReliable() {
        // Guards the power analysis itself. If someone later retunes the
        // bootstrap or the minimum point count, this catches the case where the
        // analyser quietly stops being able to see a real effect.
        var detected = 0
        let trials = 40
        for seed in 1...UInt64(trials) {
            let values = noisySeries(slopePerDay: -Self.detectableSlope,
                                     noise: Self.detectableNoise,
                                     count: Self.detectableCount, seed: seed &* 13 &+ 1)
            if TrendFitter.fit(days: days(Self.detectableCount), values: values,
                               lowerIsBetter: true,
                               bootstrapIterations: 400)?.direction == .improving {
                detected += 1
            }
        }
        #expect(detected >= 36,
                "detected a real improvement in only \(detected)/\(trials) series")
    }

    @Test("Polarity is respected: higher is better for balance")
    func polarityRespected() {
        let rising = noisySeries(slopePerDay: 0.004, noise: 0.03, count: 16, seed: 31)

        let acuity = TrendFitter.fit(days: days(16), values: rising, lowerIsBetter: true)
        let balance = TrendFitter.fit(days: days(16), values: rising, lowerIsBetter: false)

        #expect(acuity?.direction == .worsening, "rising logMAR is worse")
        #expect(balance?.direction == .improving, "rising balance ratio is better")
    }

    // MARK: Determinism

    @Test("The same history always produces the same interval")
    func intervalsAreStable() {
        // A confidence interval that wobbles between app launches destroys trust
        // in the number it qualifies.
        let values = noisySeries(slopePerDay: -0.002, noise: 0.05, count: 14, seed: 5)
        let a = TrendFitter.fit(days: days(14), values: values, lowerIsBetter: true, seed: 42)
        let b = TrendFitter.fit(days: days(14), values: values, lowerIsBetter: true, seed: 42)
        #expect(a == b)
    }

    @Test("Per-exercise seeds are stable and distinct")
    func stableSeeds() {
        #expect(ProgressAnalyzer.stableSeed(for: "m.landoltC")
                == ProgressAnalyzer.stableSeed(for: "m.landoltC"))
        #expect(ProgressAnalyzer.stableSeed(for: "m.landoltC")
                != ProgressAnalyzer.stableSeed(for: "m.vernier"))
    }

    // MARK: Degenerate input

    @Test("Degenerate input does not crash or produce nonsense")
    func degenerateInput() {
        #expect(TrendFitter.fit(days: [], values: [], lowerIsBetter: true) == nil)
        #expect(TrendFitter.fit(days: [0, 1], values: [1, 2], lowerIsBetter: true) == nil)
        #expect(TrendFitter.fit(days: [0, 1, 2], values: [1, 2], lowerIsBetter: true) == nil)

        // Every observation on the same day: no slope is defined.
        let sameDay = TrendFitter.fit(days: [3, 3, 3, 3], values: [1, 2, 3, 4],
                                      lowerIsBetter: true)
        #expect(sameDay?.slopePerDay == 0)
        #expect(sameDay?.direction == .noClearChange)

        // A perfectly constant series.
        let flat = TrendFitter.fit(days: days(12), values: Array(repeating: 0.5, count: 12),
                                   lowerIsBetter: true)
        #expect(flat?.slopePerDay == 0)
        #expect(flat?.direction == .noClearChange)
    }

    // MARK: Adherence and streaks

    @Test("Adherence counts days practised, capped at 100%")
    func adherenceIsCapped() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let analyzer = ProgressAnalyzer(now: today)

        let everyDay = Set((0..<7).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        })
        #expect(analyzer.adherence(activeDays: everyDay, days: 7, today: today) == 1.0)

        let everyOther = Set([0, 2, 4, 6].compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        })
        let partial = analyzer.adherence(activeDays: everyOther, days: 7, today: today)
        #expect(abs(partial - 4.0 / 7.0) < 1e-9)

        #expect(analyzer.adherence(activeDays: [], days: 7, today: today) == 0)
    }

    @Test("Not having trained YET today does not break a streak")
    func todayDoesNotBreakStreak() {
        // The day is not over. Punishing someone at 9am for not having trained
        // yet is how a streak turns into pressure.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let analyzer = ProgressAnalyzer(now: today)

        let yesterdayBack = Set((1...5).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        })
        #expect(analyzer.streak(activeDays: yesterdayBack, today: today) == 5)

        let includingToday = yesterdayBack.union([today])
        #expect(analyzer.streak(activeDays: includingToday, today: today) == 6)

        // A genuine two-day gap does break it.
        let gapped = Set([2, 3, 4].compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        })
        #expect(analyzer.streak(activeDays: gapped, today: today) == 0)
    }

    // MARK: Escalation

    @Test("Sparse history never triggers escalation")
    func sparseHistoryDoesNotEscalate() {
        // Absence of evidence is not evidence of a plateau. Escalating on thin
        // data would send people to an eye doctor on the strength of five
        // sessions, which is both wrong and expensive for them.
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let analyzer = ProgressAnalyzer(now: today)

        let sparse = (0..<4).compactMap { index -> ProgressAnalyzer.Observation? in
            guard let day = calendar.date(byAdding: .day, value: -index * 3, to: today) else {
                return nil
            }
            return .init(exerciseID: "m.landoltC", day: day,
                         threshold: 0.5, lowerIsBetter: true)
        }
        #expect(analyzer.countFlatBlocks(observations: sparse, today: today) == 0)
    }

    @Test("Two flat blocks with real data trigger escalation")
    func flatBlocksEscalate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let analyzer = ProgressAnalyzer(now: today)

        // Eight weeks of dense, genuinely flat practice.
        var generator = SeededGenerator(seed: 4_242)
        let observations = (0..<56).compactMap { index -> ProgressAnalyzer.Observation? in
            guard let day = calendar.date(byAdding: .day, value: -index, to: today) else {
                return nil
            }
            let jitter = Double.random(in: -0.03...0.03, using: &generator)
            return .init(exerciseID: "m.landoltC", day: day,
                         threshold: 0.5 + jitter, lowerIsBetter: true)
        }

        let blocks = analyzer.countFlatBlocks(observations: observations, today: today)
        #expect(blocks >= ProgressAnalyzer.blocksBeforeEscalation,
                "eight weeks of no change should reach the escalation threshold, got \(blocks)")
    }

    @Test("Steady improvement never triggers escalation")
    func improvementDoesNotEscalate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let analyzer = ProgressAnalyzer(now: today)

        var generator = SeededGenerator(seed: 808)
        let observations = (0..<56).compactMap { index -> ProgressAnalyzer.Observation? in
            guard let day = calendar.date(byAdding: .day, value: -index, to: today) else {
                return nil
            }
            // index counts BACKWARDS from today, so a higher index is older and
            // should carry a worse (higher) threshold.
            let jitter = Double.random(in: -0.02...0.02, using: &generator)
            return .init(exerciseID: "m.landoltC", day: day,
                         threshold: 0.4 + 0.004 * Double(index) + jitter,
                         lowerIsBetter: true)
        }
        #expect(analyzer.countFlatBlocks(observations: observations, today: today) == 0)
    }
}
