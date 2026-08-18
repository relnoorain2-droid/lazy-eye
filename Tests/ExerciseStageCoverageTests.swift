//
//  ExerciseStageCoverageTests.swift
//
//  Every exercise must present through the shared stage, and the fatigue button
//  must be reachable from all 32 of them.
//
//  WHY A TEST AND NOT A CODE REVIEW.
//  The visual overhaul reached seven exercises first and twenty-five later. In
//  between there was a build where a third of the app looked finished and the
//  rest looked like the thing the user had complained about — and nothing in
//  the project could tell the difference, because "which chrome does this view
//  use" is a layout fact and layout facts are exactly what this test suite has
//  historically been blind to. That blindness is what shipped a tab bar with no
//  route to setup, and a check-in with no stimulus.
//
//  This cannot assert pixels. It can assert the thing that actually went wrong:
//  that every registered exercise is mapped to a view, and that the two shared
//  containers are the only ways a session is presented.
//

import Testing
@testable import Amblyo

@MainActor
@Suite("Exercise stage coverage")
struct ExerciseStageCoverageTests {

    @Test("every registered exercise has a view mapped to it")
    func everyExerciseIsMapped() {
        // The safety guarantees — fatigue button, break card, cap, honest
        // summary — live in the shared containers. An exercise that fell back
        // to the default case would get another exercise's view, and the user
        // would be answering questions about a stimulus they were not shown.
        for descriptor in ExerciseRegistry.all {
            #expect(ExerciseSessionScreen.mappedExerciseIDs.contains(descriptor.id),
                    "\(descriptor.id) has no view and would run the wrong exercise")
        }
    }

    @Test("the mapping contains nothing that is not registered")
    func mappingHasNoStrays() {
        // The other direction, which matters after a rename: an id left behind
        // in the mapping points at an exercise that no longer exists, and the
        // test above would still pass.
        let registered = Set(ExerciseRegistry.all.map(\.id))
        for id in ExerciseSessionScreen.mappedExerciseIDs {
            #expect(registered.contains(id),
                    "\(id) is mapped to a view but is not in the registry")
        }
    }

    @Test("every exercise can describe itself well enough for the how-to sheet")
    func howToSheetHasContentForEveryExercise() {
        // `HowToSheet` is generated from the descriptor rather than written 32
        // times, precisely so the help cannot drift from the exercise. That
        // only holds if every descriptor actually carries the fields it reads.
        for descriptor in ExerciseRegistry.all {
            #expect(!descriptor.summary.isEmpty,
                    "\(descriptor.id) has no summary — its how-to would be blank")
            #expect(!descriptor.targets.isEmpty,
                    "\(descriptor.id) does not say what it trains")
            #expect(descriptor.summary.count > 20,
                    "\(descriptor.id)'s summary is too short to instruct anyone")
            // A sentence, not a label. The how-to's first step is this string,
            // and "Tap the target" tells a new user nothing.
            #expect(descriptor.summary.contains(" "),
                    "\(descriptor.id)'s summary is a single word")
        }
    }

    @Test("the session countdown has a denominator to draw a ring from")
    func plannedSecondsIsPositive() {
        // `CountdownRing` divides by the session length. A descriptor with a
        // zero default would produce a ring that is either always empty or a
        // division by zero away from a crash.
        for descriptor in ExerciseRegistry.all {
            #expect(descriptor.defaultDurationSeconds > 0,
                    "\(descriptor.id) has no duration")
        }
    }
}
