//
//  OnboardingDraftTests.swift
//
//  The draft decides which steps are passable and what gets written to the store,
//  so these tests are guarding two things that are expensive to get wrong:
//  a legal gate (the disclaimer) and a measurement gate (calibration).
//

import Testing
import Foundation
@testable import Amblyo

@Suite("Onboarding draft")
struct OnboardingDraftTests {

    // MARK: Disclaimer gate

    @Test("Disclaimer step cannot be passed without an explicit acknowledgement")
    func disclaimerBlocks() {
        var draft = OnboardingDraft()
        #expect(draft.canAdvance(from: .disclaimer) == false)
        #expect(draft.blockingReason(for: .disclaimer) != nil)

        draft.hasAcknowledgedDisclaimer = true
        #expect(draft.canAdvance(from: .disclaimer))
        #expect(draft.blockingReason(for: .disclaimer) == nil)
    }

    @Test("Acknowledgement is carried into the stored preferences")
    func acknowledgementPersists() {
        var draft = OnboardingDraft()
        draft.hasAcknowledgedDisclaimer = true
        #expect(draft.preferences.hasAcknowledgedDisclaimer)
    }

    // MARK: Calibration gate

    @Test("Calibration step requires a plausible density and distance")
    func calibrationBlocks() {
        var draft = OnboardingDraft()
        #expect(draft.canAdvance(from: .calibration) == false, "zero density must not pass")

        draft.screenPointsPerCM = 55
        draft.viewingDistanceCM = 45
        #expect(draft.canAdvance(from: .calibration))
    }

    // Looped rather than a parameterised `arguments:` tuple array. Swift Testing
    // can destructure a collection of tuples into a two-parameter test, but the
    // overload resolution between "one collection of tuples" and "a tuple of
    // collections" is the sort of ambiguity that costs a full CI round trip to
    // discover. A named case list reads just as well in a failure message.
    @Test("Implausible values are rejected at both ends")
    func implausibleValuesRejected() {
        let cases: [(name: String, density: Double, distance: Double)] = [
            ("density far too low", 5, 45),
            ("density far too high", 500, 45),
            ("sitting inside the screen", 55, 2),
            ("across the room", 55, 400),
        ]
        for testCase in cases {
            var draft = OnboardingDraft()
            draft.screenPointsPerCM = testCase.density
            draft.viewingDistanceCM = testCase.distance
            #expect(draft.isCalibrationUsable == false, "\(testCase.name) was accepted")
        }
    }

    // MARK: Non-blocking steps
    //
    // Regression guard. An earlier draft of the flow required an eye to be
    // chosen, which strands every user who does not know - a large share of
    // adults with amblyopia have never been told which eye it is.

    @Test("Not knowing which eye is weaker does not block setup")
    func unknownEyeIsAllowed() {
        var draft = OnboardingDraft()
        draft.amblyopicEye = .unknown
        #expect(draft.canAdvance(from: .profile))
    }

    @Test("An empty name does not block setup and falls back")
    func emptyNameIsAllowed() {
        var draft = OnboardingDraft()
        draft.name = "   "
        #expect(draft.canAdvance(from: .profile))
        #expect(draft.resolvedName == "Me")

        draft.name = "  Sara  "
        #expect(draft.resolvedName == "Sara")
    }

    // MARK: Age

    @Test("Birth year wins over an explicit age group")
    func birthYearWins() {
        var draft = OnboardingDraft()
        draft.explicitAgeGroup = .thirteenPlus

        let currentYear = Calendar.current.component(.year, from: .now)
        draft.birthYear = currentYear - 7
        #expect(draft.ageGroup == .fiveToTwelve)
        #expect(draft.isKidsMode)
    }

    @Test("With no age information at all the adult default applies")
    func ageDefaults() {
        let draft = OnboardingDraft()
        #expect(draft.ageGroup == .thirteenPlus)
        #expect(draft.isKidsMode == false)
    }

    // MARK: Sound defaults
    //
    // The single most important default in the app. docs/05-DESIGN-SYSTEM.md §7.

    /// An isolated suite per call, so nothing leaks between tests.
    private func freshDefaults() -> UserDefaults {
        let name = "amblyo.draft.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // `SettingsStore` is @MainActor, so a test that constructs one must be too.
    @MainActor
    @Test("The draft's audio defaults match the settings store's, exactly")
    func audioDefaultsMatchTheStore() {
        // WHY THIS IS COMPARED RATHER THAN HARD-CODED.
        //
        // `OnboardingFlow.persist()` copies the draft over the settings store on
        // commit. So these two sets of defaults are not merely similar, they are
        // the same decision written twice — and when sound effects were turned
        // on in the store, this draft still said off, which would have silently
        // reverted the change for every new user at the end of setup. The store
        // tests would have stayed green throughout, because they never run
        // onboarding.
        //
        // Comparing them means the next person to change one is told about the
        // other, instead of finding out from a device weeks later.
        let draft = OnboardingDraft()
        let store = SettingsStore(defaults: freshDefaults())

        #expect(draft.musicEnabled == store.musicEnabled)
        #expect(draft.soundEffectsEnabled == store.soundEffectsEnabled)
        #expect(draft.voiceGuidanceEnabled == store.voiceGuidanceEnabled)
    }

    @Test("Feedback sound is on by default, so a first session is not silent")
    func feedbackSoundStartsOn() {
        #expect(OnboardingDraft().soundEffectsEnabled)
        #expect(OnboardingDraft().musicEnabled == false)
        #expect(OnboardingDraft().voiceGuidanceEnabled == false)
    }

    // MARK: Card-check geometry
    //
    // These encode the arithmetic that forced the diagonal fallback to exist.
    // If someone later "simplifies" the calibration step back to card-only, this
    // is the test that explains why that breaks small phones.

    @Test("The card check is refused on the smallest supported screens")
    func cardDoesNotFitEverywhere() {
        // iPhone SE 3rd gen: 320 x 568 pt at 326 ppi / 2x -> 64.17 pt/cm.
        // Card at true size: 549.3 x 346.4 pt.
        let sePointsPerCM = (326.0 / 2.0) / 2.54

        #expect(ScreenGeometry.cardCheckFits(longAxisPoints: 568,
                                             shortAxisPoints: 320,
                                             atPointsPerCM: sePointsPerCM) == false)

        // WHY it does not fit, stated exactly, because an earlier version of
        // this test asserted the wrong reason and passed for the wrong screens.
        // The long edge (549) actually IS smaller than the 568 pt long axis; it
        // is the SHORT edge, at 346 pt against a 320 pt width, that makes the
        // card impossible in either orientation.
        let short = ScreenGeometry.cardShortEdgePoints(atPointsPerCM: sePointsPerCM)
        let long = ScreenGeometry.cardLongEdgePoints(atPointsPerCM: sePointsPerCM)
        #expect(short > 320, "card short edge \(short) must exceed the SE's 320 pt width")
        #expect(long < 568, "card long edge \(long) is NOT wider than the 568 pt long axis")
    }

    @Test("The card check is offered on a large iPad")
    func cardFitsOnIPad() {
        // iPad Pro 12.9in: 1024 x 1366 pt at 264 ppi / 2x -> 51.97 pt/cm.
        let padPointsPerCM = (264.0 / 2.0) / 2.54
        #expect(ScreenGeometry.cardCheckFits(longAxisPoints: 1366,
                                             shortAxisPoints: 1024,
                                             atPointsPerCM: padPointsPerCM))
    }

    @Test("The decision is made from the window size, not the device")
    func cardCheckUsesWindowNotDevice() {
        let padPointsPerCM = (264.0 / 2.0) / 2.54

        // An iPad's card is only 445 x 281 pt because its density is LOW, so it
        // still fits a 320 pt Slide Over window. I first wrote this test asserting
        // the opposite — that a narrow window always falls back — and the
        // simulation showed it was false. The real property worth pinning is that
        // the answer tracks the window, so a genuinely tiny window does refuse.
        #expect(ScreenGeometry.cardCheckFits(longAxisPoints: 1366,
                                             shortAxisPoints: 320,
                                             atPointsPerCM: padPointsPerCM),
                "a 320 pt window still fits an iPad-density card")

        #expect(ScreenGeometry.cardCheckFits(longAxisPoints: 1366,
                                             shortAxisPoints: 280,
                                             atPointsPerCM: padPointsPerCM) == false,
                "a 280 pt window cannot")
    }

    @Test("Card width converts back to the density it came from")
    func cardRoundTrip() {
        for density in [40.0, 52.0, 64.2, 79.0] {
            let points = ScreenGeometry.cardLongEdgePoints(atPointsPerCM: density)
            let recovered = ScreenGeometry.pointsPerCM(fromCardWidthInPoints: points)
            #expect(abs(recovered - density) < 0.0001)
        }
    }

    // MARK: Step sequence

    @Test("Steps form one unbroken chain from welcome to ready")
    func stepChain() {
        var visited: [OnboardingStep] = []
        var current: OnboardingStep? = .welcome
        while let step = current {
            visited.append(step)
            current = step.next
        }
        #expect(visited == OnboardingStep.allCases)
        #expect(visited.last?.isLast == true)
        #expect(OnboardingStep.welcome.previous == nil)
    }

    @Test("Progress runs strictly upward and ends at exactly 1")
    func progressMonotonic() {
        let values = OnboardingStep.allCases.map(\.progress)
        #expect(values == values.sorted())
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 < $1 })
        #expect(values.last == 1.0)
        #expect(values.first ?? 0 > 0, "the bar should never read as empty")
    }
}
