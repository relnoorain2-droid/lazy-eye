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
        // AN IN-MEMORY STORE MUST NOT CARRY A FILE-BACKED NAME.
        //
        // This passed the name "Amblyo" in both cases. A named configuration
        // resolves to a file URL, so even with `isStoredInMemoryOnly` the
        // store still reached for Application Support/Amblyo.store — which is
        // why EVERY CI run, green or red, printed:
        //
        //     CoreData: error: Failed to stat path '.../Amblyo.store'
        //     Failed to statfs file; errno 2 / No such file or directory.
        //
        // Those lines were dismissed as simulator noise for eleven runs. They
        // were the store describing a contradiction it had been handed, and
        // the app then aborted inside `NSSQLFetchRequestContext
        // _createStatement` — a fetch against a store that could not decide
        // where it lived.
        //
        // Named on disk, anonymous in memory.
        let configuration = inMemory
            ? ModelConfiguration(
                schema: AmblyoSchema.current,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none)
            : ModelConfiguration(
                "Amblyo",
                schema: AmblyoSchema.current,
                isStoredInMemoryOnly: false,
                allowsSave: true,
                cloudKitDatabase: .none)
        return try ModelContainer(
            for: AmblyoSchema.current,
            migrationPlan: AmblyoMigrationPlan.self,
            configurations: configuration
        )
    }

    /// Deletes the on-disk store so a fresh one can be created.
    ///
    /// LAST RESORT, AND IT DESTROYS USER DATA.
    /// Only called when the store will not open at all — a failed migration or
    /// a corrupt file — where the alternative is an app that launches into an
    /// empty in-memory store and quietly loses everything the user does from
    /// then on. Rebuilding is not better than migrating; it is better than
    /// pretending. Whoever calls this must tell the user.
    ///
    /// SwiftData keeps three files, and removing only the .store leaves the
    /// write-ahead log and shared-memory files behind, which can resurrect the
    /// same failure. All three go.
    static func destroyAmblyoStore() throws {
        let directory = URL.applicationSupportDirectory
        let base = directory.appending(path: "Amblyo.store")
        let files = [base,
                     directory.appending(path: "Amblyo.store-wal"),
                     directory.appending(path: "Amblyo.store-shm")]
        for file in files where FileManager.default.fileExists(atPath: file.path()) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
