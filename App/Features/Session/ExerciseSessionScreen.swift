//
//  ExerciseSessionScreen.swift
//
//  The one place that knows which view runs which exercise.
//
//  WHY IT MOVED OUT OF TrainView
//  Today can start a planned session too, and a second copy of a fifteen-case
//  switch is a guarantee that one of them will fall behind. When exercise D6 is
//  added it must appear here and nowhere else; if it is missed, EVERY entry
//  point falls through to the same default rather than one of them quietly
//  running the wrong view.
//
//  THE DEFAULT CASE IS A KNOWN COMPROMISE.
//  Swift cannot exhaustively switch over registry ids, so an unmapped exercise
//  lands on `GaborOrientationView`. `ExerciseSessionScreenTests.everyRegisteredExerciseIsMapped`
//  is what stops that from ever being reached in a shipped build.
//

import SwiftUI

@MainActor
struct ExerciseSessionScreen: View {

    let runner: SessionRunner
    let descriptor: ExerciseDescriptor
    let calibration: CalibrationProfile
    let onFinish: () -> Void

    /// Exercise ids this screen presents with a purpose-built view. Kept next to
    /// the switch so a test can compare it against the registry — the two drift
    /// apart the moment someone adds an exercise and forgets one of them.
    static let mappedExerciseIDs: Set<String> = [
        GaborOrientationExercise.descriptor.id,
        LandoltRingsExercise.descriptor.id,
        ContrastHuntExercise.descriptor.id,
        VernierExercise.descriptor.id,
        GlassPatternExercise.descriptor.id,
        CrowdedGaborExercise.descriptor.id,
        CrowdedLettersExercise.descriptor.id,
        MotionFieldExercise.descriptor.id,
        FindItExercise.descriptor.id,
        SmoothPursuitExercise.descriptor.id,
        JumpTargetsExercise.descriptor.id,
        HartChartExercise.descriptor.id,
        PathTracerExercise.descriptor.id,
        ReadingLadderExercise.descriptor.id,
        BalanceMeterExercise.descriptor.id,
        DepthPopExercise.descriptor.id,
        BounceExercise.descriptor.id,
        StackDropExercise.descriptor.id,
        BalloonPopExercise.descriptor.id,
        SkyCatchExercise.descriptor.id,
        SpaceDodgeExercise.descriptor.id,
        HiddenHalfExercise.descriptor.id,
        SplitMatchExercise.descriptor.id,
        PeekabooExercise.descriptor.id,
        ColourSortExercise.descriptor.id,
        DepthStepsExercise.descriptor.id,
        HoldTheFusionExercise.descriptor.id,
        BeadLineExercise.descriptor.id,
        MazeRunnerExercise.descriptor.id,
        RhythmTapExercise.descriptor.id,
    ]

    var body: some View {
        // Every exercise that is "look at a stimulus, tap which one" shares
        // ChoiceExerciseView, so the fatigue button, break card and honest
        // summary exist in exactly one place.
        switch descriptor.id {
        case LandoltRingsExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: LandoltPresenter()) { _ in onFinish() }
        case ContrastHuntExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: ContrastHuntPresenter()) { _ in onFinish() }
        case VernierExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: VernierPresenter()) { _ in onFinish() }
        case GlassPatternExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: GlassPatternPresenter()) { _ in onFinish() }
        case CrowdedGaborExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: CrowdedGaborPresenter()) { _ in onFinish() }
        case CrowdedLettersExercise.descriptor.id:
            ChoiceExerciseView(runner: runner, calibration: calibration,
                               presenter: CrowdedLettersPresenter()) { _ in onFinish() }

        // These cannot use the shared shell: some animate, some take their
        // answer from a tap location rather than a button.
        case MotionFieldExercise.descriptor.id:
            MotionFieldView(runner: runner, calibration: calibration) { _ in onFinish() }
        case FindItExercise.descriptor.id:
            FindItView(runner: runner, calibration: calibration) { _ in onFinish() }
        case SmoothPursuitExercise.descriptor.id:
            SmoothPursuitView(runner: runner, calibration: calibration) { _ in onFinish() }
        case JumpTargetsExercise.descriptor.id:
            JumpTargetsView(runner: runner, calibration: calibration) { _ in onFinish() }
        case HartChartExercise.descriptor.id:
            HartChartView(runner: runner, calibration: calibration) { _ in onFinish() }
        case PathTracerExercise.descriptor.id:
            PathTracerView(runner: runner, calibration: calibration) { _ in onFinish() }
        case ReadingLadderExercise.descriptor.id:
            ReadingLadderView(runner: runner, calibration: calibration) { _ in onFinish() }
        case BalanceMeterExercise.descriptor.id:
            BalanceMeterView(runner: runner, calibration: calibration) { _ in onFinish() }
        case DepthPopExercise.descriptor.id:
            DepthPopView(runner: runner, calibration: calibration) { _ in onFinish() }
        case BounceExercise.descriptor.id:
            BounceView(runner: runner, calibration: calibration) { _ in onFinish() }
        case StackDropExercise.descriptor.id:
            StackDropView(runner: runner, calibration: calibration) { _ in onFinish() }
        case BalloonPopExercise.descriptor.id:
            BalloonPopView(runner: runner, calibration: calibration) { _ in onFinish() }
        case SkyCatchExercise.descriptor.id:
            SkyCatchView(runner: runner, calibration: calibration) { _ in onFinish() }
        case SpaceDodgeExercise.descriptor.id:
            SpaceDodgeView(runner: runner, calibration: calibration) { _ in onFinish() }
        case HiddenHalfExercise.descriptor.id:
            HiddenHalfView(runner: runner, calibration: calibration) { _ in onFinish() }
        case SplitMatchExercise.descriptor.id:
            SplitMatchView(runner: runner, calibration: calibration) { _ in onFinish() }
        case PeekabooExercise.descriptor.id:
            PeekabooView(runner: runner, calibration: calibration) { _ in onFinish() }
        case ColourSortExercise.descriptor.id:
            ColourSortView(runner: runner, calibration: calibration) { _ in onFinish() }
        case DepthStepsExercise.descriptor.id:
            DepthStepsView(runner: runner, calibration: calibration) { _ in onFinish() }
        case HoldTheFusionExercise.descriptor.id:
            HoldTheFusionView(runner: runner, calibration: calibration) { _ in onFinish() }
        case BeadLineExercise.descriptor.id:
            BeadLineView(runner: runner, calibration: calibration) { _ in onFinish() }
        case MazeRunnerExercise.descriptor.id:
            MazeRunnerView(runner: runner, calibration: calibration) { _ in onFinish() }
        case RhythmTapExercise.descriptor.id:
            RhythmTapView(runner: runner, calibration: calibration) { _ in onFinish() }
        default:
            GaborOrientationView(runner: runner, calibration: calibration) { _ in onFinish() }
        }
    }
}
