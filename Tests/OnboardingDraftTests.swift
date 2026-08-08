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

    @Test("Every audio channel starts off in a fresh draft")
    func audioStartsSilent() {
        let draft = OnboardingDraft()
        #expect(draft.musicEnabled == false)
        #expect(draft.soundEffectsEnabled == false)
        #expect(draft.voiceGuidanceEnabled == false)
    }

    // MARK: Card-check geometry
    //
    // These encode the arithmetic that forced the diagonal fallback to exist.
    // If someone later "simplifies" the calibration step back to card-only, this
    // is the test that explains why that breaks small phones.

    @Test("A bank card is physically wider than the smallest supported screens")
    func cardDoesNotFitEverywhere() {
        // iPhone SE 3rd gen: 320 x 568 pt at 326 ppi / 2x -> 64.2 pt/cm.
        let sePointsPerCM = (326.0 / 2.0) / 2.54
        let cardLong = ScreenGeometry.cardLongEdgePoints(atPointsPerCM: sePointsPerCM)
        let cardShort = cardLong * (ScreenGeometry.referenceCardHeightCM
                                    / ScreenGeometry.referenceCardWidthCM)

        #expect(cardLong > 568, "card long edge should exceed the SE's long axis")
        #expect(cardShort > 320, "even the card's SHORT edge exceeds the SE's width")
    }

    @Test("A bank card fits comfortably on a large iPad")
    func cardFitsOnIPad() {
        // iPad Pro 12.9in: 1024 x 1366 pt at 264 ppi / 2x -> 52.0 pt/cm.
        let padPointsPerCM = (264.0 / 2.0) / 2.54
        let cardLong = ScreenGeometry.cardLongEdgePoints(atPointsPerCM: padPointsPerCM)
        let cardShort = cardLong * (ScreenGeometry.referenceCardHeightCM
                                    / ScreenGeometry.referenceCardWidthCM)

        #expect(cardLong + 24 < 1366)
        #expect(cardShort + 24 < 1024)
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
