//
//  AssessmentResult.swift
//
//  One weekly check-in. Four sub-tests, ~6 minutes. These are the numbers on the
//  Progress screen and the input to the plateau/escalation rule.
//
//  COMPLIANCE: every surface that displays any of these values must show
//  `AssessmentTest.scoreQualifier` — "Training score — not a clinical
//  measurement". docs/08-COMPLIANCE-LEGAL.md section 2.
//
//  docs/03-EXERCISE-CATALOG.md, assessment battery section.
//

import Foundation
import SwiftData

@Model
final class AssessmentResult {

    @Attribute(.unique) var id: UUID
    var profile: Profile?

    var date: Date

    /// Which 4-week block this belongs to, counted from the profile's first
    /// session. Drives the plateau rule.
    var blockIndex: Int

    // MARK: Sub-test results. All optional — a user may skip sub-tests, and the
    // free tier only unlocks one of them.

    /// logMAR-STYLE score for each eye. Lower is better. Not a clinical logMAR.
    var acuityAmblyopic: Double?
    var acuityFellow: Double?

    /// Contrast threshold at 4 spatial frequencies (1.5, 3, 6, 12 c/deg).
    /// Lower threshold = better sensitivity. Empty when not measured.
    var contrastThresholds: [Double]

    /// Interocular balance point, 0…1. 0.5 = balanced; below 0.5 means the
    /// amblyopic eye needed extra contrast to contribute equally.
    /// The app's most defensible metric.
    var binocularBalance: Double?

    /// Stereo threshold in arc-minutes. Lower is better. nil = not measured or
    /// no stereo detected at the coarsest disparity.
    var stereoArcmin: Double?

    /// Set when the user reached the coarsest level without perceiving depth.
    /// Distinct from "not measured" and worth showing differently.
    var stereoNotDetected: Bool

    /// Seconds spent on the assessment, for the adherence picture.
    var durationSeconds: Int

    init(
        id: UUID = UUID(),
        profile: Profile? = nil,
        date: Date = .now,
        blockIndex: Int = 0,
        acuityAmblyopic: Double? = nil,
        acuityFellow: Double? = nil,
        contrastThresholds: [Double] = [],
        binocularBalance: Double? = nil,
        stereoArcmin: Double? = nil,
        stereoNotDetected: Bool = false,
        durationSeconds: Int = 0
    ) {
        self.id = id
        self.profile = profile
        self.date = date
        self.blockIndex = blockIndex
        self.acuityAmblyopic = acuityAmblyopic
        self.acuityFellow = acuityFellow
        self.contrastThresholds = contrastThresholds
        self.binocularBalance = binocularBalance
        self.stereoArcmin = stereoArcmin
        self.stereoNotDetected = stereoNotDetected
        self.durationSeconds = durationSeconds
    }
}

extension AssessmentResult {

    /// Spatial frequencies, in cycles per degree, matching `contrastThresholds`.
    static let contrastSpatialFrequencies: [Double] = [1.5, 3.0, 6.0, 12.0]

    var isComplete: Bool {
        acuityAmblyopic != nil && !contrastThresholds.isEmpty
            && binocularBalance != nil && (stereoArcmin != nil || stereoNotDetected)
    }

    /// Difference between the two eyes. The number most users actually care
    /// about, and the one that shrinks when training is working.
    var interocularAcuityGap: Double? {
        guard let a = acuityAmblyopic, let f = acuityFellow else { return nil }
        return a - f
    }

    /// Single scalar for the contrast curve — the area under it, higher = better.
    /// Uses -log10(threshold) so the value rises as sensitivity improves.
    var contrastSensitivityIndex: Double? {
        guard !contrastThresholds.isEmpty else { return nil }
        let sensitivities = contrastThresholds.map { t -> Double in
            guard t > 0 else { return 0 }
            return -log10(min(max(t, 0.0001), 1.0))
        }
        return sensitivities.reduce(0, +) / Double(sensitivities.count)
    }

    func value(for test: AssessmentTest) -> Double? {
        switch test {
        case .acuity: acuityAmblyopic
        case .contrast: contrastSensitivityIndex
        case .balance: binocularBalance
        case .stereo: stereoArcmin
        }
    }
}
