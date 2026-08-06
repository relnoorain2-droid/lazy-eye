//
//  Profile.swift
//
//  A person using the app. Up to 5 per install (Pro); 1 on the free tier.
//  Families with two affected children are a real, common case.
//
//  docs/04-ARCHITECTURE.md section 3.
//

import Foundation
import SwiftData

@Model
final class Profile {

    @Attribute(.unique) var id: UUID
    var name: String
    var birthYear: Int?
    var ageGroupRaw: String
    var amblyopicEyeRaw: String
    var wearsCorrection: Bool
    var isKidsMode: Bool
    var isActive: Bool
    var createdAt: Date

    /// Codable settings blob — see `PreferencesBlob` for why this isn't columns.
    var preferencesData: Data

    @Relationship(deleteRule: .cascade, inverse: \CalibrationProfile.profile)
    var calibration: CalibrationProfile?

    @Relationship(deleteRule: .cascade, inverse: \SessionRecord.profile)
    var sessions: [SessionRecord]

    @Relationship(deleteRule: .cascade, inverse: \AssessmentResult.profile)
    var assessments: [AssessmentResult]

    init(
        id: UUID = UUID(),
        name: String,
        birthYear: Int? = nil,
        ageGroup: AgeGroup = .thirteenPlus,
        amblyopicEye: Eye = .unknown,
        wearsCorrection: Bool = false,
        isKidsMode: Bool = false,
        isActive: Bool = true,
        createdAt: Date = .now,
        preferences: PreferencesBlob = PreferencesBlob()
    ) {
        self.id = id
        self.name = name
        self.birthYear = birthYear
        self.ageGroupRaw = ageGroup.rawValue
        self.amblyopicEyeRaw = amblyopicEye.rawValue
        self.wearsCorrection = wearsCorrection
        self.isKidsMode = isKidsMode
        self.isActive = isActive
        self.createdAt = createdAt
        self.preferencesData = (try? JSONEncoder().encode(preferences)) ?? Data()
        self.sessions = []
        self.assessments = []
    }
}

// MARK: - Typed accessors
//
// SwiftData persists the raw strings; the app only ever touches these.

extension Profile {

    var ageGroup: AgeGroup {
        get { AgeGroup(rawValue: ageGroupRaw) ?? .thirteenPlus }
        set { ageGroupRaw = newValue.rawValue }
    }

    var amblyopicEye: Eye {
        get { Eye(rawValue: amblyopicEyeRaw) ?? .unknown }
        set { amblyopicEyeRaw = newValue.rawValue }
    }

    var fellowEye: Eye { amblyopicEye.fellow }

    var preferences: PreferencesBlob {
        get { (try? JSONDecoder().decode(PreferencesBlob.self, from: preferencesData)) ?? PreferencesBlob() }
        set { preferencesData = (try? JSONEncoder().encode(newValue)) ?? preferencesData }
    }

    /// Planned length for the next session, honouring the user's override and
    /// then the age-group cap. The cap always wins — it is a safety limit.
    var plannedSessionSeconds: Int {
        let requested = preferences.preferredSessionSeconds ?? ageGroup.defaultSessionSeconds
        return min(requested, ageGroup.dailyCapSeconds)
    }

    /// True once the user can start training: eye assigned, disclaimer read,
    /// screen calibrated.
    var isSetUp: Bool {
        amblyopicEye != .unknown
            && preferences.hasAcknowledgedDisclaimer
            && calibration?.isComplete == true
    }

    /// The dichoptic track needs a completed anaglyph calibration and normal
    /// colour vision. docs/05-DESIGN-SYSTEM.md section 8 — when false the track
    /// is HIDDEN, not shown-and-locked.
    var canUseDichopticTrack: Bool {
        guard let cal = calibration else { return false }
        return cal.isAnaglyphCalibrated && cal.colorVisionOK
    }
}
