//
//  AmblyoSchema.swift
//
//  Schema definition and container construction.
//
//  VERSIONING RULE: once a build is on TestFlight, never edit a @Model in place
//  in a way that changes storage. Add a new VersionedSchema and a migration
//  stage. Lightweight migration covers added optional properties and renames
//  with @Attribute(originalName:); anything else needs a custom stage.
//
//  docs/04-ARCHITECTURE.md section 3.
//

import Foundation
import SwiftData

// MARK: - Versioned schemas

enum AmblyoSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Profile.self,
            CalibrationProfile.self,
            SessionRecord.self,
            TrialRecord.self,
            AssessmentResult.self,
            AppMetadata.self
        ]
    }
}

enum AmblyoMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [AmblyoSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// MARK: - Convenience

enum AmblyoSchema {
    /// Current model set. Keep complete — a missing type is a silent failure.
    static var models: [any PersistentModel.Type] { AmblyoSchemaV1.models }

    static var current: Schema { Schema(versionedSchema: AmblyoSchemaV1.self) }
}

// MARK: - App-level bookkeeping (not user data)

@Model
final class AppMetadata {
    var schemaVersion: Int
    var firstLaunchedAt: Date
    var lastOpenedAt: Date
    /// Bumped when the user is shown the review prompt, so we respect Apple's cap.
    var lastReviewPromptAt: Date?
    /// Set once demo data has been seeded, so it is never seeded twice.
    var demoDataSeeded: Bool

    init(
        schemaVersion: Int = 1,
        firstLaunchedAt: Date = .now,
        lastOpenedAt: Date = .now,
        lastReviewPromptAt: Date? = nil,
        demoDataSeeded: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.firstLaunchedAt = firstLaunchedAt
        self.lastOpenedAt = lastOpenedAt
        self.lastReviewPromptAt = lastReviewPromptAt
        self.demoDataSeeded = demoDataSeeded
    }
}

// MARK: - Container factory

extension ModelContainer {

    /// The app's container.
    ///
    /// v1.0 is local-only: no CloudKit. That keeps the App Privacy label at
    /// "Data Not Collected" (docs/08-COMPLIANCE-LEGAL.md section 6). Adding
    /// CloudKit in v1.1 changes that answer — do it deliberately.
    static func amblyo(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "Amblyo",
            schema: AmblyoSchema.current,
            isStoredInMemoryOnly: inMemory,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: AmblyoSchema.current,
            migrationPlan: AmblyoMigrationPlan.self,
            configurations: configuration
        )
    }
}
