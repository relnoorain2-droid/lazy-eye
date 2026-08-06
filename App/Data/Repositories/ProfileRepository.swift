//
//  ProfileRepository.swift
//
//  All Profile reads and writes go through here. Views never touch ModelContext
//  directly — that keeps the free/Pro profile limit and the "exactly one active
//  profile" invariant in one place instead of scattered across the UI.
//
//  docs/04-ARCHITECTURE.md section 2.
//

import Foundation
import SwiftData

@MainActor
struct ProfileRepository {

    let context: ModelContext

    init(context: ModelContext) { self.context = context }

    // MARK: Limits

    /// docs/07-MONETIZATION-PAYWALL.md section 3.
    static let freeProfileLimit = 1
    static let proProfileLimit = 5

    static func limit(isPro: Bool) -> Int { isPro ? proProfileLimit : freeProfileLimit }

    // MARK: Reads

    func all() throws -> [Profile] {
        try context.fetch(
            FetchDescriptor<Profile>(sortBy: [SortDescriptor(\.createdAt, order: .forward)])
        )
    }

    func active() throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func profile(id: UUID) throws -> Profile? {
        var descriptor = FetchDescriptor<Profile>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func count() throws -> Int {
        try context.fetchCount(FetchDescriptor<Profile>())
    }

    // MARK: Writes

    enum RepositoryError: LocalizedError {
        case profileLimitReached(limit: Int)
        case cannotDeleteLastProfile

        var errorDescription: String? {
            switch self {
            case .profileLimitReached(let limit):
                "You can have up to \(limit) \(limit == 1 ? "profile" : "profiles")."
            case .cannotDeleteLastProfile:
                "You need at least one profile."
            }
        }
    }

    @discardableResult
    func create(
        name: String,
        birthYear: Int? = nil,
        ageGroup: AgeGroup,
        amblyopicEye: Eye = .unknown,
        wearsCorrection: Bool = false,
        isPro: Bool
    ) throws -> Profile {
        let limit = Self.limit(isPro: isPro)
        guard try count() < limit else {
            throw RepositoryError.profileLimitReached(limit: limit)
        }

        let profile = Profile(
            name: name,
            birthYear: birthYear,
            ageGroup: ageGroup,
            amblyopicEye: amblyopicEye,
            wearsCorrection: wearsCorrection,
            // Under-13 gets the kids skin and the parent gate by default.
            isKidsMode: ageGroup.requiresParentGate,
            isActive: false
        )
        context.insert(profile)
        try makeActive(profile)
        return profile
    }

    /// Exactly one profile is active at a time.
    func makeActive(_ profile: Profile) throws {
        for other in try all() where other.id != profile.id {
            other.isActive = false
        }
        profile.isActive = true
        try context.save()
    }

    func delete(_ profile: Profile) throws {
        let profiles = try all()
        guard profiles.count > 1 else { throw RepositoryError.cannotDeleteLastProfile }

        let wasActive = profile.isActive
        context.delete(profile)          // cascades to sessions, trials, assessments
        try context.save()

        if wasActive, let next = try all().first {
            try makeActive(next)
        }
    }

    // MARK: Calibration

    func setCalibration(_ calibration: CalibrationProfile, for profile: Profile) throws {
        if let existing = profile.calibration, existing !== calibration {
            context.delete(existing)
        }
        calibration.profile = profile
        profile.calibration = calibration
        context.insert(calibration)
        try context.save()
    }

    // MARK: Data control (docs/06-AI-ENGINE-SPEC.md section 6)

    /// One-tap delete-everything. Must remain genuinely complete — the privacy
    /// policy promises it.
    func deleteAllData() throws {
        try context.delete(model: TrialRecord.self)
        try context.delete(model: SessionRecord.self)
        try context.delete(model: AssessmentResult.self)
        try context.delete(model: CalibrationProfile.self)
        try context.delete(model: Profile.self)
        try context.save()
    }
}
