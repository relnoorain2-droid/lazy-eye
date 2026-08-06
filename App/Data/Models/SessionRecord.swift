//
//  SessionRecord.swift
//  TrialRecord.swift is in the same folder — a session owns many trials.
//
//  docs/04-ARCHITECTURE.md section 3.
//

import Foundation
import SwiftData

@Model
final class SessionRecord {

    @Attribute(.unique) var id: UUID
    var profile: Profile?

    var startedAt: Date
    var endedAt: Date?

    var plannedSeconds: Int
    var actualSeconds: Int

    var trackRaw: String
    var endedReasonRaw: String?

    /// Contrast-rebalance level in force for this session, if dichoptic.
    /// Recorded per session so the ramp can be plotted over time.
    var fellowEyeContrast: Double?

    /// Number of 20-20-20 breaks taken. Surfaced in the exported report.
    var breakCount: Int

    @Relationship(deleteRule: .cascade, inverse: \TrialRecord.session)
    var trials: [TrialRecord]

    init(
        id: UUID = UUID(),
        profile: Profile? = nil,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        plannedSeconds: Int,
        actualSeconds: Int = 0,
        track: Track,
        endedReason: EndReason? = nil,
        fellowEyeContrast: Double? = nil,
        breakCount: Int = 0
    ) {
        self.id = id
        self.profile = profile
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedSeconds = plannedSeconds
        self.actualSeconds = actualSeconds
        self.trackRaw = track.rawValue
        self.endedReasonRaw = endedReason?.rawValue
        self.fellowEyeContrast = fellowEyeContrast
        self.breakCount = breakCount
        self.trials = []
    }
}

extension SessionRecord {

    var track: Track {
        get { Track(rawValue: trackRaw) ?? .monocular }
        set { trackRaw = newValue.rawValue }
    }

    var endedReason: EndReason? {
        get { endedReasonRaw.flatMap(EndReason.init(rawValue:)) }
        set { endedReasonRaw = newValue?.rawValue }
    }

    var isFinished: Bool { endedAt != nil }

    /// A session counts toward adherence if the user did most of what was
    /// planned. Deliberately generous — punishing a 70%-complete session is how
    /// you lose the users who need the habit most.
    var countsTowardAdherence: Bool {
        guard let reason = endedReason, reason.producesValidData else { return false }
        guard plannedSeconds > 0 else { return false }
        return Double(actualSeconds) / Double(plannedSeconds) >= 0.6
    }

    var completionRatio: Double {
        guard plannedSeconds > 0 else { return 0 }
        return min(1.0, Double(actualSeconds) / Double(plannedSeconds))
    }

    /// Trials usable for threshold estimation: valid session, and the trial
    /// itself wasn't discarded for a dropped frame.
    var validTrials: [TrialRecord] {
        guard endedReason?.producesValidData ?? false else { return [] }
        return trials.filter { !$0.discarded }
    }

    var accuracy: Double? {
        let valid = validTrials
        guard !valid.isEmpty else { return nil }
        return Double(valid.filter(\.correct).count) / Double(valid.count)
    }

    var day: Date { Calendar.current.startOfDay(for: startedAt) }
}
