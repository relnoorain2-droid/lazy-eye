//
//  ExerciseRegistry.swift
//
//  The single list of everything the app can run.
//
//  WHY A REGISTRY RATHER THAN A SWITCH SOMEWHERE
//  Four subsystems need to enumerate exercises without knowing about each other:
//  the plan generator, the Train library, the paywall gate, and FlickerGuard's
//  safety audit. A registry means adding an exercise is one line, and - the part
//  that matters - it means the safety audit automatically covers anything new.
//  A new exercise cannot be forgotten by the thing that checks it is safe.
//
//  docs/04-ARCHITECTURE.md section 2.
//

import Foundation

enum ExerciseRegistry {

    /// Everything currently implemented. Grows through Phases 6-8 toward the
    /// full 32 in docs/03-EXERCISE-CATALOG.md.
    static let all: [ExerciseDescriptor] = [
        GaborOrientationExercise.descriptor,
        LandoltRingsExercise.descriptor,
        ContrastHuntExercise.descriptor,
        VernierExercise.descriptor,
        GlassPatternExercise.descriptor,
        CrowdedGaborExercise.descriptor,
        MotionFieldExercise.descriptor,
        CrowdedLettersExercise.descriptor,
        FindItExercise.descriptor,
        SmoothPursuitExercise.descriptor,
        JumpTargetsExercise.descriptor,
        HartChartExercise.descriptor,
        PathTracerExercise.descriptor,
        ReadingLadderExercise.descriptor,
        BalanceMeterExercise.descriptor,
        DepthPopExercise.descriptor,
        BounceExercise.descriptor,
        StackDropExercise.descriptor,
        BalloonPopExercise.descriptor,
        SkyCatchExercise.descriptor,
        SpaceDodgeExercise.descriptor,
        HiddenHalfExercise.descriptor,
        SplitMatchExercise.descriptor,
        PeekabooExercise.descriptor,
        ColourSortExercise.descriptor
    ]

    static func descriptor(for id: String) -> ExerciseDescriptor? {
        all.first { $0.id == id }
    }

    /// Live instance for an id. The `switch` is the one place that has to know
    /// concrete types; everywhere else works from descriptors.
    /// Explicit `return`s rather than a switch expression: the branches here are
    /// a concrete type and `nil`, and asking the compiler to unify those into
    /// `(any Exercise)?` by inference is exactly the kind of thing that resolves
    /// on one toolchain and not the next.
    static func make(_ id: String) -> (any Exercise)? {
        switch id {
        case GaborOrientationExercise.descriptor.id:
            return GaborOrientationExercise()
        case LandoltRingsExercise.descriptor.id:
            return LandoltRingsExercise()
        case ContrastHuntExercise.descriptor.id:
            return ContrastHuntExercise()
        case VernierExercise.descriptor.id:
            return VernierExercise()
        case GlassPatternExercise.descriptor.id:
            return GlassPatternExercise()
        case CrowdedGaborExercise.descriptor.id:
            return CrowdedGaborExercise()
        case MotionFieldExercise.descriptor.id:
            return MotionFieldExercise()
        case CrowdedLettersExercise.descriptor.id:
            return CrowdedLettersExercise()
        case FindItExercise.descriptor.id:
            return FindItExercise()
        case SmoothPursuitExercise.descriptor.id:
            return SmoothPursuitExercise()
        case JumpTargetsExercise.descriptor.id:
            return JumpTargetsExercise()
        case HartChartExercise.descriptor.id:
            return HartChartExercise()
        case PathTracerExercise.descriptor.id:
            return PathTracerExercise()
        case ReadingLadderExercise.descriptor.id:
            return ReadingLadderExercise()
        case BalanceMeterExercise.descriptor.id:
            return BalanceMeterExercise()
        case DepthPopExercise.descriptor.id:
            return DepthPopExercise()
        case BounceExercise.descriptor.id:
            return BounceExercise()
        case StackDropExercise.descriptor.id:
            return StackDropExercise()
        case BalloonPopExercise.descriptor.id:
            return BalloonPopExercise()
        case SkyCatchExercise.descriptor.id:
            return SkyCatchExercise()
        case SpaceDodgeExercise.descriptor.id:
            return SpaceDodgeExercise()
        case HiddenHalfExercise.descriptor.id:
            return HiddenHalfExercise()
        case SplitMatchExercise.descriptor.id:
            return SplitMatchExercise()
        case PeekabooExercise.descriptor.id:
            return PeekabooExercise()
        case ColourSortExercise.descriptor.id:
            return ColourSortExercise()
        default:
            return nil
        }
    }

    // MARK: Filtering

    static func available(track: Track) -> [ExerciseDescriptor] {
        all.filter { $0.track == track }
    }

    /// What this profile may actually be shown, in one place so no caller has to
    /// remember all four conditions.
    ///
    /// Note the dichoptic rule: when the user cannot use anaglyph, those
    /// exercises are HIDDEN, not shown-and-locked. A greyed-out list of things
    /// you can never have reads as a broken app, and for a user with colour
    /// vision deficiency it reads as being told their eyes are wrong.
    /// docs/05-DESIGN-SYSTEM.md section 8.
    static func available(
        for profile: Profile,
        isPro: Bool,
        canUseAnaglyph: Bool
    ) -> [ExerciseDescriptor] {
        all.filter { descriptor in
            if descriptor.requiresAnaglyph && !canUseAnaglyph { return false }
            if descriptor.minimumAgeGroup.isStricterThan(profile.ageGroup) { return false }
            if !isPro && !descriptor.isFreeTier { return false }
            return true
        }
    }

    /// Everything the profile could see if they subscribed - used to show what
    /// the paywall unlocks without pretending the anaglyph-only content is
    /// available to someone who cannot use it.
    static func lockedByPaywall(for profile: Profile,
                                canUseAnaglyph: Bool) -> [ExerciseDescriptor] {
        let unlocked = Set(available(for: profile, isPro: true,
                                     canUseAnaglyph: canUseAnaglyph).map(\.id))
        let free = Set(available(for: profile, isPro: false,
                                 canUseAnaglyph: canUseAnaglyph).map(\.id))
        return all.filter { unlocked.contains($0.id) && !free.contains($0.id) }
    }
}

// MARK: - Age ordering

extension AgeGroup {
    /// Rank by age, youngest first. Used for minimum-age comparisons; the enum's
    /// declaration order is not something to depend on.
    var rank: Int {
        switch self {
        case .underFive: 0
        case .fiveToTwelve: 1
        case .thirteenPlus: 2
        }
    }

    /// True when `self` demands an older user than `other` is.
    func isStricterThan(_ other: AgeGroup) -> Bool { rank > other.rank }
}
