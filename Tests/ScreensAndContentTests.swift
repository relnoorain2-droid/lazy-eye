//
//  ScreensAndContentTests.swift
//
//  Views themselves are not unit-testable without a host app, so everything on
//  a screen that CAN be a pure function is one — and those are what these tests
//  pin. What is left is layout, and layout is checked by looking at it.
//
//  The two tests that matter most here are `everyRegisteredExerciseIsMapped`
//  (a missing case silently runs the wrong exercise) and the content sweeps
//  (a medical claim in an article is a rejection, and articles are long).
//

import Testing
import Foundation
@testable import Amblyo

@MainActor
@Suite("Session host mapping")
struct ExerciseSessionScreenTests {

    @Test("every registered exercise has a purpose-built view")
    func everyRegisteredExerciseIsMapped() {
        let registered = Set(ExerciseRegistry.all.map(\.id))
        let mapped = ExerciseSessionScreen.mappedExerciseIDs
        let missing = registered.subtracting(mapped)

        #expect(missing.isEmpty,
                "these exercises would fall through to the default case and run the WRONG view: \(missing.sorted())")
    }

    @Test("the mapping contains no ids that left the registry")
    func mappingHasNoStaleIDs() {
        let registered = Set(ExerciseRegistry.all.map(\.id))
        let stale = ExerciseSessionScreen.mappedExerciseIDs.subtracting(registered)
        #expect(stale.isEmpty, "stale entries: \(stale.sorted())")
    }
}

@MainActor
@Suite("Today screen logic")
struct TodayViewLogicTests {

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    @Test("the greeting matches the time of day", arguments: [
        (7, "Good morning"), (11, "Good morning"),
        (12, "Good afternoon"), (17, "Good afternoon"),
        (18, "Good evening"), (22, "Good evening"),
        (23, "Late one"), (3, "Late one"),
    ])
    func greetingMatchesHour(hour: Int, expected: String) {
        #expect(TodayView.greetingWord(at: date(hour: hour)) == expected)
    }

    @Test("no hour produces an empty greeting")
    func greetingIsNeverEmpty() {
        for hour in 0..<24 {
            #expect(!TodayView.greetingWord(at: date(hour: hour)).isEmpty)
        }
    }

    @Test("setup message names the eye first, then consent, then calibration")
    func setupMessageOrdersByUrgency() {
        let nothing = Profile(name: "A", amblyopicEye: .unknown)
        #expect(TodayView.setupMessage(for: nothing).contains("eye"),
                "an unassigned eye means every session trains the wrong thing")

        let eyeSet = Profile(name: "B", amblyopicEye: .left)
        #expect(TodayView.setupMessage(for: eyeSet).contains("what this app is"),
                "consent comes before convenience")

        let consented = Profile(
            name: "C", amblyopicEye: .left,
            preferences: PreferencesBlob(hasAcknowledgedDisclaimer: true))
        #expect(TodayView.setupMessage(for: consented).contains("screen"))
    }

    @Test("the setup message never lists more than one next step")
    func setupMessageIsOneStep() {
        let profile = Profile(name: "A", amblyopicEye: .unknown)
        let message = TodayView.setupMessage(for: profile)
        #expect(!message.contains("•") && !message.contains("\n"),
                "a checklist of everything you haven't done is discouraging")
    }
}

@MainActor
@Suite("Profile screen logic")
struct ProfileTabViewLogicTests {

    @Test("session lengths never exceed the age group's daily cap")
    func lengthsRespectTheCap() {
        for group in AgeGroup.allCases {
            let options = ProfileTabView.sessionLengthOptions(cap: group.dailyCapSeconds)
            #expect(!options.isEmpty, "\(group) must be offered something")
            #expect(options.allSatisfy { $0 <= group.dailyCapSeconds },
                    "offering a length that gets silently clipped is worse than not offering it")
            #expect(options.allSatisfy { $0 <= SafetyLimits.maxSessionSeconds })
        }
    }

    @Test("a five-year-old is not offered a half-hour session")
    func youngChildrenGetShortOptions() {
        let options = ProfileTabView.sessionLengthOptions(cap: AgeGroup.underFive.dailyCapSeconds)
        #expect(options.max() ?? 0 <= 20 * 60)
    }

    @Test("every entitlement state has a label, and none of them are blank")
    func everyStatusHasALabel() {
        let states: [EntitlementStatus] = [
            .unknown, .free, .pro(expires: nil), .pro(expires: .now),
            .inGracePeriod(expires: .now), .inBillingRetry,
        ]
        for state in states {
            let label = ProfileTabView.statusLabel(state)
            #expect(!label.isEmpty, "\(state) renders as an empty row")
        }
    }

    @Test("a billing problem is stated, not hidden behind 'active'")
    func billingProblemsAreVisible() {
        let grace = ProfileTabView.statusLabel(.inGracePeriod(expires: .now))
        let retry = ProfileTabView.statusLabel(.inBillingRetry)
        #expect(grace.lowercased().contains("payment"))
        #expect(retry.lowercased().contains("payment"),
                "someone whose card has failed needs to know before access disappears")
    }

    @Test("profile subtitle says when the eye is unset")
    func subtitleFlagsUnsetEye() {
        let unset = Profile(name: "A", amblyopicEye: .unknown)
        #expect(ProfileTabView.subtitle(for: unset).contains("not set"))

        let set = Profile(name: "B", amblyopicEye: .right)
        #expect(!ProfileTabView.subtitle(for: set).contains("not set"))
    }

    @Test("kids mode is visible in the subtitle")
    func subtitleShowsKidsMode() {
        let child = Profile(name: "C", ageGroup: .fiveToTwelve, isKidsMode: true)
        #expect(ProfileTabView.subtitle(for: child).contains("kids mode"))
    }

    @Test("the version string is never empty, even without an Info.plist")
    func versionStringIsSafe() {
        #expect(!ProfileTabView.versionString.isEmpty)
    }
}

@Suite("Learn content")
struct LearnContentTests {

    /// Every string the Learn tab can render, flattened.
    private var allText: [String] {
        LearnArticle.all.flatMap { article -> [String] in
            var strings = [article.title, article.blurb]
            for block in article.blocks {
                switch block {
                case .heading(let text), .paragraph(let text), .bullet(let text):
                    strings.append(text)
                case .evidence(_, let text):
                    strings.append(text)
                }
            }
            return strings
        }
    }

    @Test("article ids are unique")
    func idsAreUnique() {
        let ids = LearnArticle.all.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids break SwiftUI's ForEach identity")
    }

    @Test("no article is empty or untitled")
    func articlesAreComplete() {
        for article in LearnArticle.all {
            #expect(!article.title.isEmpty)
            #expect(!article.blurb.isEmpty)
            #expect(!article.blocks.isEmpty, "\(article.id) renders a blank sheet")
            #expect(!article.systemImage.isEmpty)
        }
    }

    @Test("no text block is blank")
    func noBlankBlocks() {
        for text in allText {
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// The same list the claims linter enforces over source files. Repeated here
    /// because a violation in article prose is the most likely place for one to
    /// appear, and a compiled test fails faster than a CI lint step.
    private static let bannedPhrases = [
        "cure", "cures", "treat your", "treatment for", "diagnose", "diagnosis",
        "guarantee", "guaranteed", "clinically proven", "medically proven",
        "restore your vision", "fix your eye", "20/20",
    ]

    @Test("no article makes a medical claim")
    func noMedicalClaims() {
        for text in allText {
            let lowered = text.lowercased()
            for phrase in Self.bannedPhrases where lowered.contains(phrase) {
                Issue.record("\"\(phrase)\" appears in Learn content: \(text)")
            }
        }
    }

    @Test("the evidence article shows all three tiers, not just the best one")
    func evidenceArticleCoversEveryTier() {
        var tiers: Set<EvidenceTier> = []
        for block in LearnArticle.evidence.blocks {
            if case .evidence(let tier, _) = block { tiers.insert(tier) }
        }
        #expect(tiers == Set(EvidenceTier.allCases),
                "showing only the strong tier is exactly the kind of selective honesty the badges exist to prevent")
    }

    @Test("the safety article tells people when to stop")
    func safetyArticleSaysWhenToStop() {
        let text = allText.joined(separator: " ").lowercased()
        #expect(text.contains("headache"))
        #expect(text.contains("stop"))
    }

    @Test("something in Learn tells people to see a professional")
    func learnPointsToProfessionals() {
        let text = allText.joined(separator: " ").lowercased()
        #expect(text.contains("optometrist") || text.contains("ophthalmologist")
                || text.contains("eye care professional"))
    }

    @Test("the glasses article says which glasses do NOT work")
    func glassesArticleRulesOutWrongGlasses() {
        let text = LearnArticle.glasses.blocks.compactMap { block -> String? in
            if case .bullet(let value) = block { return value }
            if case .paragraph(let value) = block { return value }
            return nil
        }.joined(separator: " ").lowercased()

        #expect(text.contains("polaris") || text.contains("cinema"),
                "someone will try their cinema 3D glasses, and they don't work")
        #expect(text.contains("red-green") || text.contains("red-cyan"))
    }

    @Test("no article promises a timescale it cannot keep")
    func noPromisedTimescales() {
        let text = allText.joined(separator: " ").lowercased()
        for phrase in ["in just", "within days", "in a week", "overnight"] {
            #expect(!text.contains(phrase), "\"\(phrase)\" is a promise, not a description")
        }
    }
}
